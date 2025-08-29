.section .text.init
.global _start
_start:
    # Set up stack pointer
    la sp, _stack_top
    
    # Clear BSS section
    la t0, _bss_start
    la t1, _bss_end
clear_bss:
    beq t0, t1, done_bss
    sd zero, 0(t0)
    addi t0, t0, 8
    j clear_bss
done_bss:
    
    # Jump to Zig main (from program.zig)
    call main
    
    # Should never return, but if it does, halt
halt:
    wfi
    j halt