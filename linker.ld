ENTRY(_start)

MEMORY {
  RAM (rwx) : ORIGIN = 0x80200000, LENGTH = 125M
}

SECTIONS {
  .text : {
    KEEP(*(.text.init))
    . = ALIGN(16);
    *(.text.interrupt)
    *(.text*)
  } > RAM

  .rodata : {
    *(.rodata*)
  } > RAM

  .data : {
    *(.data*)
  } > RAM

  .bss (NOLOAD) : {
    _bss_start = .;
    *(.bss*)
    _bss_end = .;
  } > RAM

  _stack_top = 0x87d00000;
}