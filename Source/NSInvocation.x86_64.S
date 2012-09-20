#if defined (NeXT_RUNTIME) && (defined (__x86_64__) || defined (__x86_64))

.macro GSAssemblyFunction
    .text
    .globl	$0
    .align	2, 0x90
$0:
.endmacro

/********************************************************************
 *
 * NSInvocation layout
 *
 ********************************************************************/

#define PARENT_SIZE 8

#define IMP_PTR PARENT_SIZE
#define ARG_PTR IMP_PTR + 8
#define OFF_PTR ARG_PTR + 8
#define RES_PTR OFF_PTR + 8

#define ST_SIZE RES_PTR + 8
#define RS_SIZE ST_SIZE + 4
#define RS_TYPE RS_SIZE + 4
#define ARG_CNT RS_TYPE + 4

/********************************************************************
 *
 * marg_list layout
 *
 ********************************************************************/

#define FP_AREA     0
#define REG_AREA    FP_AREA     + 16*8
#define LINK_AREA   REG_AREA    + 8*6
#define STACK_AREA  LINK_AREA   + 8*4

#define REG_SPACE   200

/********************************************************************
 *
 * Save registers to marg_list
 *
 ********************************************************************/

.macro SaveRegisters
  // Save xmm registers
  movdqa	%xmm0,   0+FP_AREA(%rsp)
  movdqa	%xmm1,  16+FP_AREA(%rsp)
  movdqa	%xmm2,  32+FP_AREA(%rsp)
  movdqa	%xmm3,  48+FP_AREA(%rsp)
  movdqa	%xmm4,  64+FP_AREA(%rsp)
  movdqa	%xmm5,  80+FP_AREA(%rsp)
  movdqa	%xmm6,  96+FP_AREA(%rsp)
  movdqa	%xmm7, 112+FP_AREA(%rsp)

  // Save parameter registers
  movq	%rdi,  0+REG_AREA(%rsp)
  movq	%rsi,  8+REG_AREA(%rsp)
  movq	%rdx, 16+REG_AREA(%rsp)
  movq	%rcx, 24+REG_AREA(%rsp)
  movq	 %r8, 32+REG_AREA(%rsp)
  movq	 %r9, 40+REG_AREA(%rsp)

  // Save side parameter registers
  movq	%r10,  0+LINK_AREA(%rsp)	// static chain
  movq	%rax,  8+LINK_AREA(%rsp)	// xmm count
  // Return address is already at 8+LINK_AREA(%rsp)
.endmacro

/********************************************************************
 *
 * extern SEL forwardSelector = "forward::"; 
 *
 ********************************************************************/

  .data
  .align 3
  .private_extern _forwardSelector
_forwardSelector: .quad 0

/********************************************************************
 *
 * void NSInvocationForwardHandler(id receiver, SEL _cmd);
 *
 ********************************************************************/

GSAssemblyFunction _NSInvocationForwardHandler
.cfi_startproc
  cmpq	%rsi, _forwardSelector(%rip)  // Die if forwarding "forward::"
  je _abort

  subq	$REG_SPACE, %rsp              // Push stack frame
.cfi_def_cfa_offset REG_SPACE+8

  SaveRegisters

  // Call [receiver forward:(SEL) :(marg_list)]
  // %rdi is already the receiver
  movq	%rsp, %rcx                    // marg_list
  movq	%rsi, %rdx                    // sel
  movq	_forwardSelector(%rip), %rsi	// forward::

  call	_objc_msgSend

  addq	$REG_SPACE, %rsp              // Pop stack frame
  ret
.cfi_endproc

/********************************************************************
 *
 * void NSInvocationForwardHandler_stret(void *resultPointer,
 *                                       id receiver, SEL _cmd);
 *
 ********************************************************************/

GSAssemblyFunction _NSInvocationForwardHandler_stret
.cfi_startproc
  cmpq	%rdx, _forwardSelector(%rip)  // Die if forwarding "forward::"
  je _abort

  subq	$REG_SPACE, %rsp              // Push stack frame
.cfi_def_cfa_offset REG_SPACE+8

  SaveRegisters

  // Call [receiver forward:(SEL) :(marg_list)]
  // %rdx is already the selector
  movq	%rsi, %rdi                    // receiver
  movq	_forwardSelector(%rip), %rsi	// forward::
  movq	%rsp, %rcx                    // marg_list

  call	_objc_msgSend                 // forward:: is NOT struct-return

  addq	$REG_SPACE, %rsp              // Pop stack frame
  ret
.cfi_endproc

/********************************************************************
 *
 * void NSInvocationInvoke_internal(NSInvocation *invocation);
 *
 ********************************************************************/

GSAssemblyFunction _NSInvocationInvoke_internal
.cfi_startproc
  pushq %rbp                  // we need base pointer to support exceptions
.cfi_def_cfa_offset 16
.cfi_offset %rbp, -16
  movq  %rsp, %rbp
.cfi_def_cfa_register %rbp

  pushq %rbx                  // backup %rbx
  subq  $8, %rsp              // padding
  movq  %rdi, %rbx            // save invocation pointer

  movl ST_SIZE(%rbx), %eax    // save stackSize for testing

testq %rax, %rax                // if (!stackSize) goto RestoreRegisters;
je 0f

  subq %rax, %rsp             // allocate stack_size on stack

  movq          %rsp, %rdi    // 1st arg: dst = %rsp
  movq ARG_PTR(%rbx), %rsi    // 2nd arg: src = marg_list + STACK_AREA
  addq   $STACK_AREA, %rsi
  movq          %rax, %rdx    // 3d arg: size = stackSize (multiple of 16)
  callq _memcpy

