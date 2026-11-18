; HT12UMB.SYS - Upper Memory Block driver for the Headland HT12/HT12A (286)
; Bits und Bolts, 2026. NASM: nasm -f bin -o HT12UMB.SYS ht12umb.asm
;
; The HT12 shadow RAM is read-only while it is readable, so it cannot hold
; UMBs. The chip's 4 EMS windows (16K each, one 64K frame at C000..DC00) are
; plain read/write RAM: this driver points them at DRAM pages that are never
; visible otherwise (default: the DRAM behind A0000-AFFFF, pages 28h-2Bh) and
; offers the 64K block to DOS through the XMS driver (functions 10h/11h).
; It cannot run together with an EMS driver (HT12MM.SYS): both need the windows.
;
; CONFIG.SYS:
;   DEVICE=C:\DOS\HIMEM.SYS
;   DEVICE=C:\HT12\HT12UMB.SYS [/F=xxxx] [/P=xx] [/T]
;   DOS=HIGH,UMB
; /F=xxxx  frame segment C000..DC00 in 400h steps (default: lowest free)
; /P=xx    first physical 16K page behind the windows (default 28h = A0000)
; /T       skip the RAM test
;
; HT12 registers used (index port 1EDh, data port 1EFh):
;   17h  revision (high nibble 1 = HT12)    12h/13h shadow bits per 16K block
;   14h  bit 2 = memory relocation          19h  EMS: bit7 on, bits 4-6 frame
;   20h-23h window -> physical 16K page          position, bits 0-3 windows on

        cpu 286
        org 0

IDX     equ 1EDh
DAT     equ 1EFh
UMBPARA equ 1000h               ; 64K in paragraphs

; ---------------------------------------------------------------- header
        dd -1
        dw 8000h                ; character device
        dw strategy
        dw interrupt
        db 'HT12UMB$'

req_ptr         dd 0
xms_next        dd 0            ; HIMEM's code after its hook prologue
umb_seg         dw 0
umb_used        db 0

; ---------------------------------------------------------------- resident
strategy:
        mov [cs:req_ptr],bx
        mov [cs:req_ptr+2],es
        retf

interrupt:
        push ax
        push bx
        push es
        les bx,[cs:req_ptr]
        cmp byte [es:bx+2],0
        jne .other
        call init               ; init lives in the discarded part
        jmp short .done
.other: mov word [es:bx+3],8103h ; error, unknown command
.done:  pop es
        pop bx
        pop ax
        retf

; XMS entry hook: HIMEM's entry now starts with JMP FAR xms_hook
xms_hook:
        cmp ah,10h
        je .req
        cmp ah,11h
        je .rel
        cmp ah,12h
        je .realloc
        jmp far [cs:xms_next]

.req:   cmp byte [cs:umb_used],0
        jne .none
        cmp dx,UMBPARA
        ja .smaller
        mov bx,[cs:umb_seg]
        mov dx,UMBPARA
        mov byte [cs:umb_used],1
        mov ax,1
        retf
.smaller:
        mov dx,UMBPARA
        xor ax,ax
        mov bl,0B0h             ; a smaller UMB is available
        retf
.none:  xor dx,dx
        xor ax,ax
        mov bl,0B1h             ; no UMBs available
        retf

.rel:   cmp byte [cs:umb_used],1
        jne .bad
        cmp dx,[cs:umb_seg]
        jne .bad
        mov byte [cs:umb_used],0
        mov ax,1
        retf
.bad:   xor ax,ax
        mov bl,0B2h             ; invalid UMB segment
        retf

.realloc:
        xor ax,ax
        mov bl,80h              ; not implemented
        retf

resident_end:

; ================================================================ init
; everything below is discarded after init

frame_pos       db 0FFh         ; 0..7, FF = auto
first_page      db 28h
skip_test       db 0
xms_entry       dd 0

