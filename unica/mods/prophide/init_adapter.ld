ENTRY(prophide_property_set)
SECTIONS {
    . = 0xb57100;
    .prophide : { *(.text.entry) *(.text*) *(.rodata*) }
    /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) *(.llvm*) }
}