0:
  movq ARG_PTR(%rbx), %rax    // save marg_list pointer

  movq     0+REG_AREA(%rax), %rdi
  movq     8+REG_AREA(%rax), %rsi
  movq    16+REG_AREA(%rax), %rdx
  movq    24+REG_AREA(%rax), %rcx
  movq    32+REG_AREA(%rax), %r8
  movq    40+REG_AREA(%rax), %r9

  movdqa	  0+FP_AREA(%rax), %xmm0
  movdqa	 16+FP_AREA(%rax), %xmm1
  movdqa	 32+FP_AREA(%rax), %xmm2
  movdqa	 48+FP_AREA(%rax), %xmm3
  movdqa	 64+FP_AREA(%rax), %xmm4
  movdqa	 80+FP_AREA(%rax), %xmm5
  movdqa	 96+FP_AREA(%rax), %xmm6
  movdqa  112+FP_AREA(%rax), %xmm7

  callq *IMP_PTR(%rbx)
  
  movl ST_SIZE(%rbx), %ecx
  addq %rcx, %rsp             // remove stack args. from stack
  addq $8, %rsp
  popq %rbx                   // restore backed-up %rbx
  popq %rbp
  ret                         // %rax, %xmm0 are already set (if any)
.cfi_endproc

/********************************************************************
 *
 * void NSInvocationInvoke(NSInvocation *invocation);
 *
 ********************************************************************/

GSAssemblyFunction _NSInvocationInvoke
.cfi_startproc
  pushq RS_TYPE(%rdi)
  pushq RES_PTR(%rdi)
  subq $8, %rsp               // padding
.cfi_def_cfa_offset 24+8
  callq _NSInvocationInvoke_internal
  addq $8, %rsp
  popq %rcx                   // pointer to result buffer
  popq %rsi                   // return type
  movl %esi, %esi             // reset hi bytes

  // jmp *NSI_Store_VTable(, %esi, 4)
  leaq NSI_Store_VTable(%rip), %rdi
  movslq (%rdi, %rsi, 4), %r10
  addq %rdi, %r10
  jmp *%r10

NSI_Store_Xmm:
  movq %xmm0, (%rcx)
  ret
NSI_Store_Int:
  movq  %rax, (%rcx)
  ret
NSI_Store_Stack:
  // pointer to result buffer was passed to callee as first parameter in %rdi
  ret
NSI_Store_Int_Int:
  movq  %rax, 0x0(%rcx)
  movq  %rdx, 0x8(%rcx)
  ret
NSI_Store_Int_Xmm:
  movq  %rax, 0x0(%rcx)
  movq %xmm0, 0x8(%rcx)
  ret
NSI_Store_Xmm_Xmm:
  movq %xmm0, 0x0(%rcx)
  movq %xmm1, 0x8(%rcx)
  ret
NSI_Store_Xmm_Int:
  movq %xmm0, 0x0(%rcx)
  movq  %rax, 0x8(%rcx)
  ret
.cfi_endproc

.align 4
NSI_Store_VTable:
    .long 0x0 // padding, there is no zero return type
    .long NSI_Store_Xmm        - NSI_Store_VTable
    .long NSI_Store_Int        - NSI_Store_VTable
    .long NSI_Store_Stack      - NSI_Store_VTable
    .long NSI_Store_Int_Int    - NSI_Store_VTable
    .long NSI_Store_Int_Xmm    - NSI_Store_VTable
    .long NSI_Store_Xmm_Xmm    - NSI_Store_VTable
    .long NSI_Store_Xmm_Int    - NSI_Store_VTable

/********************************************************************
 *
 * void NSInvocationReturn(NSInvocation *invocation);
 *
 ********************************************************************/

GSAssemblyFunction _NSInvocationReturn
.cfi_startproc
.cfi_def_cfa_offset 8
  movq RES_PTR(%rdi), %rcx
  movl RS_TYPE(%rdi), %esi

  // jmp *NSI_Return_VTable(, %esi, 4)
  leaq NSI_Return_VTable(%rip), %rdi
  movslq (%rdi, %rsi, 4), %r10
  addq %rdi, %r10
  jmp *%r10

NSI_Return_Xmm:
  movq    (%rcx), %xmm0 
  ret
NSI_Return_Int:
  movq    (%rcx), %rax
  ret
NSI_Return_Stack:
  // nothing to do here
  ret
NSI_Return_Int_Int:
  movq 0x0(%rcx), %rax
  movq 0x8(%rcx), %rdx
  ret
NSI_Return_Int_Xmm:
  movq 0x0(%rcx), %rax
  movq 0x8(%rcx), %xmm0
  ret
NSI_Return_Xmm_Xmm:
  movq 0x0(%rcx), %xmm0
  movq 0x8(%rcx), %xmm1
  ret
NSI_Return_Xmm_Int:
  movq 0x0(%rcx), %xmm0
  movq 0x8(%rcx), %rax
  ret
.cfi_endproc

.align 4
NSI_Return_VTable:
    .long 0x0 // padding, there is no zero return type
    .long NSI_Return_Xmm        - NSI_Return_VTable
    .long NSI_Return_Int        - NSI_Return_VTable
    .long NSI_Return_Stack      - NSI_Return_VTable
    .long NSI_Return_Int_Int    - NSI_Return_VTable
    .long NSI_Return_Int_Xmm    - NSI_Return_VTable
    .long NSI_Return_Xmm_Xmm    - NSI_Return_VTable
    .long NSI_Return_Xmm_Int    - NSI_Return_VTable

#endif /* __x86_64__ */