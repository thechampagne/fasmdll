
; flat assembler DLL interface for Win32
; Copyright (c) 1999-2018, Tomasz Grysztar.
; All rights reserved.

format PE64 DLL GUI 5.0
entry DLLEntryPoint

include 'win64a.inc'
include '..\fasm.ash'

macro invoke proc,args&
 { local size,current
   push r15
   mov r15,rsp
   if size
    sub rsp,size
   end if
   and rsp,-16
   current = 0
   current@frame equ current
   size@frame equ size
   invoke proc,args
   size@frame = current@frame
   mov rsp,r15
   pop r15
   restore size@frame,current@frame }

section '.data' data readable writeable

mutex dq ?
display_pipe dq ?
source dq ?
source_position dq ?

state dd ?
first_write dd ?
first_write_length dd ?
second_write dd ?
second_write_length dd ?

systime SYSTEMTIME

tmp dd ?
buffer rb 1000h

include '..\..\variable.inc'

section '.text' code readable executable

DLLEntryPoint:

  virtual at rsp+8
    hinstDLL dq ?
    fdwReason dq ?
    lpvReserved dq ?
  end virtual

	cmp	edx,DLL_PROCESS_ATTACH
	jne	dll_ok
	cmp	[mutex],0
	jne	dll_ok
	invoke	CreateMutex,NULL,FALSE,NULL
	mov	[mutex],rax
	test	rax,rax
	jz	dll_failed
    dll_ok:
	mov	eax,TRUE
	ret
    dll_failed:
	mov	eax,FALSE
	ret

fasm_GetVersion:
	mov	eax,VERSION_MAJOR + VERSION_MINOR shl 16
	ret

fasm_AssembleFile:

	push	rcx rdx r8 r9
	invoke	WaitForSingleObject,[mutex],-1
	pop	r9 r8 rdx rcx

	mov	rax,[hDisplayPipe]
	mov	[display_pipe],rax

	push	r12 rbp rbx rsi rdi
	mov	r12,rsp

	jmp	setup_assembler

