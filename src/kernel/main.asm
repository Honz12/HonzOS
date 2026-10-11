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
