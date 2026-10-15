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
    ; setup data segments
    mov ax, 0
    mov ds, ax          ; cant write to DS/ES directly
    mov es, ax

    ; setup stack
    mov ss, ax
    mov sp, 0x7C00

    ; some BIOSes might start at 07C0:0000 instead of 0000:7C00, make sure we are in the
    ; expected location
    push es
    push word .after

    retf
.after:
    
    ; read something from the floppy disk
    ; BIOS should set DL to drive number
    mov [ebr_drive_number], dl

    ; show loading message
    mov si, msg_loading
    call puts

    ; read drive parameters (sectors per track and head count)
    ; instead of relying on data on formated disk
    push es
    mov ah, 0x08
    int 0x13
    jc floppy_error
    pop es

    and cl, 0x3F                    ; remove top 2 bits
    xor ch, ch
    mov [bdb_sectors_per_track], cx ; sector count

    inc dh
    mov [bdb_heads], dh             ; head count

    ; compute LBA of root directory = reserved + fats * sector_per_fat
    ; note: this section can be hardcoded
    mov ax, [bdb_sectors_per_fat]
    mov bl, [bdb_fat_count]
    xor bh, bh
    mul bx
    add ax, [bdb_reserved_sectors]
    push ax

    ; compute size of root directory = (32 * number_of_entries) / bytes_per_sector
    mov ax, [bdb_sectors_per_fat]
    shl ax, 5                       ; ax *= 32
    xor dx, dx                      ; dx = 0
    div word [bdb_bytes_per_sector] ; number of sectors we need to read

    test dx, dx                     ; if dx != 0, add 1
    jz .root_dir_after
    inc ax                          ; division remainder != 0, add 1
                                    ; this meand we have sector only partialy filled with entries
    
.root_dir_after:

    ; read root directory
    mov cl, al                      ; number of sectors to read = size of root directory (in sectors)
    pop ax                          ; ax = LBA of root directory
    mov dl, [ebr_drive_number]      ; dl = drive number (saved previously)
    mov bx, buffer                  ; es:bx = buffer
    call disk_read

    ; search for stage2.bin
    xor bx, bx
    mov di, buffer

.search_stage2:
    mov si, file_stage2_name
    mov cx, 11                      ; compare up to 11 bytes
    push di
    repe cmpsb
    pop di
    je .found_stage2

    add di, 32
    inc bx
    cmp bx, [bdb_dir_entries_count]
    jl .search_stage2

    jmp stage2_not_found_error

.found_stage2:
    ; di should have the address to the entry
    mov ax, [di + 26]               ; first logical cluster field (offset 26)
    mov [stage2_cluster], ax

    ; load FAT from disk into memory
    mov ax, [bdb_reserved_sectors]
    mov bx, buffer
    mov cl, [bdb_sectors_per_fat]
    mov dl, [ebr_drive_number]
    call disk_read

    ; read stage2 and process FAT chain
    mov bx, stage2_LOAD_SEGMENT
    mov es, bx
    mov bx, stage2_LOAD_OFFSET

.load_stage2_loop:

    ; Read next cluster
    mov ax, [stage2_cluster]
    add ax, 31                      ; hard coded for our kind of floppy disk
    
    mov cl, 1
    mov dl, [ebr_drive_number]
    call disk_read

    add bx, [bdb_bytes_per_sector]

    ; compute location of next cluster
    mov ax, [stage2_cluster]
    mov cx, 3
    mul cx
    mov cx, 2
    div cx                          ; ax = index of entry in FAT, dx = cluster mod 2

    mov si, buffer
    add si, ax
    mov ax, [ds:si]                 ; read entry from FAT table at index ax

    or dx, dx
    jz .even

.odd:
    shr ax, 4
    jmp .next_cluster_after

.even:
    and ax, 0x0FFF

.next_cluster_after:
    cmp ax, 0x0FF8                  ; end if chain
    jae .read_finish

    mov [stage2_cluster], ax
    jmp .load_stage2_loop

.read_finish:

    ; jump to our stage2
    mov dl, [ebr_drive_number]      ; boot device in dl

    mov ax, stage2_LOAD_SEGMENT     ; set segment registers
    mov ds, ax
    mov es, ax

    jmp stage2_LOAD_SEGMENT:stage2_LOAD_OFFSET

    ; should never happen
    jmp wait_key_and_reboot

    cli                             ; disable interrupts so CPU cant get out of "halt" state
    hlt

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

floppy_error:
    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

stage2_not_found_error:
    mov si, msg_stage2_not_found
    call puts
    jmp wait_key_and_reboot

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

; STRINGS

file_stage2_name: db 'STAGE2  BIN'
msg_loading: db 'Loading...', ENDL, 0
msg_read_failed: db 'FLOPPY READ FAIL', ENDL, 0
msg_stage2_not_found: db 'STAGE2.BIN NOT FOUND', ENDL, 0

; DATA

stage2_cluster: dw 0

buffer equ 0x7E00

stage2_LOAD_SEGMENT equ 0x2000
stage2_LOAD_OFFSET equ 0

; PAD

times 510-($-$$) db 0   ; pad program
dw 0AA55h               ; word
