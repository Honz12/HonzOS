#include "disk.h"
#include "x86.h"

bool DISK_Initialize(DISK* disk, uint8_t driveNumber) {
    uint8_t driveType;
    uint16_t cylinders, sectors, heads;

    if (!x86_Disk_GetDriveParams(
        driveNumber,
        &driveType,
        &cylinders,
        &sectors,
        &heads
    )) {
        return false;
    }

    disk->id = driveNumber;
    disk->cylinders = cylinders;
    disk->heads = heads;
    disk->sectors = sectors;

    return true;
}

void DISK_LBA_TO_CHS(
    DISK* disk,
    uint32_t lba,
    uint16_t* cylinderOut,
    uint16_t* sectorOut,
    uint16_t* headOut
) {
    *sectorOut = lba % disk->sectors + 1;
    *cylinderOut = (lba / disk->sectors) / disk->heads;
    *headOut = (lba / disk->sectors) % disk->heads;
}

bool DISK_ReadSectors(
    DISK* disk,
    uint32_t lba,
    uint8_t sectors,
    uint8_t far* dataOut
) {
    return true;
}
