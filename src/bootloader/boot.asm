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

    ; read something from the floppy disk
    ; BIOS should set DL to drive number
    mov [ebr_drive_number], dl

    mov ax, 1           ; LBA = 1 (second sector from disk)
    mov cl, 1           ; NUM_SECTORS = 1
    mov bx, 0x7E00      ; Data should be after bootloader
    call disk_read

    ; print message
    mov si, msg_hello
    call puts

    hlt

floppy_error:
    
    hlt

wait_key_and_reboot:
    mov ah, 0
    int 0x16                        ; wait for keypress
    jmp 0xFFFF:0                    ; jump to start of BIOS (reboot)

.halt:
    cli                             ; disable interrupts so CPU cant get out of "halt" state
    hlt

;
; Disk routines
;

;
; Converts an LBA to CHS address
; PARAMS:
;   - ax: LBA address
; RETURNS?
;   - cx [bits 0-5]: sector number
;   - cx [bits 6-15]: cylinder
;   - dh: head

lba_to_chs:
    push ax
    push dx

    xor dx, dx                          ; DX = 0
    div word [bdb_sectors_per_track]    ; AX = LBA / SECTORS_PER_TRACK
                                        ; DX = LBA % SECTORS_PER_TRACK

    inc dx                              ; DX = LBA % SECTORS_PER_TRACK + 1 = sector
    mov cx, dx

    xor dx, dx                          ; DX = 0
    div word [bdb_heads]                ; AX = (LBA / SECTORS_PER_TRACK) / HEADS = cylinder
                                        ; DX = (LBA / SECTORS_PER_TRACK) % HEADS = head

    mov dh, dl                          ; DH = head
    mov ch, al                          ; CH = cylinder (lower 8 bits)
    shl ah, 6
    or cl, ah                           ; put upper 2 bits of cylinder in CL

    pop ax
    mov dl, al                          ; restore DL
    pop ax

    ret

;
; Reads sectors from disk
; Parameters:
;   - ax: LBA address
;   - cl: number of sectors
;   - dl: drive number
;   - es:bx: memory address where to store read data
;
disk_read:
    push ax                             ; save what we modify
    push bx
    push cx
    push dx
    push di

    push cx                             ; save CL (num of sectors to read)
    call lba_to_chs
    pop ax                              ; AL = number of sectors to read

    mov ah, 0x02                        ; DO RESEARCH !
    mov di, 3                           ; number of attempts to read

.retry:
    pusha                               ; save all registers, we don't know what the BIOS will modify
    stc                                 ; set carry flag, some BIOS'es dont
    int 0x13
    jnc .done                           ; success

    ; read failed
    popa
    call disk_reset

    dec di
    test di, di

.fail:
    ; all attempts are exausted
    jmp floppy_error

.done:
    popa

    pop di                              ; get back registers we modified
    pop dx
    pop cx
    pop bx
    pop ax

    ret

;
; Resets disk controler
; PARAMS:
;   dl: drive number
;
disk_reset:
    pusha
    
    mov ah, 0
    stc
    int 0x13
    jc floppy_error
    
    popa
    ret

msg_hello: db 'Hello world', ENDL, 0
msg_read_failed: db 'FLOPPY READ FAIL', ENDL, 0

times 510-($-$$) db 0   ; pad program
dw 0AA55h               ; word
