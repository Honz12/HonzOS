%define ENDL 0x0D, 0x0A

org 0
bits 16

start:
    ; print hello message
    mov si, msg_hello
    call puts

    hlt

.halt:
    jmp .halt

; =============================
; Functions
; =============================

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

msg_hello: db 'Welcome to HonzOS v0.1!', ENDL, 0