init:
        push cx
        push dx
        push si
        push di
        push ds
        push es
        push bx
        push cs
        pop ds
        cld

        mov dx,m_banner
        call puts

        ; --- command line: request header +12h -> text after "DEVICE="
        les bx,[req_ptr]
        les si,[es:bx+12h]
        call parse
        jc fail_opt

        ; --- HT12 present?
        mov dx,IDX
        mov al,17h
        out dx,al
        jmp $+2
        in al,dx
        cmp al,17h              ; index register reads back on the HT12
        jne fail_chip
        mov al,17h
        call rdreg
        and al,0F0h
        cmp al,10h
        jne fail_chip

        ; --- EMS driver loaded? (it owns the windows)
        xor ax,ax
        mov es,ax
        mov es,[es:67h*4+2]
        mov di,0Ah
        mov si,s_emm
        mov cx,8
        repe cmpsb
        je fail_ems

        ; --- no EMS driver: switch off windows a warm boot may have left on
        mov ah,0
        mov al,19h
        call wrreg

        ; --- memory relocation moves the hidden DRAM: refuse the default pages
        mov al,14h
        call rdreg
        test al,04h
        jz .noreloc
        cmp byte [p_given],0
        je fail_reloc
.noreloc:

        ; --- XMS driver with a hookable entry, and no UMB provider yet
        mov ax,4300h
        int 2Fh
        cmp al,80h
        jne fail_xms
        mov ax,4310h
        int 2Fh
        mov [xms_entry],bx
        mov [xms_entry+2],es
        cmp byte [es:bx],0EBh
        jne fail_hook
        cmp word [es:bx+2],9090h
        jne fail_hook
        cmp byte [es:bx+4],90h
        jne fail_hook
        mov ah,10h
        mov dx,0FFFFh
        call far [xms_entry]
        cmp bl,80h              ; HIMEM alone answers "not implemented"
        jne fail_umbthere

        ; --- frame position
        cmp byte [frame_pos],0FFh
        jne .given
        xor cl,cl
.try:   mov al,cl
        call frame_free
        jnc .found
        inc cl
        cmp cl,8
        jb .try
        jmp fail_noframe
.given: mov al,[frame_pos]
        call frame_free
        jc fail_busy
        mov cl,[frame_pos]
.found: mov [frame_pos],cl
        mov al,cl
        xor ah,ah
        shl ax,10               ; pos * 400h
        add ax,0C000h
        mov [umb_seg],ax

        ; --- program the windows: 20h-23h = pages, 19h = on + frame + 4 windows
        mov cl,0
        mov ch,[first_page]
.win:   mov al,20h
        add al,cl
        mov ah,ch
        call wrreg
        call rdreg
        cmp al,ch
        jne fail_regs
        inc ch
        inc cl
        cmp cl,4
        jb .win
        mov ah,[frame_pos]
        shl ah,4
        or ah,8Fh
        mov al,19h
        call wrreg
        call rdreg
        cmp al,ah
        jne fail_regs

        ; --- RAM test: address pattern, then complementary pattern, then zero
        cmp byte [skip_test],0
        jne .tested
        mov es,[umb_seg]
        mov dx,0A55Ah
        call ramtest
        jc fail_ram
        mov dx,055A5h
        call ramtest
        jc fail_ram
.tested:
        mov es,[umb_seg]
        xor di,di
        xor ax,ax
        mov cx,8000h
        cld
        rep stosw

        ; --- hook the XMS entry: EB xx 90 90 90 -> EA off seg
        les bx,[xms_entry]
        mov al,[es:bx+1]
        cbw
        add ax,bx
        add ax,2                ; target of the short jump
        mov [xms_next],ax
        mov [xms_next+2],es
        cli
        mov byte [es:bx],0EAh
        mov word [es:bx+1],xms_hook
        mov [es:bx+3],cs
        sti

        ; --- report
        mov dx,m_ok1
        call puts
        mov ax,[umb_seg]
        call phex4
        mov dx,m_dash
        call puts
        mov ax,[umb_seg]
        add ax,0FFFh
        call phex4
        mov dx,m_ok2
        call puts
        mov al,[first_page]
        call phex2
        mov dx,m_dash
        call puts
        mov al,[first_page]
        add al,3
        call phex2
        mov dx,m_ok3
        call puts

        pop bx
        les bx,[req_ptr]
        mov word [es:bx+0Eh],resident_end
        mov [es:bx+10h],cs
        mov word [es:bx+3],0100h
        jmp short init_ret