fasm_Assemble:

  virtual at rsp+8
    lpSource dq ?	; rcx
    lpMemory dq ?	; rdx
    cbMemorySize dq ?	; r8
    nPassesLimit dq ?	; r9
    hDisplayPipe dq ?
  end virtual

	push	rcx rdx r8 r9
	invoke	WaitForSingleObject,[mutex],-1
	pop	r9 r8 rdx rcx

	mov	rax,[hDisplayPipe]
	mov	[display_pipe],rax

	push	r12 rbp rbx rsi rdi
	mov	r12,rsp

	mov	[source],rcx
	mov	[source_position],0
	mov	ecx,null_byte

  setup_assembler:

	mov	rax,rdx
	add	rax,r8
	or	rax,rdx
	or	rax,rcx
	shr	rax,32
	jnz	invalid_parameter

	cmp	r9d,10000h
	ja	invalid_parameter
	or	r9d,r9d
	jz	invalid_parameter
	mov	[passes_limit],r9w

	mov	[input_file],ecx
	mov	[output_file],null_byte

	mov	eax,edx
	mov	ecx,r8d
	mov	[state],eax
	mov	[eax+FASM_STATE.condition],FASM_WORKING
	sub	ecx,sizeof.FASM_STATE
	jbe	out_of_memory
	add	eax,sizeof.FASM_STATE
	mov	[memory_start],eax
	mov	edx,ecx
	shr	edx,2
	sub	ecx,edx
	add	eax,ecx
	mov	[memory_end],eax
	mov	[additional_memory],eax
	add	eax,edx
	mov	[additional_memory_end],eax

	xor	eax,eax
	mov	[initial_definitions],eax

	mov	[first_write],eax
	mov	[second_write],eax

	mov	rax,rsp
	and	eax,not 0FFFh
	add	eax,1000h-10000h
	mov	[stack_limit],eax

	call	preprocessor
	call	parser
	call	assembler
	call	formatter

	mov	ebx,[state]
	mov	[ebx+FASM_STATE.condition],FASM_OK

  done:
	mov	eax,[ebx+FASM_STATE.condition]

  exit:
	push	rax
	invoke	ReleaseMutex,[mutex]
	pop	rax
	mov	rsp,r12
	pop	rdi rsi rbx rbp r12
	ret

  invalid_parameter:
	mov	eax,FASM_INVALID_PARAMETER
	jmp	exit

  general_error:
	mov	ebx,[state]
	mov	[ebx+FASM_STATE.condition],eax
	jmp	done

  assembler_error:
	mov	ebx,[state]
	mov	[ebx+FASM_STATE.error_code],eax
	mov	eax,[current_line]
	mov	[ebx+FASM_STATE.error_line],eax
	mov	eax,FASM_ERROR
	jmp	general_error

  get_environment_variable:
	mov	ecx,[memory_end]
	sub	ecx,edi
	invoke	GetEnvironmentVariable,esi,edi,ecx
	add	edi,eax
	ret

  open:
	cmp	byte [edx],0
	je	open_memory
	invoke	CreateFile,edx,GENERIC_READ,FILE_SHARE_READ,0,OPEN_EXISTING,0,0
	cmp	eax,-1
	je	file_error
	mov	ebx,eax
	clc
	retn
    file_error:
	stc
	retn
    open_memory:
	xor	ebx,ebx
	retn
  read:
	or	ebx,ebx
	jz	read_memory
	mov	ebp,ecx
	invoke	ReadFile,ebx,edx,ebp,tmp,0
	or	eax,eax
	jz	file_error
	cmp	ebp,[tmp]
	jne	file_error
	clc
	retn
    read_memory:
	push	rsi rdi
	mov	rsi,[source]
	add	rsi,[source_position]
	mov	edi,edx
	call	move_block
	pop	rdi rsi
	clc
	retn
    move_block:
	mov	al,cl
	shr	ecx,2
	rep	movsd
	mov	cl,al
	and	cl,11b
	rep	movsb
	retn
  lseek:
	or	ebx,ebx
	jz	seek_memory
	movzx	eax,al
	invoke	SetFilePointer,ebx,edx,0,eax
	cmp	eax,-1
	je	file_error
	retn
    seek_memory:
	push	rsi
	mov	rsi,[source]
	mov	ecx,edx
	or	al,al
	jz	seek_forward
	add	rsi,[source_position]
	cmp	al,2
	je	seek_source_end
    seek_forward:
	sub	ecx,1
	jc	seek_complete
    seek_in_source:
	lodsb
	or	al,al
	loopnz	seek_in_source
	jnz	seek_complete
	dec	rsi
    seek_complete:
	mov	rax,rsi
	sub	rax,[source]
	mov	[source_position],rax
	pop	rsi
	retn
    seek_source_end:
	lodsb
	or	al,al
	jnz	seek_source_end
	dec	rsi
	sub	rsi,rdx
	cmp	rsi,[source]
	jae	seek_complete
	mov	rsi,[source]
	jmp	seek_complete
  create:
	or	ebx,-1
	clc
	retn
  write:
	cmp	[first_write],0
	jne	make_second_write
	mov	[first_write],edx
	mov	[first_write_length],ecx
	clc
	retn
    make_second_write:
	cmp	[second_write],0
	jne	cannot_write
	mov	[second_write],edx
	mov	[second_write_length],ecx
	clc
	retn
    cannot_write:
	stc
	retn
  close:
	or	ebx,ebx
	jz	file_closed
	cmp	ebx,-1
	je	output_ready
	invoke	CloseHandle,ebx
    file_closed:
	retn
    output_ready:
	mov	ebx,[state]
	cmp	[second_write],0
	jne	two_part_output
	mov	eax,[first_write]
	mov	[ebx+FASM_STATE.output_data],eax
	mov	eax,[first_write_length]
	mov	[ebx+FASM_STATE.output_length],eax
	retn
    two_part_output:
	mov	eax,[second_write]
	mov	[ebx+FASM_STATE.output_data],eax
    shuffle_output:
	mov	ecx,[first_write_length]
	cmp	ecx,[second_write_length]
	ja	small_second_part
	sub	[second_write_length],ecx
	mov	esi,[first_write]
	mov	edi,[second_write]
	call	xchg_block
	mov	[second_write],edi
	jmp	shuffle_output
    xchg_block:
	shr	ecx,1
	jnc	xchgb_ok
	mov	al,[edi]
	xchg	al,[esi]
	stosb
	inc	esi
      xchgb_ok:
	shr	ecx,1
	jnc	xchgw_ok
	mov	ax,[edi]
	xchg	ax,[esi]
	stosw
	add	esi,2
      xchgw_ok:
	jz	xchgd_ok
      xchgd:
	mov	eax,[edi]
	xchg	eax,[esi]
	stosd
	add	esi,4
	loop	xchgd
      xchgd_ok:
	retn
    small_second_part:
	mov	edi,[second_write]
	mov	esi,edi
	add	edi,[first_write_length]
	cmp	edi,[first_write]
	jbe	move_second_part
	mov	edi,[first_write]
	add	edi,[first_write_length]
    move_second_part:
	push	rdi
	mov	ecx,[second_write_length]
	lea	eax,[edi+ecx]
	cmp	eax,[tagged_blocks]
	ja	out_of_memory
	call	move_block
	mov	edi,[second_write]
	mov	esi,[first_write]
	mov	ecx,[first_write_length]
	call	move_block
	pop	rsi
	mov	ecx,[second_write_length]
	call	move_block
	mov	ecx,edi
	sub	ecx,[ebx+FASM_STATE.output_data]
	mov	[ebx+FASM_STATE.output_length],ecx
	retn

  display_block:
	mov	rax,[display_pipe]
	test	rax,rax
	jz	display_ok
	invoke	WriteFile,eax,esi,ecx,tmp,NULL
    display_ok:
	retn

  make_timestamp:
	invoke	GetSystemTime,systime
	movzx	ecx,[systime.wYear]
	mov	eax,ecx
	sub	eax,1970
	mov	ebx,365
	mul	ebx
	mov	ebp,eax
	mov	eax,ecx
	sub	eax,1969
	shr	eax,2
	add	ebp,eax
	mov	eax,ecx
	sub	eax,1901
	mov	ebx,100
	div	ebx
	sub	ebp,eax
	mov	eax,ecx
	xor	edx,edx
	sub	eax,1601
	mov	ebx,400
	div	ebx
	add	ebp,eax
	movzx	ecx,[systime.wMonth]
	mov	eax,ecx
	dec	eax
	mov	ebx,30
	mul	ebx
	add	ebp,eax
	cmp	ecx,8
	jbe	months_correction
	mov	eax,ecx
	sub	eax,7
	shr	eax,1
	add	ebp,eax
	mov	ecx,8
      months_correction:
	mov	eax,ecx
	shr	eax,1
	add	ebp,eax
	cmp	ecx,2
	jbe	day_correction_ok
	sub	ebp,2
	movzx	ecx,word [systime.wYear]
	test	ecx,11b
	jnz	day_correction_ok
	xor	edx,edx
	mov	eax,ecx
	mov	ebx,100
	div	ebx
	or	edx,edx
	jnz	day_correction
	mov	eax,ecx
	mov	ebx,400
	div	ebx
	or	edx,edx
	jnz	day_correction_ok
      day_correction:
	inc	ebp
      day_correction_ok:
	movzx	eax,[systime.wDay]
	dec	eax
	add	eax,ebp
	mov	ebx,24
	mul	ebx
	movzx	ecx,[systime.wHour]
	add	eax,ecx
	mov	ebx,60
	mul	ebx
	movzx	ecx,[systime.wMinute]
	add	eax,ecx
	mov	ebx,60
	mul	ebx
	movzx	ecx,[systime.wSecond]
	add	eax,ecx
	retn

