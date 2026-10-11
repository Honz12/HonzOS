; ======= Systems Info =======
;
; BIOS - Basic Input Output System
;
; Page Number (AI definition):
;   Page numbers in text mode BIOS refer to the display pages
;   that can be accessed and manipulated using BIOS interrupts.
;   Each page can show different content, allowing for multiple
;   screens of text to be managed in memory.
;
; ============================

; ====== Instruction Info =======
;
;   LODSB, LODSW, LODSD
;   - loads a byte/word/dword form DS:SI into AL/AX/EAX,
;     increments SI by the size when done
;
;   MOV a, b
;   - a = b
;     `b` can be a constant or a register 
;
; ===============================

%define ENDL 0x0D, 0x0A

org 0x7C00
bits 16

;
; FAT12 header
; 
jmp short start
nop

bdb_oem:                    db 'MSWIN4.1'           ; 8 bytes
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 0x0E0
bdb_total_sectors:          dw 2880                 ; 2880 * 512 = 1.44MB
bdb_media_descriptor_type:  db 0x0F0                ; F0 = 3.5" floppy disk
bdb_sectors_per_fat:        dw 9                    ; 9 sectors/fat
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_sector_count:     dd 0

; extended boot record
ebr_drive_number:           db 0                    ; 0x00 floppy, 0x80 hdd, useless
                            db 0                    ; reserved
ebr_signature:              db 29h
ebr_volume_id:              db 12h, 34h, 56h, 78h   ; serial number, value doesn't matter
ebr_volume_label:           db 'HonzOS     '        ; 11 bytes, padded with spaces
ebr_system_id:              db 'FAT12   '           ; 8 bytes

;
; Bootloader code
;

start:
    jmp main

;
; Prints a null-terminater string to the screen
; PARAMS:
;   - ds:si point to string
;
puts:
    ; save what we modify
    push si
    push ax

.loop:
    lodsb               ; loads character into AL
    or al, al           ; verify if next character is null?
    jz .done

    mov ah, 0x0e        ; BIOS > VIDEO-INT > CHAR-OUT
    mov bh, 0           ; Page number
    int 0x10

    jmp .loop

.done:
    pop ax
    pop si

    ret

main:
    ; setup data segments
    mov ax, 0
    mov ds, ax          ; cant write to DS/ES directly
    mov es, ax

    ; setup stack
    mov ss, ax
    mov sp, 0x7C00

    ; print message
    mov si, msg_hello
    call puts

    hlt

.halt:
    jmp .halt

msg_hello: db 'Hello world', ENDL, 0

times 510-($-$$) db 0   ; pad program
dw 0AA55h               ; word
