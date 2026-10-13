#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#define true 1
#define false 0

typedef struct {
    uint8_t BootJumpInstruction[3];
    
    uint8_t OemIdentifier[8];
    uint16_t BytesPerSector;
    uint8_t SectorsPerCluster;
    uint16_t ReservedSectors;
    uint8_t FatCount;
    uint16_t DirEntryCount;
    uint16_t TotalSectors;
    uint8_t MediaDescriptorType;
    uint16_t SectorsPerFat;
    uint16_t SectorsPerTrack;
    uint16_t Heads;
    uint32_t HiddenSectors;
    uint32_t LargeSectorCount;

    // extended boot record
    uint8_t DriveNumber;
    uint8_t _Reserved;
    uint8_t Signature;
    uint32_t VolumeId;          // serial number, value doesn't matter
    uint8_t VolumeLabel[11];    // 11 bytes, padded with spaces
    uint8_t SystemId[8];

    // ... we don't care about code ...
} __attribute__((packed)) BootSector;

typedef struct {
    uint8_t Name[11];
    uint8_t Attributes;
    uint8_t _Reserved;
    uint8_t CreatedTimeTenths;
    uint16_t CreatedTime;
    uint16_t CreatedDate;
    uint16_t AccessedDate;
    uint16_t FirstClusterHigh;
    uint16_t ModifiedTime;
    uint16_t ModifiedDate;
    uint16_t FirstClusterLow;
    uint32_t Size;
} __attribute__((packed)) DirectoryEntry;

BootSector g_boot_sector;
uint8_t* g_fat = NULL;
DirectoryEntry* g_root_directory = NULL;
uint32_t g_root_directory_end = 0;

bool read_boot_sector(FILE* disk) {
    return fread(&g_boot_sector, sizeof(g_boot_sector), 1, disk) > 0;
}

bool read_sectors(FILE* disk, uint32_t lba, uint32_t count, void* bufferOut) {
    bool ok = true;
    ok = ok && (fseek(disk, lba * g_boot_sector.BytesPerSector, SEEK_SET) == 0);
    ok = ok && (fread(bufferOut, g_boot_sector.BytesPerSector, count, disk));
}

bool read_fat(FILE* disk) {
    g_fat = (uint8_t*) malloc(g_boot_sector.SectorsPerFat * g_boot_sector.BytesPerSector);
    return read_sectors(disk, g_boot_sector.ReservedSectors, g_boot_sector.SectorsPerFat, g_fat);
}

bool read_root_directory(FILE* disk) {
    uint32_t lba = g_boot_sector.ReservedSectors + g_boot_sector.SectorsPerFat * g_boot_sector.FatCount;
    uint32_t size = sizeof(DirectoryEntry) * g_boot_sector.DirEntryCount;
    uint32_t sectors = (size / g_boot_sector.BytesPerSector);
    if (size % g_boot_sector.BytesPerSector > 0) {
        sectors++;
    }

    g_root_directory_end = lba + sectors;
    g_root_directory = (DirectoryEntry*) malloc(sectors * g_boot_sector.BytesPerSector);
    return read_sectors(disk, lba, sectors, g_root_directory);
}

DirectoryEntry* find_file(const char* name) {
    for (uint32_t i = 0; i < g_boot_sector.DirEntryCount; i++) {
        if (memcmp(name, g_root_directory[i].Name, 11) == 0) {
            return &g_root_directory[i];
        }
    }

    return NULL;
}

bool read_file(DirectoryEntry* file_entry, FILE* disk, uint8_t* output_buffer) {
    bool ok = true;
    uint16_t current_cluster = file_entry->FirstClusterLow;

    do {
        uint32_t lba = g_root_directory_end + (current_cluster - 2) * g_boot_sector.SectorsPerCluster;
        ok = ok && read_sectors(disk, lba, g_boot_sector.SectorsPerCluster, output_buffer);
        output_buffer += g_boot_sector.SectorsPerCluster * g_boot_sector.BytesPerSector;

        uint32_t fat_index = current_cluster * 3 / 2;
        if (current_cluster % 2 == 0) {
            current_cluster = (*(uint16_t*)(g_fat + fat_index)) & 0x0FFF;
        }
        else {
            current_cluster = (*(uint16_t*)(g_fat + fat_index)) >> 4;
        }
    } while (ok && current_cluster < 0xFF8);

    return ok;
}

int main(int argc, char** argv) {
    if (argc < 3) {
        printf("Syntax: %s <disk image> <file name>\n", argv[0]);
        return -1;
    }

    FILE* disk = fopen(argv[1], "rb");

    if (!disk) {
        fprintf(stderr, "Cannot open disk image %s!", argv[1]);
        return -1;
    }

    if (!read_boot_sector(disk)) {
        fprintf(stderr, "Failed to read boot sector!");
        return -2;
    }

    if (!read_fat(disk)) {
        fprintf(stderr, "Failed to read FAT!\n");
        free(g_fat);
        return -3;
    }

    if (!read_root_directory(disk)) {
        fprintf(stderr, "Failed to read root directory!\n");
        free(g_fat);
        free(g_root_directory);
        return -4;
    }

    DirectoryEntry* file_entry = find_file(argv[2]);
    if (!file_entry) {
        fprintf(stderr, "File %s does not exist!\n", argv[2]);
        free(g_fat);
        free(g_root_directory);
        return -5;
    }

    uint8_t* buffer = (uint8_t*) malloc(file_entry->Size + g_boot_sector.BytesPerSector);
    if (!read_file(file_entry, disk, buffer)) {
        fprintf(stderr, "Failed to read file %s!\n", argv[2]);
        free(g_fat);
        free(g_root_directory);
        free(buffer);
        return -6;
    }

    for (size_t i = 0; i < file_entry->Size; i++) {
        if (isprint(buffer[i]) || buffer[i] == '\n') fputc(buffer[i], stdout);
        else printf("<%02x>", buffer[i]);
    }
    printf("\n");

    free(buffer);
    free(g_fat);
    free(g_root_directory);
    return 0;
}
