; HTPROBE.COM - one-shot HT12 register probe (8086/286 code)
; Usage: HTPROBE ii vv ssss
;   ii   = HT12 register index (hex)
;   vv   = value to write for the test (hex)
;   ssss = segment to test-write at offset 0010h (hex)
; Steps, with interrupts off, so the odd state lasts only microseconds:
;   read reg -> set vv -> read reg back -> read seg:10 -> write 4 bytes -> read seg:10
;   -> restore reg -> read seg:10 again. Then prints everything.
        cpu 286
        org 100h

start:  mov si,81h
        call gethex
        mov [idx],al
        call gethex
        mov [val],al
        call gethex
        mov [sgm],ax

        mov es,[sgm]
        mov dx,1EDh
        cli
        mov al,[idx]
        out dx,al
        jmp $+2
        mov dx,1EFh
        in al,dx
        mov [orig],al
        ; read before
        mov ax,[es:10h]
        mov [bef],ax
        mov ax,[es:12h]
        mov [bef+2],ax
        ; set the test value
        mov dx,1EDh
        mov al,[idx]
        out dx,al
        jmp $+2
        mov dx,1EFh
        mov al,[val]
        out dx,al
        jmp $+2
        mov dx,1EDh
        mov al,[idx]
        out dx,al
        jmp $+2
        mov dx,1EFh
        in al,dx
        mov [rb],al
        ; read in the test state, then write the pattern and read it back
        mov ax,[es:10h]
        mov [dur0],ax
        mov ax,[es:12h]
        mov [dur0+2],ax
        mov al,0C0h
        mov ah,[val]
        mov [es:10h],ax                 ; bytes C0 vv
        mov al,[idx]
        mov ah,0EEh                     ; bytes EE idx
        xchg al,ah
        mov [es:12h],ax
        mov ax,[es:10h]
        mov [dur1],ax
        mov ax,[es:12h]
        mov [dur1+2],ax
        ; restore the register
        mov dx,1EDh
        mov al,[idx]
        out dx,al
        jmp $+2
        mov dx,1EFh
        mov al,[orig]
        out dx,al
        jmp $+2
        mov ax,[es:10h]
        mov [aft],ax
        mov ax,[es:12h]
        mov [aft+2],ax
        sti

        mov dx,m_reg
        call puts
        mov al,[idx]
        call phex
        mov dx,m_orig
        call puts
        mov al,[orig]
        call phex
        mov dx,m_set
        call puts
        mov al,[val]
        call phex
        mov dx,m_rb
        call puts
        mov al,[rb]
        call phex
        mov dx,m_seg
        call puts
        mov ax,[sgm]
        xchg al,ah
        call phex
        xchg al,ah
        call phex
        mov dx,m_bef
        call puts
        mov si,bef
        call p4
        mov dx,m_dur0
        call puts
        mov si,dur0
        call p4
        mov dx,m_dur1
        call puts
        mov si,dur1
        call p4
        mov dx,m_aft
        call puts
        mov si,aft
        call p4
        mov dx,m_crlf
        call puts
        mov ax,4C00h
        int 21h

; gethex: skip blanks at [si], parse hex digits -> AX
gethex: xor bx,bx
.sk:    lodsb
        cmp al,' '
        je .sk
        cmp al,9
        je .sk
.dig:   cmp al,'0'
        jb .end
        cmp al,'9'
        jbe .num
        and al,0DFh
        cmp al,'A'
        jb .end
        cmp al,'F'
        ja .end
        sub al,7
.num:   sub al,'0'
        shl bx,4
        or bl,al
        lodsb
        jmp .dig
.end:   mov ax,bx
        ret

puts:   mov ah,9
        int 21h
        ret

; phex: AL as 2 hex digits
phex:   push ax
        push ax
        shr al,4
        call nib
        pop ax
        and al,0Fh
        call nib
        pop ax
        ret
nib:    add al,'0'
        cmp al,'9'
        jbe .o
        add al,7
.o:     push ax
        mov dl,al
        mov ah,2
        int 21h
        pop ax
        ret
; p4: 4 bytes at [si] as hex with spaces
p4:     mov cx,4
.l:     lodsb
        call phex
        mov dl,' '
        mov ah,2
        int 21h
        loop .l
        ret

m_reg   db 'HTPROBE reg $'
m_orig  db ' was $'
m_set   db ' set $'
m_rb    db ' read back $'
m_seg   db 13,10,'seg $'
m_bef   db ':0010  before: $'
m_dur0  db 13,10,'  in test state: $'
m_dur1  db 13,10,'  after write  : $'
m_aft   db 13,10,'  restored     : $'
m_crlf  db 13,10,'$'

idx     db 0
val     db 0
orig    db 0
rb      db 0
sgm     dw 0
bef     dd 0
dur0    dd 0
dur1    dd 0
aft     dd 0