dump_symbols:
	retn

include '..\errors.inc'

include '..\..\linux\x64\modes.inc'

include '..\..\preproce.inc'
include '..\..\parser.inc'
include '..\..\exprpars.inc'
include '..\..\exprcalc.inc'
include '..\..\assemble.inc'
include '..\..\formats.inc'
include '..\..\x86_64.inc'
include '..\..\avx.inc'
include '..\..\tables.inc'

include '..\..\version.inc'

null_byte db 0

section '.idata' import data readable writeable

  library kernel32,'KERNEL32.DLL'

  include 'api\kernel32.inc'

section '.edata' export data readable

  export 'FASM.DLL',\
	 fasm_GetVersion,'fasm_GetVersion',\
	 fasm_Assemble,'fasm_Assemble',\
	 fasm_AssembleFile,'fasm_AssembleFile'

section '.reloc' fixups data readable discardable

section '.rsrc' resource data readable

  directory RT_VERSION,versions

  resource versions,\
	   1,LANG_NEUTRAL,version

  versioninfo version,VOS__WINDOWS32,VFT_APP,VFT2_UNKNOWN,LANG_ENGLISH+SUBLANG_DEFAULT,0,\
	      'FileDescription','flat assembler',\
	      'LegalCopyright',<'Copyright ',0A9h,' 2001-2018 Tomasz Grysztar.'>,\
	      'FileVersion',VERSION_STRING,\
	      'ProductVersion',VERSION_STRING,\
	      'OriginalFilename','FASMX64.DLL'