; ---------------------------------------------------------------- failures
fail_opt:       mov dx,e_opt
                jmp short fail
fail_chip:      mov dx,e_chip
                jmp short fail
fail_ems:       mov dx,e_ems
                jmp short fail
fail_reloc:     mov dx,e_reloc
                jmp short fail
fail_xms:       mov dx,e_xms
                jmp short fail
fail_hook:      mov dx,e_hook
                jmp short fail
fail_umbthere:  mov dx,e_umb
                jmp short fail
fail_noframe:   mov dx,e_noframe
                jmp short fail
fail_busy:      mov dx,e_busy
                jmp short fail
fail_regs:      mov dx,e_regs
                jmp short fail_off
fail_ram:       mov dx,e_ram
fail_off:       push dx                 ; switch the windows off again
                mov ah,0
                mov al,19h
                call wrreg
                pop dx
fail:   call puts
        mov dx,m_notinst
        call puts
        pop bx
        les bx,[req_ptr]
        mov word [es:bx+0Eh],0  ; nothing stays resident
        mov [es:bx+10h],cs
        mov word [es:bx+3],0100h
init_ret:
        pop es
        pop ds
        pop di
        pop si
        pop dx
        pop cx
        ret

; ---------------------------------------------------------------- helpers
; rdreg: AL = index -> AL = value (AH kept)
rdreg:  push dx
        mov dx,IDX
        out dx,al
        jmp $+2
        mov dx,DAT
        in al,dx
        pop dx
        ret

; wrreg: AL = index, AH = value; AL keeps the index
wrreg:  push dx
        push ax
        mov dx,IDX
        out dx,al
        jmp $+2
        mov dx,DAT
        mov al,ah
        out dx,al
        jmp $+2
        pop ax
        pop dx
        ret

; frame_free: AL = position 0..7 -> CF clear if C000+pos*16K..+64K is empty:
; no shadow bit set for its 4 blocks, no ROM signature, floating bus (FFh)
; and nothing that keeps a written byte.
frame_free:
        push ax
        push bx
        push cx
        push dx
        push es
        mov bl,al               ; block index of the first 16K block (0..7)
        ; shadow bits: blocks 0-7 in reg 12h, 8-15 in reg 13h
        mov al,12h
        call rdreg
        mov ah,al
        mov al,13h
        call rdreg
        xchg al,ah              ; AX = 16 shadow bits, bit n = block n
        mov cl,bl
        shr ax,cl
        test al,0Fh
        jnz .busy
        ; scan every 2K
        mov al,bl
        xor ah,ah
        shl ax,10
        add ax,0C000h
        mov dx,ax               ; DX = segment being checked
        mov cx,32               ; 32 x 2K = 64K
.chunk: mov es,dx
        cmp word [es:0],0AA55h
        je .busy
        cmp word [es:0],0FFFFh
        jne .busy
        cmp word [es:200h],0FFFFh
        jne .busy
        cmp word [es:400h],0FFFFh
        jne .busy
        cmp word [es:600h],0FFFFh
        jne .busy
        mov al,[es:7FFh]        ; RAM there? (nothing answers on an empty bus)
        mov byte [es:7FFh],5Ah
        mov ah,[es:7FFh]
        mov [es:7FFh],al        ; put back what was there
        cmp ah,5Ah
        je .busy
        add dx,80h
        loop .chunk
        clc
        jmp short .out
.busy:  stc
.out:   pop es
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ramtest: ES = UMB segment, DX = seed -> CF set on error
; write word (offset XOR seed) everywhere, then verify (finds address faults)
ramtest:
        push ax
        push cx
        push di
        cld
        xor di,di
        mov cx,8000h
