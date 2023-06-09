FASM.DLL

A simple DLL which allows to assemble just inside the memory. 

Short description of functions inside FASM.DLL


fasm_GetVersion()

  Returns double word containg major version in lower 16 bits,
  and minor version in the higher 16 bits.

fasm_Assemble(lpSource,lpMemory,cbMemorySize,nPassesLimit,hDisplayPipe)

  Assembles the given source, using the provided memory block as a free
  storage space (which is also to contain generated output).

  The lpSource should contain a pointer to zero-ended source text.

  The lpMemory should be a pointer to the memory block and cbMemorySize
  should contain its size. In the beginning of this memory block the
  FASM_STATE structure will reside (as defined in FASM.ASH). The assembler
  doesn't allocate any memory beside this block, if it is not enough for
  its purposes, the function returns with FASM_OUT_OF_MEMORY state.

  The nPassesLimit should be a value in range from 1 to 65536, defining
  the maximum number of passes the assembler can perform in order to
  generate the code (the recommended value is 100). If the limit is reached,
  the function returns with state FASM_CANNOT_GENERATE_CODE.

  The hDisplayPipe should contain handle of the pipe, to which the output
  of DISPLAY directives will be written. If this parameter is NULL, all
  the display will get discarded.

  If the assembly is successful, function returns FASM_OK value and fills
  the output_data and output_length fields of the FASM_STATE structure
  (which resides at the beginning of provided memory block) with pointer
  to the generated output and count of bytes stored there.

  If the assembly failed, function returns one of the other general
  conditions as defined in FASM.ASH. If the condition returned is FASM_ERROR,
  it means that an error caused by a specific place in source occured,
  then the error_code and error_line fields of FASM_STATE are filled,
  first one with detailed error code as defined in FASM.ASH, and the second
  one with pointer to a structure containing data about line that caused
  the error.

fasm_AssembleFile(lpSourceFile,lpMemory,cbMemorySize,nPassesLimit,hDisplayPipe)

  This function performs identically to fasm_Assemble, except that it takes
  the lpSourceFile parameter in place of lpSource, and it shall contain the
  pointer to zero-ended path to file containing the source to assemble.
