.code16
.text
.globl fly_debug_routine
fly_debug_routine:
    pusha
    pushw %ds
    movw %sp, %bp

    /* Push fields in reverse final-buffer order; marker ends up last. */
    movw $0xa55a, %ax
    pushw %ax
    pushw 0x7d7a
    pushw 0xbe1b
    pushw 0xcac2
    pushw 0x46fe
    pushw 0x4712
    pushw 0x4724
    pushw 0x476e
    pushw 0xf332
    pushw 0xf334
    pushw 0xf336
    pushw 0xf338
    pushw 0xf33a
    pushw 0xf33c
    pushw 0x5f1e
    pushw 0xf33b

    /* Append one record to FLYDBG.TXT. The file is pre-created empty. */
    pushw %cs
    popw %ds
    movw $0x3d01, %ax
    xorw %cx, %cx
    movw $(debug_filename + 0xd24d), %dx
    int $0x21
    movw %ax, %bx
    movw $0x4202, %ax
    xorw %cx, %cx
    xorw %dx, %dx
    int $0x21

    pushw %ss
    popw %ds
    movw %sp, %dx
    movb $0x40, %ah
    movb $32, %cl
    int $0x21
    movb $0x3e, %ah
    int $0x21

    movw %bp, %sp
    popw %ds
    popa
    jmp debug_resume

debug_filename:
    .ascii "FLYDBG.TXT\0"
debug_resume:
