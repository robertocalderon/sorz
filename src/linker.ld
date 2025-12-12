ENTRY(_start);

. = 0x80000000;
MEM_START = .;
MEM_SIZE = 128M;
MEM_END = MEM_START + MEM_SIZE;

SECTIONS {
	/* Include entry point at start of binary */
	.text : ALIGN(4K) {
		*(.text.start);
		*(.text .text.*);
	}
	.bss : ALIGN(4K) {
		PROVIDE(bss_start = .);
		*(.bss .bss.*);
		*(.sbss .sbss.*);
		. += 16 * 4096;
		PROVIDE(_fw_stack_end = .);
		PROVIDE(bss_end = .);
	}
	.rodata : ALIGN(4K) {
		*(.rodata .rodata.*);
		*(.srodata .srodata.*);
		PROVIDE(global_pointer = .);
		.debug_info_start = .;
        KEEP(*(.debug_info))
        .debug_info_end = .;
        .debug_abbrev_start = .;
        KEEP(*(.debug_abbrev))
        .debug_abbrev_end = .;
        .debug_str_start = .;
        KEEP(*(.debug_str))
        .debug_str_end = .;
        .debug_line_start = .;
        KEEP(*(.debug_line))
        .debug_line_end = .;
        .debug_ranges_start = .;
        KEEP(*(.debug_ranges))
        .debug_ranges_end = .;
	}
	.data : ALIGN(4K) {
		*(.data .data*);
		*(.sdata .sdata*);
	}
	. = ALIGN(4096);
	PROVIDE(HEAP_START = .);
	PROVIDE(HEAP_END = MEM_END);
	PROVIDE(HEAP_SIZE = HEAP_END - HEAP_START);
}
