/*
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any
means.
*/
OUTPUT_FORMAT("elf32-littleriscv", "elf32-littleriscv", "elf32-littleriscv")
OUTPUT_ARCH(riscv)
ENTRY(crtStart)

MEMORY
{
  FLASH (rx)      : ORIGIN = 0x00000000, LENGTH = 8M /* entire flash, 8 MiB */
  RAM   (xrw)     : ORIGIN = 0x40000000, LENGTH = 8k
}

_stack_size = DEFINED(_stack_size) ? _stack_size : 1k;
_heap_size = DEFINED(_heap_size) ? _heap_size : 0;

SECTIONS {
    /* The program code and other data goes into FLASH */
  .vector : {
    . = ALIGN(4);
    *crt.o(.text);
  } > FLASH

  .text :
  {
    . = ALIGN(4);
    *(.text)           /* .text sections (code) */
    *(.text*)          /* .text* sections (code) */
    *(.rodata)         /* .rodata sections (constants, strings, etc.) */
    *(.rodata*)        /* .rodata* sections (constants, strings, etc.) */
    *(.srodata)        /* .rodata sections (constants, strings, etc.) */
    *(.srodata*)       /* .rodata* sections (constants, strings, etc.) */
  
    *(.eh_frame_hdr)
    *(.eh_frame)

    . = ALIGN(4);
    _etext = .;        /* define a global symbol at end of code */
    _sidata = _etext;  /* This is used by the startup in order to initialize the .data secion */
  } >FLASH

  .rodata :
  {
    *(.rdata)
    *(.rodata .rodata.*)
    *(.gnu.linkonce.r.*)
  } > FLASH

  .ctors :
  {
    . = ALIGN(4);
    _ctors_start = .;
    KEEP(*(.init_array*))
    KEEP (*(SORT(.ctors.*)))
    KEEP (*(.ctors))
    . = ALIGN(4);
    _ctors_end = .;
  } > FLASH

  /* This is the initialized data section
  The program executes knowing that the data is in the RAM
  but the loader puts the initial values in the FLASH (inidata).
  It is one task of the startup to copy the initial values from FLASH to RAM. */
  .data : AT ( _sidata )
  {
    . = ALIGN(4);
    _sdata = .;        /* create a global symbol at data start; used by startup code in order to initialise the .data section in RAM */
    _ram_start = .;    /* create a global symbol at ram start for garbage collector */
    . = ALIGN(4);
    *(.data)           /* .data sections */
    *(.data*)          /* .data* sections */
    *(.gnu.linkonce.d.*)
    . = ALIGN(8);
    PROVIDE( __global_pointer$ = . + 0x800 );
    *(.sdata)           /* .sdata sections */
    *(.sdata*)          /* .sdata* sections */
    *(.gnu.linkonce.s.*)
    . = ALIGN(4);
    _edata = .;        /* define a global symbol at data end; used by startup code in order to initialise the .data section in RAM */
  } >RAM

  /* Uninitialized data section */
  .bss :
  {
    . = ALIGN(4);
    _bss_start  = .;         /* define a global symbol at bss start; used by startup code */
    *(.bss)
    *(.bss*)
    *(.sbss)
    *(.sbss*)
    *(.gnu.linkonce.sb.*)
    *(.gnu.linkonce.b.*)
    *(COMMON)
    . = ALIGN(4);
    _bss_end = .;         /* define a global symbol at bss end; used by startup code */
  } >RAM
	
	_end = .;
	PROVIDE (end = .);

  /* this is to define the start of the heap, and make sure we have a minimum size */
  .heap :
  {
    . = ALIGN(8);
    PROVIDE ( _heap_start = .);    /* define a global symbol at heap start */
    . = . + _heap_size;
    . = ALIGN(8);
    PROVIDE ( _heap_end = .);
  } >RAM

  /* .stack ORIGIN(RAM) + LENGTH(RAM) - _stack_size : */
  .stack :
  {
    . = ALIGN(16);
  /*  PROVIDE(_heap_end = . ); */
    PROVIDE(_stack_end = .);
    . = _stack_size;
    . = ALIGN(16);
    PROVIDE(_stack_start = .);
  } >RAM

}