.w:     mov ax,di
        xor ax,dx
        stosw
        loop .w
        xor di,di
        mov cx,8000h
.v:     mov ax,di
        xor ax,dx
        scasw
        jne .err
        loop .v
        clc
        jmp short .x
.err:   stc
.x:     pop di
        pop cx
        pop ax
        ret

; parse: ES:SI -> DEVICE= line. Skips the file name, reads /F= /P= /T.
parse:  mov byte [p_given],0
.name:  mov al,[es:si]
        cmp al,' '
        jbe .opts
        inc si
        jmp .name
.opts:  mov al,[es:si]
        inc si
        cmp al,0
        je .ok
        cmp al,13
        je .ok
        cmp al,10
        je .ok
        cmp al,'/'
        jne .opts
        mov al,[es:si]
        inc si
        and al,0DFh
        cmp al,'T'
        je .t
        cmp al,'F'
        je .f
        cmp al,'P'
        je .p
        stc
        ret
.t:     mov byte [skip_test],1
        jmp .opts
.f:     call optval
        jc .bad
        sub ax,0C000h
        jb .bad
        test ax,03FFh
        jnz .bad
        shr ax,10
        cmp ax,8
        jae .bad
        mov [frame_pos],al
        jmp .opts
.p:     call optval
        jc .bad
        cmp ax,0FCh
        ja .bad
        mov [first_page],al
        mov byte [p_given],1
        jmp .opts
.ok:    clc
        ret
.bad:   stc
        ret

; optval: ES:SI at '=' or ':' then hex digits -> AX, CF on error
optval: mov al,[es:si]
        cmp al,'='
        je .sep
        cmp al,':'
        jne .bad
.sep:   inc si
        xor bx,bx
        xor cx,cx
.dig:   mov al,[es:si]
        cmp al,'0'
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
        inc si
        inc cx
        jmp .dig
.end:   jcxz .bad
        mov ax,bx
        clc
        ret
.bad:   stc
        ret

puts:   mov ah,9
        int 21h
        ret

phex4:  xchg al,ah
        call phex2
        xchg al,ah
phex2:  push ax
        shr al,4
        call .nib
        pop ax
        push ax
        and al,0Fh
        call .nib
        pop ax
        ret
.nib:   push ax
        push dx
        add al,'0'
        cmp al,'9'
        jbe .o
        add al,7
.o:     mov dl,al
        mov ah,2
        int 21h
        pop dx
        pop ax
        ret

p_given         db 0
s_emm           db 'EMMXXXX0'
m_banner        db 13,10,'HT12UMB 1.0 - UMB driver for the Headland HT12 (Bits und Bolts 2026)',13,10,'$'
m_ok1           db '  64K upper memory at $'
m_dash          db '-$'
m_ok2           db ', DRAM pages $'
m_ok3           db 'h. Use DOS=UMB.',13,10,'$'
m_notinst       db '  HT12UMB not installed.',13,10,'$'
e_opt           db '  Bad option. Use /F=xxxx /P=xx /T',13,10,'$'
e_chip          db '  No Headland HT12 chipset found.',13,10,'$'
e_ems           db '  An EMS driver is loaded - it uses the EMS windows HT12UMB needs.',13,10,'$'
e_reloc         db '  Memory relocation is on - give the pages with /P=xx.',13,10,'$'
e_xms           db '  No XMS driver - load HIMEM.SYS first.',13,10,'$'
e_hook          db '  The XMS driver cannot be hooked.',13,10,'$'
e_umb           db '  Another UMB provider is already loaded.',13,10,'$'
e_noframe       db '  No free 64K area between C000 and EBFF.',13,10,'$'
e_busy          db '  The /F area is not free (ROM, RAM or shadow).',13,10,'$'
e_regs          db '  HT12 EMS registers did not take the values.',13,10,'$'
e_ram           db '  RAM test failed.',13,10,'$'
