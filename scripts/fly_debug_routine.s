.code16
.text
.globl fly_debug_routine
fly_debug_routine:
    pushf
    pusha
    pushw %ds
    movw %sp, %bp

    /* Push fields in reverse final-buffer order; marker ends up last. */
    movw $0xa55a, %ax
    pushw %ax
    pushw 0xbe1b
    pushw 0xcac2
    pushw 0xbe5c
    pushw 0xbe5e
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

    /* Create/truncate FLYDBG.TXT in the game directory. Guest stdout is not
       forwarded to the host when DOSBox-X is launched with redirected stdio,
       so a real file is the reliable evidence channel. */
    pushw %cs
    popw %ds
    movw $0x3c00, %ax
    xorw %cx, %cx
    movw $(debug_filename + 0xd24d), %dx
    int $0x21
    movw %ax, %bx

    /* Write the 34-byte stack buffer to that handle and truncate on next tick. */
    pushw %ss
    popw %ds
    movw %sp, %dx
    movb $0x40, %ah
    movb $34, %cl
    int $0x21

    movw %bp, %sp
    popw %ds
    popa
    popf
    jmp debug_resume

debug_filename:
    .ascii "FLYDBG.TXT\0"
debug_resume:
