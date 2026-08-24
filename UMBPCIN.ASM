;------------------------------------------------------------------------------
; HIMEM extension to UMBs for DOS 5 .. 7 ;
; Original (c) Peter Siering, published in c't 8/91
; Extended version by as (Sch‰pers), 15-AUG-91.
; Extended version by as (Stiller), c't 11/95
; for new chips from Intel, VIA, ALi, SiS as well as
; support for MTRRs starting from PPro and K7
; Extended version by Uwe Sieber from 04/1996
; (mail@uwe-sieber.de)
;
;                        *** Nasm Version ***
;
; /7 : Use external chipset even w/ AMD K7. (by Ninho), 01/09
;
; Thanks to Uwe Milde (PPro support) as well as Sergei Shtylyov
; and Serg Svetlov (K7 support)
;
; Special thanks to Nagatoshi Uehara for many valuable hints
;
;
; Requires Borland Tasm 4.x To Compile
; ------------------------------------
; Compile with:
;    tasm umbpci umbpci.obj [| more]*                  (German Version)   or
;    tasm umbpci /dEnglVersion umbpci2.obj [| more]*   (English Version)  or
;    tasm umbpci /dPTBR umbpci2.obj [| more]*          (Pt-BR Version)
;
; Link with:
;    tlink /t umbpci.obj, umbpci.sys /3
;
; * Note: | more is optional, to pause errors messages.
;------------------------------------------------------------------------------


;------------------------------------------------------------------------------
; Compilation Modifiers
;------------------------------------------------------------------------------
;EnglVersion     equ 1             ; Driver compiled in English
;DebugVersion    equ 1
;DebugVersion2   equ 1
;P2DebugVersion  equ 1
;K7DebugVersion  equ 1
;TestStack       equ 1
;PTBR            equ 1             ; Driver compilado em Portugues do Brasil


;==============================================================================
; Directives    
;==============================================================================
    .MODEL SMALL                   ; USE16 implicit...
    .CODE
;    .486p
    .586p                          ; Requires Borland TAsm 4.x
    JUMPS                          ; Automatic SHORT/NEAR conditional jumps (Ninho)


;==============================================================================
; Code Defines
;==============================================================================
VERSION_STRING       equ 'V3.91beta4'
DATE_STRING          equ '04/1996-05/2025'

; Pentium (586) Instructions
;cpuid                equ db 0Fh, 0A2h
;rdmsr                equ db 0Fh, 032h
;wrmsr                equ db 0Fh, 030h


;==============================================================================
; Structs
;==============================================================================

;------------------------------------------------------------------------------
; Parameter Block for INIT
;------------------------------------------------------------------------------
INIT_REQUEST STRUC
    IR_Length        db ?          ; Total size of parameter block
    IR_Unit          db ?          ; not used
    IR_Function      db ?          ; Function $00, i.e. Init
    IR_Status        dw ?          ; Initialization result code
    IR_Reserved      db 8 dup (?)  ; "reserved", not used
    IR_Units         db ?          ; Number of devices served by driver
    IR_EndAddress    dd ?          ; highest available/occupied memory address
    IR_ParamAddress  dd ?          ; Command line address (device=...)
    IR_DriveNumber   db ?          ; first unassigned drive letter
    IR_MessageFlag   db ?          ; Flag for error messages
INIT_REQUEST ENDS

UMB_ENTRY STRUC
    Start            dw ?          ; Start address (paragraphs)
    Len              dw ?          ; Length in paragraphs
UMB_ENTRY ENDS


;==============================================================================
; Start of Device Driver (192 bytes at total)
;==============================================================================

   org   0                        ; .SYS file Header stay on offset 0

;------------------------------------------------------------------------------
; Device Driver Header (Must be at offset 0)
;------------------------------------------------------------------------------
Next_Driver   dd -1                        ; Address of next driver (FFFF:FFFF)
Attributes    dw 0E000h                    ; Driver Attributes
Strategy      dw OFFSET Strategy_Routine   ; Offset of "Strategy" routine
Interrupt     dw OFFSET Interrupt_Routine  ; Offset of "Interrupt" routine
Driver_Name   db 'UMBPCIXX'                ; Name (or units)


;------------------------------------------------------------------------------
; List of UMBs Addresses Found and Available
;------------------------------------------------------------------------------
UMBs_List            dw 22 dup(0)        ; Maximum of 10 entries (UMBs)


;==============================================================================
; Inserted into the chain by Init_Function and called by DOS to allocate UMBs.
; -----------------------------------------------------------------------------
; Call  : DX = requested size (bytes), Flags on stack
; Return: DX = size of block found, BX = segment, AX = 1
;         or AX = 0 and BL = $B1 for "no block at all"
;         or AX = 0 and BL = $B0 for "block too small"
;==============================================================================
UMB_Request PROC NEAR
    push  ds
    push  si
    push  cx
    push  bx
    push  cs
    pop   ds                       ; DS = code segment

    mov   si,OFFSET UMBs_List
    xor   cx,cx                    ; For size comparison
    cld                            ; Ascending direction for move address blocks

; Search for an UMB free
UMB_Search:
    lodsw                          ; Gets one entry from UMB list
    or    ax,ax                    ; End of UMBs available list?
    jz    UMB_End                  ; -> Yes, not has more UMBs
    mov   bx,ax                    ; hold start segment
    lodsw
    cmp   bx,-1                    ; Already occupied?
    je    UMB_Search               ; -> Yes, let's check the next entry
    cmp   ax,cx                    ; largest block so far?
    jb    Check_Size
    mov   cx,ax                    ; Yes, hold size

Check_Size:
    cmp   ax,dx                    ; Size is enough?
    jb    UMB_Search               ; -> No, then go to the next block

Free_UMB_Found:
    mov   WORD PTR [si - 4],-1     ; Marks the block as allocated
    mov   dx,ax                    ; Size in DX, segment in BX
    pop   ax                       ; Old BX from stack
    mov   ax,1                     ; Signals success
    jmp   SHORT UMB_Done

UMB_End:
    xor   ax,ax
    pop   bx                       ; Original BX (BH)
    mov   bl,0B0h                  ; Assumption: the UMB only too small
    mov   dx,cx                    ; Block size to return
    or    dx,dx                    ; Anything found?
    jnz   UMB_Done                 ; -> Yes, only too small
    inc   bl                       ; Nothing found at all: BL = $B1

UMB_Done:
    pop   cx
    pop   si
    pop   ds
    popf
    retf

UMB_Request ENDP


;------------------------------------------------------------------------------
; Original HIMEM.SYS Chain (Changed on loading to support the UMBPCI)
;------------------------------------------------------------------------------
XMS_Original_Jmp     dd ?          ; HIMEM original address


New_Chain:
    jmp   SHORT New_Ctrl
    nop                            ; At this location the next
    nop                            ; handler would insert its jump
    nop

New_Ctrl:
    pushf
    cmp   ah,10h                   ; UMB request?
    je    UMB_Request              ; Flags on stack!
    popf
    jmp   [XMS_Original_Jmp]       ; Otherwise goes to original XMS handler

ifdef TestStack
  db  ('FSTACK7890ABCDEF')
  db  ('ESTACK7890ABCDEF')
  db  ('DSTACK7890ABCDEF')
  db  ('CSTACK7890ABCDEF')
  db  ('BSTACK7890ABCDEF')
  db  ('ASTACK7890ABCDEF')
  db  ('9STACK7890ABCDEF')
  db  ('8STACK7890ABCDEF')
  db  ('7STACK7890ABCDEF')
  db  ('6STACK7890ABCDEF')
  db  ('5STACK7890ABCDEF')
  db  ('4STACK7890ABCDEF')
  db  ('3STACK7890ABCDEF')
  db  ('2STACK7890ABCDEF')
  db  ('1STACK7890ABCDEF')
  Local_Stack  db  0
endif

END_RESIDENT LABEL BYTE    ; *** The Resident Part (192 bytes) Ends Here ***


;==============================================================================
;                  *** BEGINNING OF NON-RESIDENT PART ***
;==============================================================================

;=========================================
; Constants
;=========================================
UNSUPPORTED_UNTESTED          equ 1
UNSUPPORTED_NO_DATASHEET      equ 2
UNSUPPORTED_NO_SHADOW_RAM     equ 3
UNSUPPORTED_CONFIG_MECHANISM  equ 4
UNSUPPORTED_WRONG_DOC         equ 5
UNSUPPORTED_NO_HOST_BRIDGE    equ 6

TYP_06                        equ 0606h
TYP_18                        equ 1818h
MSR_CONTROL                   equ 02FFh

CARRIAGE_RETURN               equ 0Dh
LINE_FEED                     equ 0Ah
ESC_KEY                       equ 1Bh


;=========================================
; Buffers for Non Resident Code
;=========================================
Hex_Digits     db '0123456789ABCDEF' ; Ausgabe einer Hex-Zahl mit vier Stellen (AX)
CR_LF_$        db 13,10,'$'          ; CRLF also marks the end of the resident part!

SkipUkcMsg     dw 0
Skip_K7_Test   dw 0                  ;  '/7' command line param (Ninho)

Liste          dw 0
Bus_Dev_0      dw 0
Bus_Dev_1      dw 0

Found_Chip     dw 0
PPro_Found     dw 0
K7_Found       dw 0
Untested       dw 0

Param_Error    dw 0

MTRR_Def_Type  dd 0
Dummy          dd 0
MTRR_Number    dd 0
MTRR_Val_Lo    dd 0
MTRR_Val_Hi    dd 0

Block_Size     dw 400h               ; default 16K blocks
BlockSizeShR   db 10                 ; shr by 10 bits for 16K, 8 for 4K blocks

;Fill_1         db '--------------'
;Fill_2         db '--------------'

Comma_$        db ', ','$'
Dash_Char_$    db '-$'

;AXstr          db 'AX:$'
;BXstr          db 'BX:$'
;CXstr          db 'CX:$'
;DXstr          db 'DX:$'

ifdef K7DebugVersion
  readstr      db 'read : $'
  writestr     db 'write: $'
endif

Param_Addr     dd ?                  ; Buffer for INIT parameter block

initOnly       db 0


;==============================================================================
; Strategy Routine, saves ES:BX (Parameter Block Address)
;==============================================================================
Strategy_Routine:
    mov   WORD PTR [Param_Addr],bx
    mov   WORD PTR [Param_Addr + 2],es
    retf


;== Apr/08/2004 Nagatoshi Uehara ==;
             dw  95 dup (0)
Local_Stack  dw  0                 ; Stack Size = 192 byte
Saved_Stack  dw  0, 0
;==================================;


;==============================================================================
; Interrupt Routine, defines only the INIT function
;==============================================================================
Interrupt_Routine:

ifdef DebugVersion
    int   03h                      ; DEBUG TRAP (Ninho)
endif

;================================================
;    **** Apr/08/2004 Nagatoshi Uehara ****
; Saves Original SS:SP and Set a Local SS:SP
; -----------------------------------------------
    mov   cs:WORD PTR [Saved_Stack],sp     ; Lo
    mov   cs:WORD PTR [Saved_Stack][2],ss  ; Hi
    push  cs
    pop   ss
    mov   sp,OFFSET Local_Stack
;================================================

    push  ax                       ; no more than these three registers
    push  bx                       ; are currently needed
    push  es
    pushf
    les   bx,[Param_Addr]           ; ES:BX = parameter block
    mov   es:[bx + IR_Status],8103h ; pessimistic approach
    mov   al,es:[bx + IR_Function]  ; function number
    or    al,al                     ; Init?
    jnz   IR_Other_Cmd              ; code "command unknown" set
    call  Init_Function             ; INIT - delivers status in AX
    les   bx,[Param_Addr]
    mov   es:[bx + IR_Status],ax

IR_Other_Cmd:
    popf
    pop   es
    pop   bx
    pop   ax

;================================================
;    **** Apr/08/2004 Nagatoshi Uehara ****
; Restores Original SS:SP
; -----------------------------------------------
    mov   sp,cs:WORD PTR [Saved_Stack]     ; Lo
    mov   ss,cs:WORD PTR [Saved_Stack][2]  ; Hi
;================================================

    retf


;==============================================================================
; Waits a Key Pressing
;==============================================================================
Wait_Key:
    pusha                                  ; Saves all registers
;    mov   dx,OFFSET PressKey$
;    call  Print_String
    mov   ax,0
    int   16h
    popa                                   ; Restores all registers
    ret


Print_Dash_Char:
    pusha
    mov   dx,OFFSET Dash_Char_$
    jmp   Do_Print_And_Restore_Registers


Print_Comma:
    pusha
    mov   dx,OFFSET Comma_$
    jmp   Do_Print_And_Restore_Registers


Print_CRLF:
    pusha
    mov   dx,OFFSET CR_LF_$
;    jmp   Do_Print_And_Restore_Registers


Do_Print_And_Restore_Registers:
    mov   ah,09h
    int   21h
    popa                                   ; Restores all registers
    ret


;==============================================================================
; Prints a String on Screen Skipping to the Next Line
;==============================================================================
Print_String:
    call  Do_Print_Str
    mov   dx,OFFSET CR_LF_$                ; Finish printing

Do_Print_Str:
    mov   ah,09h
    int   21h
    ret


;==============================================================================
; Prints a 16-bit Hexadecimal Value
;==============================================================================
Print_Hex_Value:
    pusha                          ; Preserves all registers
    mov   cx,0Ch                   ; beim ersten Mal 12 Bit schieben, dann immer 4 weniger

Print_Hex_Digit:
    push  ax                       ; Saves the 16-bit value to show
    shr   ax,cl                    ; Gets the nibble to show
    and   ax,000Fh                 ; Clears unwished nibbles
    mov   bx,ax
    mov   dl,[Hex_Digits + bx]     ; Gets the hexadecimal character
    mov   ah,02h                   ; "Display Output"
    int   21h
    pop   ax                       ; Restores the original 16-bit value showing
    sub   cl,4                     ; Get next nibble
    jnb   Print_Hex_Digit          ; Show the next digit
    popa                           ; Restores all registers
    ret


; Ausgabe einer Hex-Zahl mit acht Stellen (EAX)
ifdef K7DebugVersion
PrHexDW:
    pusha                          ; Preserves all registers values
    mov   cx,1Ch                   ; beim ersten Mal 28 Bit schieben, dann immer 4 weniger

PrDigDW:
    push  eax
    shr   eax,cl
    and   eax,000Fh
    mov   ebx,eax
    mov   dl,[Hex_Digits + bx]     ; ebx < FFFF, so bx is ok and avoids TASM to see a 32bit record
    mov   ah,02h                   ; "Display Output"
    int   21h
    pop   eax
    sub   cl,4
    jnb   PrDigDW
    popa                           ; Restores all registers values
    ret
endif


;------------------------------------------------------------------------------
; Display an Error Message Using DOS Function $09 and Abort
; Called with DS:DX = message text
;------------------------------------------------------------------------------
Error_Out:
    call  Print_String                        ; Show text

Key_Out:
    cmp   word ptr [SkipUkcMsg],1             ; /S
    je    Release

    mov   dx,OFFSET PressKey$                 ; Press any key... message
    call  Print_String
    xor   ax,ax
    int   16h                                 ; Wait a key press

Release:
    les   bx,[Param_Addr]
    mov   word ptr es:[bx + IR_EndAddress],0  ; 0 bytes required
    mov   ax,8100h                            ; Error (unspecified)
    jmp   Init_End
;------------------------------------------------------------------------


;------------------------------------------------------------------------
Pre_Init_Function:
;    mov   ax,0B101h                ; Check PCI BIOS presence
;    int   1Ah
;    jc    @PIF_No_PCI_BIOS         ; PCI Bios not present (PIF stands for Pre_Initi_Function)
;    cmp   ah,0
;    jne   @PIF_No_PCI_BIOS         ; PCI Bios not present (PIF stands for Pre_Initi_Function)
;    cmp   dx,4350h
;    je    @PIF_PCI_BIOS_Found      ; PCI BIOS is present, so continue (PIF stands for Pre_Initi_Function)
    call  Check_PCI_BIOS           ; Check if a PCI BIOS is present
    jnc   @PIF_PCI_BIOS_Found      ; Yes (Carry flag = 0)

;@PIF_No_PCI_BIOS:
    mov   dx,OFFSET NoPCI$         ; No PCI message
    stc                            ; Fail flag (Carry = 1)
    ret                            ; No PCI BIOS -> abort

@PIF_PCI_BIOS_Found:
;Test special Chipsets

@No_VIA_CX700:
;       jmp Test_K7


Test_K7:
    ;----------------------------------------------------------
    ; First let's look for an Intel chipset; if found, it
    ; cannot be an AMD K7, even if one is present -> VMware.
    ;----------------------------------------------------------
    mov   ax,0B109h                ; Read_Config_Word
;    mov   bx,0                     ; bus=0, dev=0, fuc=0
;    mov   di,0                     ; reg=0 -> vendor ID
    xor   bx,bx                    ; bus=0, dev=0, fuc=0
    xor   di,di                    ; reg=0 -> vendor ID
    int   1Ah
    cmp   cx,8086h                 ; Intel vendor ID
    je    No_K7_CPU

    ;kein Intel Chipsatz -> nach AMD K7 CPU suchen,
    ;dann haben wir eine BlockSize von 4, sonst 16KB
    cmp   Skip_K7_Test,1           ; param /7
    je    No_K7_CPU
    call  Test_K7_CPU
    jnc   No_K7_CPU
    mov   K7_Found,1
    mov   word ptr [Block_Size],100h
    mov   byte ptr [BlockSizeShR],8

No_K7_CPU:


;------------------------------------------------------------------------------
; HIMEM is Installed?
;------------------------------------------------------------------------------
Check_HIMEM:
    mov   ax,4300h                  ; Check whether HIMEM is installed
    int   2Fh
    cmp   al,80h                    ; HIMEM present?
    je    Get_XMS_Call              ; -> Yes

    ; No HIMEM found, so only enable memory
    mov   byte ptr [initOnly],1
    clc                            ; OK (Carry = 0)
    ret                            ; Continue without HIMEM


;------------------------------------------------------------------------------
; Determine Chain
;------------------------------------------------------------------------------
Get_XMS_Call:
    mov   ax,4310h                 ; HIMEM: Entry address
    int   2Fh
    mov   word ptr [XMS_Original_Jmp],bx
    mov   word ptr [XMS_Original_Jmp + 2],es

    ; UMB server already exists?
    mov   ah,16
    mov   dx,0FFFh                 ; Request a 64-KByte block
    call  [XMS_Original_Jmp]
    cmp   bl,80h                   ; Not installed?
    je    Pre_Init_OK_Exit         ; -> OK
    mov   dx,OFFSET UMBPresent$    ;
    stc                            ; Fail flag (Carry = 1)
    ret

Pre_Init_OK_Exit:
    clc                            ; All OK (Carry = 0)
    ret
;-----------------------------------------------


;------------------------------------------------------------------------------
; Initialization - called with ES:DI = parameter block and ES, BX, AX/flags
; on the stack, so there is no need to preserve these registers.
;------------------------------------------------------------------------------
Init_Function:
    push  cx
    push  dx
    push  si
    push  di
    push  ds

    push  cs
    pop   ds                       ; DS = code segment

    mov   word ptr es:[bx + IR_EndAddress],OFFSET CR_LF_$
    mov   word ptr es:[bx + IR_EndAddress + 2],cs  ; Store end address
    mov   dx,OFFSET Copyright$                     ; "Gruess Gott"
    call  Print_String
    mov   dx,OFFSET Changed$                       ; "Gress Gott2"
    call  Print_String

;----------------------------------------------
; First check command line, look for "/7" only
; BEFORE doing PreInit   (Ninho)
;----------------------------------------------
    les   di,[Param_Addr]               ; Parameterblock
    les   di,es:[di + IR_ParamAddress]  ; ES:DI auf Kommandozeile

Elem_7:
    mov   al,es:[di]
    inc   di
    cmp   al,CARRIAGE_RETURN            ; Carriage Return ?
    je    End_7                         ; -> yes, End
    cmp   al,LINE_FEED                  ; Line Feed ?
    je    End_7                         ; -> dito
    cmp   al,'/'                        ; Slash ?
    jne   Elem_7
    mov   al,es:[di]                    ; Gets the next char

    ;------ /7 - suppress K7 test ------
    cmp   al,'7'
    jne   Elem_7
    mov   Skip_K7_Test,1                ; Must be set before PREINIT
    mov   K7_Found,0
    mov   dx,OFFSET SkipK7Msg$
    call  Do_Print_Str
    ;------------------------------------

End_7:
    call  Pre_Init_Function
    jc    Error_Out                     ; problem in Pre_Init_Function, DX points to msg

;------------------------------------------
; Parse the Command Line
;------------------------------------------
Get_Cmd_Line:
Cmd_Line:
    les   di,[Param_Addr]               ; Parameter block
    les   di,es:[di + IR_ParamAddress]  ; ES:DI points to the command line
    call  Set_List                      ; Parse the command line and set the list
    jnc   Test_Areas                    ; -> OK

    cmp   Param_Error,1
    jne   No_Param_Error
    mov   dx,OFFSET BadCmd$
    jmp   Error_Out                    ; Output the command line

No_Param_Error:
    call  Scan_Areas                   ; Search for Areas automatically
    jnc   Test_Areas                   ; -> OK
    mov   dx,OFFSET NoFreeBlock$       ; Message
    jmp   Error_Out


s    dw 0
;d1   db "Block Start$"
;d2   db "Block Ende$"
;d3   db "Back from Test$"


; Input: Start in AX, Return: Length in CX
Test_Block:
    push  ax
    push  ds
    push  es
;    mov   si,0
    xor   si,si

@Next_Block:
    ;pusha
    ;call  Print_Hex_Value
    ;call  Print_Dash_Char
    ;call  Print_CRLF
    ;popa

    mov   s,ax                     ; Save start
    dec   ax                       ; Decrement once time for the first inc...
    mov   es,ax

@Next_Word:
    mov   ax,es
    inc   ax
    mov   es,ax
    mov   dx,WORD PTR es:[si]
    and   dx,WORD PTR es:[si + 2]
    and   dx,WORD PTR es:[si + 4]
    and   dx,WORD PTR es:[si + 6]
    cmp   dx,0FFFFh
    je    @Next_Word

@Diff_Found:
    ;Difference found -> end of block
    mov   ax,es                    ; Current address
    push  bx
    mov   bx,[Block_Size]
    xor   dx,dx                    ; clears DX before division
    div   bx
    mul   bx                       ; Round down to the nearest 4K or 16K boundary
    pop   bx

;    mov   cx,0
    xor   cx,cx
    cmp   ax,s
    je    @End_Test_Block          ; Exit with CX = 0
    mov   cx,ax
    sub   cx,s                     ; Length = address - start

@End_Test_Block:
    pop   es
    pop   ds
    pop   ax
    ret


Test_Areas:
    ;AMD K7/K8 work without a chipset :-)
    cmp   word ptr [K7_Found],1
    je    Test_All_UMB_Blocks


No_K7_CPU2:

ifdef DebugVersion
    int   03h                      ;;; (Ninho) DEBUG 2
endif
    
    call  Init_Chipset             ; Get and show chipset found
    jc    Key_Out                  ; Message already displayed

Test_All_UMB_Blocks:
    clc
    mov   si,OFFSET UMBs_List
    cld

Next_UMB:

ifdef DebugVersion
    int   03h                      ;;; (Ninho) DEBUG 3
endif
    
    lodsw                          ; Start address
    or    ax,ax                    ; End of list reached?
    jz    Areas_Tested              ; Yes. Then done
    mov   es,ax                    ; Start address in ES
    lodsw                          ; Size (paragraphs)
    mov   cl,BlockSizeShR          ; Convert to 16K/4K blocks
    shr   ax,cl                    ; => Number of 16K/4K blocks

ifdef K7DebugVersion
    pusha
    call  Print_Hex_value
    call  Print_CRLF
    popa
endif

Test_Blocks:
    cmp   K7_Found,0
    je    Skip_Set_K7
    xor   di,di
    call  Set_K7                   ; Segment ES, enable 16K
    call  Init_RAM_4KB
    jmp   Test_Current_Block


Skip_Set_K7:
    xor   di,di
    call  Set_Chipset              ; Segment ES, enable 16K
    jc    Chipset_Error

Test_Current_Block:
    xor   di,di
    mov   bx,es:[di]               ; Read current contents
    mov   dx,bx
    xor   dx,0FFFFh                ; Invert
    mov   es:[di],dx               ; And write
    mov   cx,8000h                 ; Wait a moment in case the
    loop  $                        ; operation should fail
    cmp   es:[di],dx               ; Do we have a constant value?
    mov   es:[di],bx               ; Restore old contents
    jne   No_RAM                   ; -> No RAM at this location!
    cmp   PPro_Found,0             ; PPro?
    je    Skip_PPro
    pusha
    call  Set_PPro                 ; Segment ES, enable 16K
    popa

Skip_PPro:
    dec   ax
    jz    Next_UMB                 ; -> Next UMB area
    mov   di,es
    add   di,Block_Size            ; Otherwise, advance ES by 16K
    mov   es,di
    jmp   Test_Blocks              ; And back to test the next 4K or 16K block


;------------------------------------------------------------------------------
; Upper Memory Area RAM not Found or Read Only
;------------------------------------------------------------------------------
No_RAM:
    push  es                       ; Segment of the block
    mov   dx,OFFSET RAMFail1$
    call  Do_Print_Str             ; Output without CRLF
    pop   ax
    call  Print_Hex_Value          ; Show segment address
;    call  Print_Space              ; Adds a space
    mov   dx,OFFSET RAMFail2$
    jmp   Error_Out


Chipset_Error:
    mov   dx,OFFSET SetErr$
    jmp   Error_Out


;------------------------------------------------------------------------------
; After a successful RAM test, the execution continues here by inserting our
; own "hook" into the HIMEM.SYS jump chain.
;------------------------------------------------------------------------------
Areas_Tested:
    cmp   initOnly,1
    jne   InstHimemExt
    mov   dx,OFFSET Initialized$   ; Initialized only
    call  Print_String

;------------------------------------------------------------
;------------------------------------------------------------
;------------------------------------------------------------
;* Start patch by Jack Ellis - save UMBList to the first UMB for QXHIMEM
    cli                            ; Disable CPU interrupts.
    cld                            ; Ensure forward "string" commands.
    xor   di,di                    ; Point to first upper-memory block.
    mov   si,OFFSET UMBs_List
    mov   es,[si]
    mov   ax,"U$"                  ; Set starting  $UMBTbl!  signature.
    stosw
    mov   ax,"BM"
    stosw
    mov   ax,"bT"
    stosw
    mov   ax,"!l"
    stosw
    mov   cx,22                    ; Move UMBPCI table to upper-memory.
    rep   movsw
    mov   ax,0AB5Fh                ; Set ending signature bytes.
    stosw
    sti                            ; Acho que faltou! (CJB)
;* End patch by Jack Ellis
;------------------------------------------------------------
;------------------------------------------------------------
;------------------------------------------------------------

    jmp   Release                  ;##### END


InstHimemExt:
    les   di,[XMS_Original_Jmp]

Scan_Hooks:
    mov   al,BYTE PTR es:[di]
    cmp   al,0EBh                    ; JMP SHORT?
    je    Hook_Found                 ; OK - momentanes Kettenende
    les   di,DWORD PTR es:[di + 1]   ; sonst nÑchstes Element
    cmp   al,0EAh                    ; war das Åberhaupt ein JMP FAR?
    je    Scan_Hooks
    mov   dx,OFFSET HookErr$         ; Hook-Kette beschÑdigt
    jmp   Error_Out


Hook_Found:
    cli                                          ; No interruptions here, please!
    dec   BYTE PTR es:[di]                       ; JMP SHORT -> JMP FAR
    mov   WORD PTR es:[di + 1],OFFSET New_Chain  ; Insert our own routine
    mov   WORD PTR es:[di + 3],cs                ; Set segment
    add   di,5                                   ; Actual original address (after the NOPs)
    mov   WORD PTR [XMS_Original_Jmp],di
    mov   WORD PTR [XMS_Original_Jmp + 2],es
    sti

Show_Installation:
    mov   dx,OFFSET Installed$       ; Message
    call  Print_String
    mov   ax,0100h                   ; Initialization completed successfully

Init_End:
    pop   ds
    pop   di
    pop   si
    pop   dx
    pop   cx
    ret
;----------------------------- INIT FUNCTION END ------------------------------


;------------------------------------------------------------------------------
; Search for Free Areas, Return with UMBs_List Filled and Carry Set or Cleared
;------------------------------------------------------------------------------
Scan_Areas:
    xor   bx,bx                            ; Initialize UMB_List index
    mov   ax,0C000h                        ; First block

@@SA_Next_Block:
    call  Test_Block
    cmp   cx,0
    je    @@Skip_Range_Msg
    pusha
    mov   bx,ax
    add   bx,cx
    sub   bx,1
    push  bx
    push  ax
    mov   dx,OFFSET Using_String$          ; Message
    call  Do_Print_Str
    pop   ax
    call  Print_Hex_Value
    call  Print_Dash_Char
    pop   bx
    mov   ax,bx
    call  Print_Hex_Value
    call  Print_CRLF
    popa

@@Skip_Range_Msg:
    cmp   cx,0                             ; Length zero?
    jne   @@Add2List
    add   ax,Block_Size
    cmp   ax,0F000h
    jb    @@SA_Next_Block
    jmp   List_Set_2                       ; That's it, exit


@@Add2List:
;    call  Here_MSG
    mov   WORD PTR[UMBs_List + bx],ax      ; Entry start address
    mov   WORD PTR[UMBs_List + bx + 2],cx  ; Block length

    add   ax,cx                            ; Continue searching beyond the
                                           ; end of the block
;    pusha
;    call  Print_Hex_Value
;    call  Print_Comma
;    call  Print_CRLF
;    popa

    add   bx,4
    cmp   bx,40                            ; More than 10 entries?
;    cmp   bx,16                           ; More than 4 entries?
    jnb   List_Set_2
    cmp   ax,0F000h
    jb    @@SA_Next_Block
    jmp   List_Set_2


;List_Error_2:
;    stc
;    ret


List_Set_2:
    sub   bx,1                             ; Set Carry if BX = 0
    ret
;------------------------------ SCAN_AREAS END --------------------------------


;allhier$          db 'Ick bin allhier!$'

;Here_MSG:
;    pusha
;    mov   dx,OFFSET allhier$
;    call  Print_String
;    popa
;    ret


;include "MESSAGES.INC"
ifdef EnglVersion
  Copyright$       db 'UMBPCI c''t 11/95 - Siering/SchÑpers/Stiller$'
  Changed$         db ''
                   db VERSION_STRING, ' - Support for new Chipsets and CPUs - Uwe Sieber ', DATE_STRING,'$'
  NoXMS$           db 'No XMS-driver found!$'
  UMBPresent$      db 'UMB-server already installed!',13,10
                   db 'Installation stopped!',13,10,'$'
  NoFreeBlock$     db 'No unused memory block found',13,10,'$'
  BadCmd$          db ''
                   db 'Problem with range parameters in CONFIG.SYS!',13,10
                   db 'Format: DEVICE=UMBPCI.SYS /I=aaaa-bbbb /I=cccc-dddd',13,10
                   db 'Supported range is C800-EFFF',13,10
                   db 'Only whole 16K-Blocks are allowed e.g. /I=c800-cbff or /I=c800-efff',13,10,'$'
                   db 'On AMD K7/K8 4K-Blocks are allowed e.g. /I=c900-ccff or /I=c800-efff',13,10,'$'
                   db 'Loaded without any parameters UMBPCI searches and uses all free ranges$'
  RAMFail1$        db 13,10,'No RAM found at segment (hex) $'
  RAMFail2$        db ' - Installation Stopped -$'
  HookErr$         db 'Hook-Chain of HIMEM.SYS unknown!$'
  Installed$       db 'Program installed.$'
  NoPCI$           db 'UMBPCI creates UMBs on PCI chipsets (that''s where the name comes from).',13,10
                   db 'This computer has no PCI chipset!$'
  SetErr$          db 'Problem programming PCI-chipset!$'
  SkipK7Msg$       db 'AMD K7 detection will be skipped!',13,10,'$' ; (Ninho)
  PressKey$        db 'press any key...$'
  Unsupp2$         db 'This chipset isn''t supported because its vendor doesn''t offer the needed information about it',13,10,'$'
  Unsupp3$         db 'This chipset isn''t supported because it has no Shadow RAM',13,10,'$'
  Unsupp4$         db 'The configuration mechanism of this chipset isn''t supported.',13,10,'$'
  Unsupp5$         db 'This chipset isn''t supported because it doesn''t work as documented',13,10,'$'
  Unsupp6$         db 'This chipset has no hostbridge as device 0 at bus 0',13,10,'$'
  NoIntel$         db 'The chipset is unknown!',13,10
;                   db 'Please check out at http://www.uwe-sieber.de/umbpci_e.html if this',13,10
;                   db 'the latest version of UMBPCI. If it is, please email these data',13,10
;                   db 'and the name of your chipset to mail@uwe-sieber.de:$'
  Found_String$    db ' found.$'
  Using_String$    db 'Using $'
  iErr$            db 'Internal Error :-($'
  Initialized$     db 'No loaded HIMEM found, Upper Memory activated only$'
  Untested$        db ''
                   db 'This chipset is untested! Mail me the name of the chipset and if it works',13,10
                   db 'so I can either remove this break or list it as not working:',13,10
                   db 'mail@uwe-sieber.de',13,10
                   db 'Try a bit around with pure DOS (a good test is to load high DOSKEY) and backup ',13,10
                   db 'your harddisk before you boot into Win9x GUI - I doensn''t warrenty anything!',13,10
                   db 'Press ESC to skip UMBPCI or another key to proceed loading!',13,10,'$'
  Canceled$        db 'Installation canceled!',13,10,'$'
  SpaceE$          db '                '
  InternalThanks   db '   Thanks to Uwe Milde (PPro Support), Sergei Shtylyov and Serg Svetlov (K7 support)   '
  InternalThanks2  db '   Thanks to Nagatoshi Uehara for lots of very useful hints   '
elseifdef PTBR
  Copyright$       db 'UMBPCI c''t 11/95 - Siering/Sch‰pers/Stiller$'
  Changed$         db ''
                   db VERSION_STRING, ' - Suporte para Novos Chipsets e CPUs - Uwe Sieber ', DATE_STRING,13,10,'$'
  NoXMS$           db 'Nenhum driver XMS encontrado!$'
  UMBPresent$      db 'InstalaáÑo Interrompida!',13,10
                   db 'Servidor UMB j† instalado.',13,10,'$'
  NoFreeBlock$     db 'NÑo foi encontrado nenhum bloco de mem¢ria sem uso.',13,10,'$'
  BadCmd$          db ''
                   db 'Erro com os parÉmetros de faixa no arquivo CONFIG.SYS!',13,10
                   db 'Sintaxe: DEVICE=UMBPCI.SYS /I=aaaa-bbbb /I=cccc-dddd',13,10
                   db 'A faixa suportada Ç C800-EFFF.',13,10
                   db 'Somente blocos inteiros de 16K sÑo permitidos, por exemplo: /I=C800-CBFF ou /I=C800-EFFF',13,10,'$'
                   db 'Blocos de 4K sÑo permitidos nos AMD K7/K8, por exemplo: /I=C900-CCFF ou /I=C800-EFFF',13,10,'$'
                   db 'Se o UMBPCI Ç chamado sem nenhum parÉmetro, ele busca e usa toda a faixa livre da mem¢ria superior.$'
  RAMFail1$        db 'Nenhuma RAM dispon°vel no segmento (hex) $'
  RAMFail2$        db '  ** InstalaáÑo Interrompida **$'
  HookErr$         db 'Hook-Chain of HIMEM.SYS unknown!$'
  Installed$       db 'UMBPCI instalado.',13,10,'$'
  NoPCI$           db 'O UMBPCI cria UMBs em chipsets PCI (que Ç de onde origina o nome ;-).',13,10
                   db 'Este computador nÑo tem um chipset PCI!$'
  SetErr$          db 'Um erro ocorreu ao tentar programar o chipset PCI!$'
  SkipK7Msg$       db 'A detecáÑo de AMD K7 ser† ignorada!',13,10,'$' ; (Ninho)
  PressKey$        db 0Dh, 0Ah, 'Pressione uma tecla para continuar...', 0Dh, 0Ah, '$'
  Unsupp2$         db 'This chipset isn''t supported because its vendor doesn''t offer the needed information about it',13,10,'$'
  Unsupp3$         db 'This chipset isn''t supported because it has no Shadow RAM',13,10,'$'
  Unsupp4$         db 'The configuration mechanism of this chipset isn''t supported.',13,10,'$'
  Unsupp5$         db 'This chipset isn''t supported because it doesn''t work as documented',13,10,'$'
  Unsupp6$         db 'This chipset has no hostbridge as device 0 at bus 0',13,10,'$'
  NoIntel$         db 'Chipset Desconhecido!',13,10
;                   db 'Por favor verifique em http://www.uwe-sieber.de/umbpci_e.html se esta Ç',13,10
;                   db 'a mais £ltima versÑo do UMBPCI. Se ele est†, por favor envie estes dados',13,10
;                   db 'e o nome do seu chipset para mail@uwe-sieber.de:$'
  Found_String$    db ' encontrado.$'
  Using_String$    db 'Segmentos dispon°veis: $'
  iErr$            db 'Erro Interno :-($'
  Initialized$     db 'HIMEM.SYS nÑo carregado. Somente Mem¢ria Superior ativada.$'
  Untested$        db ''
                   db 'Este Chipset NÑo Foi Testado! Mail me the name of the chipset and if it works',13,10
                   db 'so I can either remove this break or list it as not working:',13,10
                   db 'mail@uwe-sieber.de',13,10
                   db 'Try a bit around with pure DOS (a good test is to load high DOSKEY) and backup ',13,10
                   db 'your harddisk before you boot into Win9x GUI - I doensn''t warrenty anything!',13,10
                   db 'Pressione ESC para pular o UMBPCI ou qualquer outra tecla para continuar carregando!',13,10,'$'
  Canceled$        db 'InstalaáÑo Cancelada!',13,10,'$'
  SpaceE$          db '                '
  InternalThanks   db '   Obrigado a Uwe Milde (Suporte ao PPro), Sergei Shtylyov e Serg Svetlov (Suporte ao K7)   '
  InternalThanks2  db '   Obrigado a Nagatoshi Uehara por v†rias dicas muito £teis   '
else
  Copyright$       db 'UMBPCI c''t 11/95 - Siering/SchÑpers/Stiller$'
  Changed$         db ''
                   db VERSION_STRING, ' - Support fÅr neue ChipsÑtze und CPUs - Uwe Sieber ', DATE_STRING,'$'
  NoXMS$           db 'Kein XMS-Treiber vorhanden!$'
  UMBPresent$      db 'UMB Server bereits installiert!',13,10
                   db 'Installation abgebrochen!',13,10,'$'
  NoFreeBlock$     db 'Keinen unbenutzen Speicher-Block gefunden',13,10,'$'
  BadCmd$          db ''
                   db 'Probleme mit den Bereichsangaben in CONFIG.SYS!',13,10
                   db 'Format: DEVICE=UMBPCI.SYS /I=aaaa-bbbb /I=cccc-dddd',13,10
                   db 'Nur der Bereich C800-EFFF wird unterstÅtzt',13,10
                   db 'Nur ganze 16K-Blîcke sind erlaubt, z.B. /I=c800-cfff oder /I=c800-efff',13,10,'$'
                   db 'Auf AMD K7/K8 sind 4K-Blîcke erlaubt, z.B. /I=c900-ceff oder /I=c800-efff',13,10,'$'
                   db 'Ohne Parameter geladen, werden alle freien Bereiche gesucht und benutzt$'
  RAMFail1$        db 13,10,'Kein RAM im Segment (hex) $'
  RAMFail2$        db ' - Installation abgebrochen -$'
  HookErr$         db 'Hook-Chain von HIMEM.SYS beschÑdigt bzw. unbekannt !$'
  Installed$       db 'Programm installiert$'
  NoPCI$           db 'UMBPCI erzeugt UMBs auf PCI-ChipsÑtzen (daher der Name...).',13,10
                   db 'Dieser Computer hat keinen PCI-Chipsatz!$'
  SetErr$          db 'Problem mit PCI-Chipsatz-Programmierung!$'
  SkipK7Msg$       db 'AMD K7 Erkennung deaktiviert',13,10,'$';
  PressKey$        db 'beliebige Taste drÅcken...$'
  Unsupp2$         db 'Dieser Chipsatz wird wegen fehlendem Datenblatt nicht unterstÅtzt$'
  Unsupp3$         db 'Dieser Chipsatz wird nicht unterstÅtzt, da er kein Shadow RAM besitzt$'
  Unsupp4$         db 'Der Konfigurationsmechanismus dieses Chipsatzes wird nicht unterstÅtzt.$'
  Unsupp5$         db 'Dieser Chipsatz wird nicht unterstÅtzt, da sein Shadow-RAM nicht',13,10
                   db 'wie im Datenblatt beschrieben funktioniert.$'
  Unsupp6$         db 'Dieser Chipsatz hat keine Hostbridge als device 0 auf bus 0',13,10,'$'
  NoIntel$         db 'Der Chipsatz ist unbekannt!',13,10
;                   db 'Bitte ÅberprÅfen Sie auf http://www.uwe-sieber.de/umbpci.html, ob',13,10
;                   db 'es sich um die aktuelle Version von UMBPCI handelt. Falls ja, bitte',13,10
;                   db 'folgende Daten an mail@uwe-sieber.de mailen:$'
  Found_String$    db ' erkannt$'
  Using_String$    db 'Benutze $'
  iErr$            db 'Interner Fehler :-($'
  Initialized$     db 'Kein geladenen HIMEM gefunden, UMB-Speicher nur aktiviert$'
  Untested$        db ''
                   db 'Dieser Chipsatz ist ungetestet. Bitte mailen Sie mir den Namen des Chipsatzes',13,10
                   db 'und ob es funktioniert, damit ich ggf. diese Pause entfernen kann:',13,10
                   db 'mail@uwe-sieber.de',13,10
                   db 'Testen Sie erst, ob es im puren DOS funktioniert bevor Sie Win9x GUI hochfahren',13,10
                   db '(das Hochladen von DOSKEY ist ein guter Test) und machen Sie vorher ein',13,10
                   db 'Backup - ich garantiere fÅr nichts!',13,13,10
                   db 'DrÅcken Sie "Esc" um abzubrechen oder eine andere Taste um fortzufahren!',13,10,'$'
  Canceled$        db 'Installation abgebrochen!',13,10,'$'
  Space$           db '                '
  InternalThanks   db '   Dank an Uwe Milde (PPro Support), sowie Sergei Shtylyov und Serg Svetlov (K7-Support)   '
  InternalThanks2  db '   Dank an Nagatoshi Uehara fÅr viele wertvolle Hinweise   '
endif

ifdef P2DebugVersion
  lese             db 'lese    : $'
  schreibe         db 'schreibe: $'
endif

ifdef DebugVersion2
  Step1            db 'Step1',13,10,'$'
  Step2            db 'Step2',13,10,'$'
  Step3            db 'Step3',13,10,'$'
  Step4            db 'Step4',13,10,'$'
endif
;----------------------------- END OF MESSAGES --------------------------------

; Called with ES:DI pointing into the command line
; Returns with DI+4, value or 0 in DX, and Z flag cleared/set
Hex_To_Val:
    push  cx
    mov   cx,0404h                 ; Counter, shift counter
    xor   dx,dx                    ; Value

Do_Digit:
    shl   dx,cl                    ; One position to the left
    mov   al,es:[di]               ; Gets one character
    inc   di
    cmp   al,'9'
    jbe   Is_Digit
    and   al,0DFh                  ; Turn char upper case
    cmp   al,'A'
    jb    No_Char                  ; Error. Not an hexadecimal value character
    cmp   al,'F'
    ja    No_Char                  ; Error. Not an hexadecimal value character
    sub   al,55                    ; 'A'..'F' -> 10..16
    jmp   SHORT Set_Dig            ; Insert

Is_Digit:
    cmp   al,'0'
    jb    No_Char                  ; Error
    sub   al,'0'                   ; '0'..'9' -> 0..9

Set_Dig:
    or    dl,al                    ; Insert
    dec   ch
    jnz   Do_Digit
    jmp   SHORT Dig_Done

No_Char:
    xor   dx,dx                    ; Error display: DX = 0

Dig_Done:
    pop   cx
    or    dx,dx
    ret

;;; CmdLineEmpty:                  ; unused, removed (Ninho)


;------------------------------------------------------------------------------
; Parse the command line. Called with ES:DI = command line,
; returns with UMBList set and Carry set/cleared
;------------------------------------------------------------------------------
Set_List:
    xor   bx,bx                    ; Index in UMBs_List

Do_Elem:
    mov   al,es:[di]
    inc   di
    cmp   al,13                    ; Is a Carriage Return?
    je    List_Set                 ; -> Yes. Then finish
    cmp   al,10                    ; Is a Line Feed?
    je    List_Set                 ; -> Yes. Then finish
    cmp   al,'/'                   ; Is a Slash from "/I=..."?
    jne   Do_Elem
    mov   ax,es:[di]

    ;------ /7 - skip K7 test ------
    cmp   al,'7'
    jne   @No_7
    ;; '/7'                        , Was processed already before preinit
    jmp   Do_Elem
    ;-------------------------------

@No_7:
    and   al,0DFh                  ; Turn 'i' -> 'I'

    ;------ /S - skip unknown chipset break msg ------
    cmp   al,'S'
    jne   @No_S
    mov   SkipUkcMsg,1
    jmp   Do_Elem
    ;-------------------------------------------------

@No_S:
    cmp   ax,'=I'                  ; Is it "I="? (reversed)
    jne   @No_I                    ;
    add   di,2                     ; OK, skip
    call  Hex_To_Val               ; Parse hexadecimal number -> DX
    jz    List_Error               ; -> Nothing found
    mov   al,es:[di]
    cmp   al,'-'                   ; Separator?
    jne   List_Error               ; -> Nothing found
    inc   di
    call  Test_Start_Address       ; Wert in dx auf Start 16K-Block prÅfen
    jne   List_Error               ; Checks CMP DX,0 from Test_Start_Address
    jb    List_Error
    mov   cx,dx                    ; Startadresse festhalten
    call  Hex_To_Val               ; Endadresse ermitteln
    jz    List_Error               ; -> Nothing found
    call  Test_End_Address         ; Wert in dx auf Ende 16K-Block prÅfen
    jne   List_Error               ; Checks CMP DX,0 from Test_End_Address
    jg    List_Error
    mov   WORD PTR [UMBs_List + bx],cx   ; Entry start address
    mov   ax,dx
    sub   ax,cx                          ; Size in paragraphs
    inc   ax                             ; B000-B7FF is $800 paragraphs!
    mov   WORD PTR [UMBs_List + bx + 2],ax
    add   bx,4
    cmp   bx,40                          ; More than 10 entries?
    jb    Do_Elem                        ; -> No, then continue
    jmp   List_Error

@No_I:
    jmp   Do_Elem

List_Error:
    mov   Param_Error,1
    stc
    ret

List_Set:
    sub   bx,1                     ; Set Carry if BX = 0
    ret
;------------------------------- Set_List END ---------------------------------


Test_Start_Address:
    pusha
    cmp   dx,0C000h
;    jb    @EndTestSA
    jb    @@TSA_End
;    mov   ax,dx
;    mov   bx,Block_Size
;    xor   dx,dx                    ; DX must be clear to divide
;    div   bx
;    cmp   dx,0
    call  Test_Address_Common

;@EndTestSA:
@@TSA_End:    
    popa
    ret


Test_End_Address:
    pusha
    cmp   dx,0FFFFh
;    jg    @End_Test_EA
    jg    @@TEA_End
;    add   dx,1
    inc   dx
;    mov   ax,dx
;    mov   bx,Block_Size
;    xor   dx,dx                    ; DX must be clear to divide
;    div   bx
;    cmp   dx,0
    call  Test_Address_Common

;@End_Test_EA:
@@TEA_End:
    popa
    ret


; This Routine is Common to Test_Start_Address and Test_End_Address
Test_Address_Common:
    mov   ax,dx
    mov   bx,Block_Size
    xor   dx,dx                    ; DX must be clear to divide
    div   bx
    cmp   dx,0                     ; The flags will be tested by the 
                                   ; caller routine
    ret


;----------------------------- Strings for AMD K7 -----------------------------
AMD_ID_String       db "AuthenticAMD"
AMD_K7_Found$       db "AMD K7 CPU$"
AMD_K8_Found$       db "AMD K8 CPU$"

ifdef EnglVersion
AMD_Unknown_Found$  db "Unknown AMD CPU >K8$"
;no_AMD_found$       db "no AMD CPU found$"
elseifdef PTBR
AMD_Unknown_Found$  db "CPU AMD desconhecida! (> K8)$"
;no_AMD_found$       db "nenhuma CPU AMD encontrada$"
else
AMD_Unknown_Found$  db "unbekannte AMD CPU >K8$"
;no_AMD_found$       db "keine AMD CPU gefunden$"
endif
;------------------------------------------------------------------------------


; ----------------------------- ShowDevice-IDs --------------------------------
Vendor$             db '  Vendor: ', 36
Device$             db '  Device: ', 36
North_Bridge$       db ' North-Bridge:', 36
South_Bridge$       db ' South-Bridge:', 36

Device              db 01h

South_Bridge_Found  db 0           ; Flag for South Bridge found

TestClass           dw 0601h, 0602h, 0000h, 0101h
MaxDev              dw 0020h, 0020h, 0002h, 0020h
TCIdx               dw 0000h

Print_Device_IDs:
    ;First, checks if a PCI BIOS is present
;    mov   ax,0B101h
;    int   1Ah
;    jc    @PID_No_PCI_BIOS
;    cmp   ah,0
;    jne   @PID_No_PCI_BIOS
;    cmp   dx,4350h
;;    jne   PID_No_PCI_BIOS              ; PCI BIOS is not present
;;    jmp   PID_PCI_BIOS_OK
;    je    @VPCI_BIOS_OK
    call  Check_PCI_BIOS           ; Check if a PCI BIOS is present
    jnc   @PID_PCI_BIOS_OK         ; Yes (Carry = 0)

;@PID_No_PCI_BIOS:
    call  Print_CRLF
    ret 


;------------------------------------------------------------------------------
;Show Vendor and Device
;------------------------------------------------------------------------------
@PID_PCI_BIOS_OK:
    mov   dx,OFFSET North_Bridge$
    call  Do_Print_Str             ; Prints "North-Bridge:"
    mov   dx,OFFSET Vendor$
    call  Do_Print_Str             ; Prints "Vendor:"

    ;Print Vendor-ID Host-Bridge
;    mov   di,0                     ; Reg.0 = Vendor-ID
;    mov   bx,0                     ; Dev,Func,Bus=0
    xor   di,di                    ; Reg.0 = Vendor-ID
    xor   bx,bx                    ; Dev,Func,Bus=0
    mov   ax,0B109h                ; ReadWord 
    int   1Ah
    mov   ax,cx
    call  Print_Hex_Value
     
    ;Print "Device:"
    mov   dx,OFFSET Device$
    call  Do_Print_Str             ; Prints "Device:"

    ;Print Device-ID Host-Bridge
    mov   di,2                     ; Reg.2 = Device-ID
;    mov   bx,0                     ; Dev,Func,Bus=0
    xor   bx,bx                    ; Dev,Func,Bus=0
    mov   ax,0B109h
    int   1Ah
    mov   ax,cx
    call  Print_Hex_Value
    call  Print_CRLF

    ;--------- Show South Bridge ---------
    mov   dx,OFFSET South_Bridge$
    call  Do_Print_Str             ; Prints "South-Bridge:"
    mov   dx,OFFSET Vendor$
    call  Do_Print_Str             ; Prints "Vendor:"

    mov   Device,1

@South:
;    mov   di,0
    xor   di,di
    mov   bl,Device                ; bei Dev=1 beginnen
    shl   bl,3
    mov   bh,0
    mov   ax,0B109h
    int   1Ah
    cmp   cx,0FFFFh                ; FFFF heisst: Kein Device da
    jne   @South_Bridge_Found

@Next_South:
    inc   Device         ;aufwÑrts bis einschl.
    mov   di,TCIdx
    mov   dx, WORD PTR [MaxDev + di]
    cmp   Device,dl
    je    @Skip_South
    jmp   @South


@South_Bridge_Found:
    ;Base und Sub-Class holen 
    mov   di,0Ah                   ; Reg.0A+0B = Class-Code
;    mov   bx,0                     ; Dev,Func,Bus=0
    mov   ax,0B109h
    int   1Ah
    mov   di,TCIdx
    mov   ax,WORD PTR [TestClass + di]
    cmp   cx,ax
    je    @South_Bridge_Finally_Found

;    cmp   cx,0                    ; auf alten Chipsaetzen kann auch null geliefert werden...
    jmp   @Next_South

@South_Bridge_Finally_Found:
    mov   South_Bridge_Found,1
    ;Vendor holen
;    mov   di,0                     ; Reg.0 = Vendor-ID
    xor   di,di                    ; Reg.0 = Vendor-ID
    mov   ax,0B109h  ;ReadWord
    int   1Ah
    mov   ax,cx
    call  Print_Hex_Value
;--------------
    ;Print "Device:"
    mov   dx,OFFSET Device$
    call  Do_Print_Str
    mov   di,2
    mov   bl,Device                ; Bus stimmt noch von vorhin
    shl   bl,3
    mov   bh,0
    mov   ax,0B109h
    int   1Ah
    mov   ax,cx
    call  Print_Hex_Value

@Skip_South:
    cmp   South_Bridge_Found,1
    je    @South_End
    cmp   TCIdx,6
    je    @South_End

    ;nochmal von vorne
    mov   Device,1
    inc   TCIdx
    inc   TCIdx
    jmp   @South

@South_End:
    call  Print_CRLF
    call  Print_CRLF
    ret 


;------------------------------------------------------------------------------
; Checks for PCI BIOS (Returns Carry = 0 if Present, Otherwise Carry = 1)
;------------------------------------------------------------------------------
Check_PCI_BIOS:
    mov   ax,0B101h
    int   1Ah
    jc    CPB_No_PCI_BIOS          ; PCI Bios not present (CPB stands for Check_PCI_BIOS)
    cmp   ah,0
    jne   CPB_No_PCI_BIOS          ; PCI Bios not present (CPB stands for Check_PCI_BIOS)
    cmp   dx,4350h
    je    CPB_PCI_BIOS_Found       ; PCI BIOS is present, so continue (CPB stands for Check_PCI_BIOS)

CPB_No_PCI_BIOS:
    stc                            ; No PCI BIOS found (Carry flag = 1)
    ret

CPB_PCI_BIOS_Found:
    clc                            ; PCI BIOS found (Carry flag = 0)
    ret


;==============================================================================
;       ************* PCI Chipset Programming Starts Here *************
;==============================================================================

PCIx MACRO n
    mov   ah,0B1h
    mov   al,n
    int   1Ah
ENDM


ToggleCR0 MACRO
    db    0Fh, 20h, 0C0h           ; MOV EAX,CR0
    xor   eax,040000000h
    db    0Fh, 22h, 0C0h           ; MOV CR0,EAX
ENDM


ClearICache MACRO
    db    0Fh, 20h, 0D8h
    db    0Fh, 22h, 0D8h
ENDM


GetMSR MACRO MSR, MSRValLo, MSRValHi
    mov   ecx,MSR
    rdmsr
    mov   MSRValHi,edx
    mov   MSRValLo,eax

ifdef P2DebugVersion2
    pusha
    mov   dx,OFFSET lese
    call  Do_Print_Str
    mov   eax,msr
    call  Print_Hex_value
    mov   dx,OFFSET crlf
    call  Do_Print_Str
    popa
endif
ENDM


;---------------------------------------------
SetMSR MACRO MSR, MSRValLo, MSRValHi
    mov   ecx,MSR
    mov   edx,MSRValHi
    mov   eax,MSRValLo
    wrmsr

ifdef P2DebugVersion
    pusha
    cmp   MSRValHi,0
;    je    lbl11
    mov   dx,OFFSET schreibe
    call  Do_Print_Str
    mov   eax,msr
    call  Print_Hex_Value
    call  prKomma
    mov   eax,msrvallo
    call  Print_Hex_Value
    call  prKomma
    mov   eax,msrvalhi
    call  Print_Hex_Value
    mov   dx,OFFSET CR_LF_$
    call  Do_Print_Str
;lbl11:
    popa
endif
ENDM
;---------------------------------------------

;==============================================================================


;================================ Chipsets List ===============================

INTEL_ID         equ 8086h
VIA_ID           equ 1106h
SIS_ID           equ 1039h
ALI_ID           equ 10B9h
AMD_ID           equ 1022h
OPTI_ID          equ 1045h
UMC_ID           equ 1060h
NV_ID            equ 10DEh
SIO_ID           equ 0484h         ; SIO
PIIX2_ID         equ 122Eh         ; PIIX, Function 0
PIIX3_ID         equ 7000h         ; PIIX3, Function 0
PIIX4_ID         equ 7110h         ; PIIX4, Function 0

ID_LIST_LENGTH   equ 33            ; Length of each data line (register) of
                   ; list (used to scan the chipset list)

ID_List:

;----------------------------------- Intel -----------------------------------
    dw INTEL_ID, 0483h, SIO_ID, OFFSET SIO_List, 0, 0
    db 'Intel Saturn$        '

    dw INTEL_ID, 04A3h, SIO_ID, OFFSET SIO_List, 0, 0
    db 'Intel Mercury/Neptun$'

    dw INTEL_ID, 04A3h,   0000, OFFSET Intel_Uni_List, 0, 0
    db 'Intel Mercury/Neptun$'

    dw INTEL_ID, 122Dh, PIIX2_ID, OFFSET PIIX_List, 0, 0
;    dw INTEL_ID, 04D0h, PIIX2_ID, OFFSET PIIX_List, 0, 0
    db 'Intel 430FX$         '

    dw INTEL_ID, 1235h, 0000, OFFSET Intel_Uni_List, 0, 0
    db 'Intel 430MX$         '

    dw INTEL_ID, 1250h, PIIX3_ID, OFFSET PIIX_List, 0, 0
    db 'Intel 430HX$         '

    ; PCEM
    dw INTEL_ID, 1250h, 0000h, OFFSET Intel_Uni_List, 0, 0
    db 'Intel 430HX virtual$ '

    dw INTEL_ID, 7030h, PIIX2_ID, OFFSET PIIX_List, 0, 0
    db 'Intel 430VX$         '

    dw INTEL_ID, 7030h, PIIX3_ID, OFFSET PIIX_List, 0, 0
    db 'Intel 430VX$         '

    ; virtual machine
    dw INTEL_ID, 7030h, 0000h, OFFSET Intel_Uni_List, 0, 0
    db 'Intel 430VX virtual$ '

    dw INTEL_ID, 7100h, PIIX4_ID, OFFSET PIIX_List, 0, 0
    db 'Intel 430TX$         '

    ; 440FX moved to the end of the list to test the integrity of the list in VirtualBox
    ;dw INTEL_ID, 1237h, PIIX3_ID, OFFSET PIIX_List, 1, 0
    ;db 'Intel 440FX$         '
 
    ; other virtual?
    ;dw INTEL_ID, 1237h, 0000h, OFFSET Intel_Uni_List, 1, 0
    ;db 'Intel 440FX virtual$ '
 
    dw INTEL_ID, 7180h, PIIX4_ID, OFFSET PIIX_List, 1, 0
    db 'Intel 440LX/EX$      '
 
    dw INTEL_ID, 7190h, PIIX4_ID, OFFSET PIIX_List, 1, 0
    db 'Intel 440BX/ZX$      '
 
    ; 440ZX moved to the end of the list to test the integrity of the list in Virtual PC
    ;dw INTEL_ID, 7192h, PIIX4_ID, OFFSET PIIX_List, 1, 0
    ;db 'Intel 440ZX w/o AGP$ '
 
    dw INTEL_ID, 7194h, 0000h, OFFSET Intel_Uni_List, 1, 0
    db 'Intel i440MX$        '

    dw INTEL_ID, 71A0h, PIIX4_ID, OFFSET PIIX_List, 1, 0
    db 'Intel 440GX$         '
 
    dw INTEL_ID, 71A2h, PIIX4_ID, OFFSET PIIX_List, 1, 0
    db 'Intel 440GX w/o AGP$ '

    dw INTEL_ID, 7120h, 0000h, OFFSET Intel810_List, 1, 0
    db 'Intel 810$           '

    dw INTEL_ID, 7122h, 0000h, OFFSET Intel810_List, 1, 0
    db 'Intel 810-DC100$     '

    dw INTEL_ID, 7124h, 0000h, OFFSET Intel810_List, 1, 0
    db 'Intel 810E$          '

    dw INTEL_ID, 7128h, 0000h, OFFSET Intel810_List, 1, UNSUPPORTED_UNTESTED
    db 'Intel 810-M DC100$   '

    dw INTEL_ID, 712Ah, 0000h, OFFSET Intel810_List, 1, UNSUPPORTED_UNTESTED
    db 'Intel 810-M DC133$   '

    dw INTEL_ID, 1100h, 0000h, OFFSET Intel_Uni_List, 1, 0
    db 'Intel 815$           '

    dw INTEL_ID, 1110h, 0000h, OFFSET Intel_Uni_List, 1, 0
    db 'Intel 815$           '

    dw INTEL_ID, 1120h, 0000h, OFFSET Intel_Uni_List, 1, 0
    db 'Intel 815$           '

    dw INTEL_ID, 1130h, 0000h, OFFSET Intel_Uni_List, 1, 0
    db 'Intel 815$           '

    dw INTEL_ID, 2500h, 0000h, OFFSET Intel_Uni_List, 1, 0
    db 'Intel 820$           '

    dw INTEL_ID, 2501h, 0000h, OFFSET Intel_Uni_List, 1, 0
    db 'Intel 820$           '

    dw INTEL_ID, 3575h, 0000h, OFFSET Intel_Uni_List, 1, 0
    db 'Intel 830MP$         '

    dw INTEL_ID, 1A21h, 0000h, OFFSET Intel_Uni_List, 1, UNSUPPORTED_UNTESTED
    db 'Intel 840$           '

    dw INTEL_ID, 1A30h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 845$           '

    dw INTEL_ID, 2560h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 845G$          '

    dw INTEL_ID, 2570h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 848P/865G/P/PE$'

    dw INTEL_ID, 2530h, 0000h, OFFSET Intel_Uni_List, 1, 0
    db 'Intel 850$           '

    dw INTEL_ID, 3580h, 0000h, OFFSET Intel_Uni_List, 1, 0
    db 'Intel 852GM/855GM$   '

    dw INTEL_ID, 3340h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 855PM$         '

    dw INTEL_ID, 2531h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 860$           '

    dw INTEL_ID, 2578h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 875P$          '

    dw INTEL_ID, 2580h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 915G$          '

    dw INTEL_ID, 2584h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 925X$          '

    dw INTEL_ID, 2590h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 915GM$         '

    dw INTEL_ID, 2770h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 945$           '

    dw INTEL_ID, 2970h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 946$           '

    dw INTEL_ID, 2774h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 955$           '

    dw INTEL_ID, 277Ch, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 975$           '

    dw INTEL_ID, 27A0h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 945GM$         '

    dw INTEL_ID, 27ACh, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 945GME$        '

    dw INTEL_ID, 2980h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 965$           '

    dw INTEL_ID, 2990h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 965$           '

    dw INTEL_ID, 29A0h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 965P$          '

    dw INTEL_ID, 2A00h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 965M$          '

    dw INTEL_ID, 2A10h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 965M$          '

    dw INTEL_ID, 2A40h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 4 Mobile$      '

;---------------------------------- Intel 3x ----------------------------------
    dw INTEL_ID, 35B0h, 0000h, OFFSET Intel_Uni_List, 1, 0
    db 'Intel 3100$          '

    dw INTEL_ID, 29F0h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 3200$          '

    dw INTEL_ID, 4030h, 0000h, OFFSET Intel_Uni_List, 1, 1
    db 'Intel 5400$          '

    dw INTEL_ID, 360Ch, 0000h, OFFSET Intel_Uni_List, 1, 1
    db 'Intel 7300$          '

; from datasheets:
; 29C0h = Intel 82G35 GMCH
; 29B0h = Intel 82Q35 GMCH
; 29C0h = Intel 82G33/82P35 (G)
; 29D0h = Intel 82Q33 GMCH

    dw INTEL_ID, 29B0h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Q35$           '

    dw INTEL_ID, 29C0h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel G33/G35/P35$   '

    dw INTEL_ID, 29D0h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Q33$           '

    dw INTEL_ID, 2E10h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Q4 Series$     '
 
    dw INTEL_ID, 2E20h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel 4 Series$      '
 
    dw INTEL_ID, 2E30h, 0000h , OFFSET Intel845_List, 1, 0
    db 'Intel G41$           ' 

    dw INTEL_ID, 2E40h, 0000h , OFFSET Intel845_List, 1, 0
    db 'Intel B43$           ' 

    dw INTEL_ID, 29E0h, 0000h , OFFSET Intel845_List, 1, 0
    db 'Intel X38/X48$       ' 

;--------------------- Intel Core i CPUs DRAM Controllers ---------------------
    dw INTEL_ID, 0040h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Core i3/i5 CPU$' 

    ; Core i7 Device 0 Function 1
    dw INTEL_ID, 2C01h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Core i7 CPU$   '

    ; Core i7 Device 0 Function 0
    ; dw INTEL_ID, 2C41h, 0000h , OFFSET Intel845_List, 1, 0
    ; db 'Intel Core i7 CPU$   '

    dw INTEL_ID, 2C70h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Core i7 CPU$   ' 

    dw INTEL_ID, 2C50h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Core i7 CPU$   ' 
 
    dw INTEL_ID, 2C51h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Core i7 CPU$   ' 
 
    dw INTEL_ID, 2C52h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Core i7 CPU$   ' 
 
    dw INTEL_ID, 2C53h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Core i7 CPU$   '
 
    dw INTEL_ID, 2C54h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Core i7 CPU$   '
 
    dw INTEL_ID, 2C55h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Core i7 CPU$   '
 
    dw INTEL_ID, 2C56h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Core i7 CPU$   '
 
    dw INTEL_ID, 2C57h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Core i7 CPU$   '

    dw INTEL_ID, 0044h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Core i3/i5 CPU$'

    dw INTEL_ID, 0048h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Core i3/i5 CPU$'

    dw INTEL_ID, 0D131h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Core i5/i7 CPU$'

    dw INTEL_ID, 0D132h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Core i7 CPU$   '

    dw INTEL_ID, 0100h, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    db 'Intel Core 2nd Gen$  '
 
    dw INTEL_ID, 0104h, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    db 'Intel Core 2nd Gen$  '
 
    dw INTEL_ID, 0108h, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    db 'Intel Core 2nd Gen$  '
 
    dw INTEL_ID, 010Ch, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    db 'Intel Core 2nd Gen$  '

    dw INTEL_ID, 0150h, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    db 'Intel Core 3rd Gen$  '
 
    dw INTEL_ID, 0154h, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    db 'Intel Core 3rd Gen$  '
 
    dw INTEL_ID, 0158h, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    db 'Intel Core 3rd Gen$  '
 
    dw INTEL_ID, 015Ch, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    db 'Intel Core 3rd Gen$  '

    dw INTEL_ID, 0C00h, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    db 'Intel Core 4th Gen$  '
 
    dw INTEL_ID, 0C04h, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    db 'Intel Core 4th Gen$  '
 
    dw INTEL_ID, 0D04h, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    db 'Intel Core 4th Gen$  '
 
    dw INTEL_ID, 0A04h, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    db 'Intel Core 4th Gen$  '
 
    dw INTEL_ID, 0D00h, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    db 'Intel Core 4th Gen$  '
 
    dw INTEL_ID, 0A04h, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    db 'Intel Core 4th Gen$  '

    dw INTEL_ID, 1900h, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    db 'Intel Core 6th Gen$  '
 
    dw INTEL_ID, 190Fh, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    db 'Intel Core 6th Gen$  '
 
    dw INTEL_ID, 191Fh, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    db 'Intel Core 6th Gen$  '

;------------------------------- Core 7th Gen ---------------------------------
    dw INTEL_ID, 5900h, 0000h, OFFSET IntelCore7thGen_List, 1, 0
    db 'Intel Core 7th Gen$  '
 
    dw INTEL_ID, 5904h, 0000h, OFFSET IntelCore7thGen_List, 1, 0
    db 'Intel Core 7th Gen$  '
 
    dw INTEL_ID, 590ch, 0000h, OFFSET IntelCore7thGen_List, 1, 0
    db 'Intel Core 7th Gen$  '
 
    dw INTEL_ID, 590fh, 0000h, OFFSET IntelCore7thGen_List, 1, 0
    db 'Intel Core 7th Gen$  '
 
    dw INTEL_ID, 5910h, 0000h, OFFSET IntelCore7thGen_List, 1, 0
    db 'Intel Core 7th Gen$  '
 
    dw INTEL_ID, 5914h, 0000h, OFFSET IntelCore7thGen_List, 1, 0
    db 'Intel Core 7th Gen$  '
 
    dw INTEL_ID, 5918h, 0000h, OFFSET IntelCore7thGen_List, 1, 0
    db 'Intel Core 7th Gen$  '
 
    dw INTEL_ID, 591fh, 0000h, OFFSET IntelCore7thGen_List, 1, 0
    db 'Intel Core 7th Gen$  '

;------------------------------- Xeon E3-1200 ---------------------------------
    dw INTEL_ID, 3e10h, 0000h, OFFSET IntelCore7thGen_List, 1, 0
    db 'Intel Core 8th Gen$  '
 
    dw INTEL_ID, 3e18h, 0000h, OFFSET IntelCore7thGen_List, 1, 0
    db 'Intel Core 8th Gen$  '
 
    dw INTEL_ID, 3e1fh, 0000h, OFFSET IntelCore7thGen_List, 1, 0
    db 'Intel Core 8th Gen$  '
 
    dw INTEL_ID, 3e30h, 0000h, OFFSET IntelCore7thGen_List, 1, 0
    db 'Intel Core 8th Gen$  '
 
    dw INTEL_ID, 3e33h, 0000h, OFFSET IntelCore7thGen_List, 1, 0
    db 'Intel Core 8th Gen$  '
 
    dw INTEL_ID, 3e34h, 0000h, OFFSET IntelCore7thGen_List, 1, 0
    db 'Intel Core 8th Gen$  '

;------------------------------- Core 8/9th Gen -------------------------------
    dw INTEL_ID, 3ec2h, 0000h, OFFSET IntelCore7thGen_List, 1, 0
    db 'Intel Core 8th Gen$  '
 
    dw INTEL_ID, 3ec4h, 0000h, OFFSET IntelCore7thGen_List, 1, 0
    db 'Intel Core 8th Gen$  '
 
    dw INTEL_ID, 3ec6h, 0000h , OFFSET IntelCore7thGen_List, 1, 0
    db 'Intel Core 8th Gen$  '
 
    dw INTEL_ID, 3ecah, 0000h , OFFSET IntelCore7thGen_List, 1, 0
    db 'Intel Core 8th Gen$  '
 
    dw INTEL_ID, 3ed0h, 0000h , OFFSET IntelCore7thGen_List, 1, 0
    db 'Intel Core 8th Gen$  '

;------------------------------- Core 10th Gen --------------------------------
    ;Y Processor 2 Cores 0x8A00h
    dw INTEL_ID, 8A00h, 0000h, OFFSET IntelCore7thGen_List, 1, UNSUPPORTED_UNTESTED
    db 'Intel Core 10th Gen$ '
 
    ;U Processor 2 Cores 0x8A02h
    dw INTEL_ID, 8A02h, 0000h, OFFSET IntelCore7thGen_List, 1, UNSUPPORTED_UNTESTED
    db 'Intel Core 10th Gen$ '
 
    ;Y Processor 4 Cores 0x8A10h
    dw INTEL_ID, 8A10h, 0000h, OFFSET IntelCore7thGen_List, 1, UNSUPPORTED_UNTESTED
    db 'Intel Core 10th Gen$ '
 
    ;U Processor 4 Cores 0x8A12h
    dw INTEL_ID, 8A12h, 0000h, OFFSET IntelCore7thGen_List, 1, UNSUPPORTED_UNTESTED
    db 'Intel Core 10th Gen$ '
 
    dw INTEL_ID, 9B53h, 0000h, OFFSET IntelCore7thGen_List, 1, UNSUPPORTED_UNTESTED
    db 'Intel Core 10th Gen$ '

;------------------------------- Core 11th Gen --------------------------------
    ;11th Generation IntelÆ Coreô Processor 8 Core 4C43h
    dw INTEL_ID, 4C43h, 0000h, OFFSET IntelCore7thGen_List, 1, UNSUPPORTED_UNTESTED
    db 'Intel Core 11th Gen$ '
 
    ;11th Generation IntelÆ Coreô Processor 6 Core 4C53h
    dw INTEL_ID, 4C53h, 0000h, OFFSET IntelCore7thGen_List, 1, UNSUPPORTED_UNTESTED
    db 'Intel Core 11th Gen$ '

;------------------------------- Core 12th Gen --------------------------------
    ;S LGA 8+8
    dw INTEL_ID, 4660h, 0000h, OFFSET IntelCore7thGen_List, 1, UNSUPPORTED_UNTESTED
    db 'Intel Core 12th Gen$ '
 
    ;S LGA 8+4
    dw INTEL_ID, 4668h, 0000h, OFFSET IntelCore7thGen_List, 1, UNSUPPORTED_UNTESTED
    db 'Intel Core 12th Gen$ '
 
    ;S LGA 6+4 
    dw INTEL_ID, 4648h, 0000h, OFFSET IntelCore7thGen_List, 1, UNSUPPORTED_UNTESTED
    db 'Intel Core 12th Gen$ '

    dw INTEL_ID, 1604h, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    db 'Intel Broadwell-U$   '


; already as 'Intel Core 3rd Gen'
    ;dw INTEL_ID, 0150h, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    ;db 'Intel XEON E3-1200v2$'

    dw INTEL_ID, 0C08h, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    db 'Intel XEON E3-1200v3$'

    dw INTEL_ID, 000Bh, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    db 'Intel XEON E3-1200v4$'

    dw INTEL_ID, 3C00h, 0000h, OFFSET No_List, 1, UNSUPPORTED_NO_SHADOW_RAM
    db 'Intel XEON E5$       '

    dw INTEL_ID, 2D81h, 0000h, OFFSET IntelCore2011_List, 1, 0
    db 'Intel XEON 5600$     '

    ;dw INTEL_ID, 0E00h, 0000h, OFFSET IntelCore2ndGen_List, 1, 0
    ;db 'Intel Core i7$       '

    ;dw INTEL_ID, 2C61h, 0000h, OFFSET IntelCore2011_List, 1, 0
    ;db 'Intel Core CPU$      '
 
    dw INTEL_ID, 3CF4h, 0000h , OFFSET IntelCore2011_List, 1, 0
    db 'Intel Core CPU$      '


;Intel845_List

;-------------------------- Intel Core Chipsets -------------------------
;    dw INTEL_ID, 3B02h, 0000h, OFFSET No_List, 1, UnsuppCoreCpu
;    db 'Intel P55$           ' 
;
;    dw INTEL_ID, 3B03h, 0000h, OFFSET No_List, 1, UnsuppCoreCpu
;    db 'Intel PM55$          ' 
;
;    dw INTEL_ID, 3B06h, 0000h , OFFSET No_List, 1, UnsuppCoreCpu
;    db 'Intel H55$           ' 
;
;    dw INTEL_ID, 3B07h, 0000h, OFFSET No_List, 1, UnsuppCoreCpu
;    db 'Intel QM57$          ' 
;
;    dw INTEL_ID, 3B08h, 0000h, OFFSET No_List, 1, UnsuppCoreCpu
;    db 'Intel H57$           ' 
;
;    dw INTEL_ID, 3B09h, 0000h, OFFSET No_List, 1, UnsuppCoreCpu
;    db 'Intel HM55$          ' 
;
;    dw INTEL_ID, 3B0Ah, 0000h, OFFSET No_List, 1, UnsuppCoreCpu
;    db 'Intel Q57$           ' 
;
;    dw INTEL_ID, 3B0B, 0000h , OFFSET No_List, 1, UnsuppCoreCpu
;    db 'Intel HM57$          ' 
;
;    dw INTEL_ID, 3B0Fh, 0000h, OFFSET No_List, 1, UnsuppCoreCpu
;    db 'Intel QS57$          ' 
;
;    dw INTEL_ID, 3B12h, 0000h, OFFSET No_List, 1, UnsuppCoreCpu
;    db 'Intel 3400$          ' 
;
;    dw INTEL_ID, 3B14h, 0000h, OFFSET No_List, 1, UnsuppCoreCpu
;    db 'Intel 3420$          ' 
;
;    dw INTEL_ID, 3B16h, 0000h, OFFSET No_List, 1, UnsuppCoreCpu
;    db 'Intel 3450$          ' 
;


;------------------------------ Intel Atom  ----------------------------
    dw INTEL_ID, 0F00h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Atom Z36/Z37xx$' 

    dw INTEL_ID, 22C8h, 0000h, OFFSET No_List, 1, UNSUPPORTED_NO_HOST_BRIDGE
    db 'Intel Pentium Nxxxx$ '

    dw INTEL_ID, 4114h, 0000h, OFFSET Intel845_List, 1, UNSUPPORTED_UNTESTED
    db 'Intel Atom E6xx$     ' 

    dw INTEL_ID, 4114h, 0000h, OFFSET Intel845_List, 1, UNSUPPORTED_UNTESTED
    db 'Intel Atom E6xx$     ' 

    dw INTEL_ID, 8100h, 0000h, OFFSET Intel_Atom_List, 1, UNSUPPORTED_UNTESTED
    db 'Intel US15W/X$       ' 

    dw INTEL_ID, 8101h, 0000h, OFFSET Intel_Atom_List, 1, UNSUPPORTED_UNTESTED
    db 'Intel US11L/15L$     ' 

    dw INTEL_ID, 0A000h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Atom D4xx/D5xx$' 

    dw INTEL_ID, 0A010h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel Atom N4xx$     ' 

;------------------------------- Intel Server ---------------------------------
    dw INTEL_ID, 2540h, 0000h, OFFSET Intel_Uni_List, 1, 0
    db 'Intel E7500$         '

    dw INTEL_ID, 254Ch, 0000h, OFFSET Intel_Uni_List, 1, 0
    db 'Intel E7501$         '

    dw INTEL_ID, 2550h, 0000h, OFFSET Intel_Uni_List, 1, 0
    db 'Intel E7505$         '

    dw INTEL_ID, 255Dh, 0000h, OFFSET Intel_Uni_List, 1, 0
    db 'Intel E7205$         '

    dw INTEL_ID, 2578h, 0000h, OFFSET Intel_Uni_List, 1, 0
    db 'Intel E7210$         '

    dw INTEL_ID, 2588h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel E7221$         '

    dw INTEL_ID, 2778h, 0000h, OFFSET Intel845_List, 1, 0
    db 'Intel E7230$         '

    dw INTEL_ID, 3590h, 0000h, OFFSET Intel_Uni_List, 1, 0
    db 'Intel E7520$         '

    dw INTEL_ID, 359Eh, 0000h,  OFFSET Intel_Uni_List, 1, 0
    db 'Intel E7525$         '

    dw INTEL_ID, 3592h, 0000h, OFFSET Intel_Uni_List, 1, 0
    db 'Intel E7350$         '

    dw INTEL_ID, 3600h, 0000h, OFFSET Intel_Uni_List, 1, 0
    db 'Intel E7300$         '

    dw INTEL_ID, 25C0h, 0000h, OFFSET Intel_Uni_List, 1, UNSUPPORTED_CONFIG_MECHANISM
    db 'Intel 5000X$         '

    dw INTEL_ID, 25C8h, 0000h, OFFSET Intel_Uni_List, 1, UNSUPPORTED_CONFIG_MECHANISM
    db 'Intel 5000P$         '

    dw INTEL_ID, 25D0h, 0000h, OFFSET Intel_Uni_List, 1, UNSUPPORTED_CONFIG_MECHANISM
    db 'Intel 5000Z$         '

    dw INTEL_ID, 25D4h, 0000h, OFFSET Intel_Uni_List, 1, UNSUPPORTED_CONFIG_MECHANISM
    db 'Intel 5000V$         '

    dw INTEL_ID, 25D8h, 0000h, OFFSET Intel_Uni_List, 1, UNSUPPORTED_CONFIG_MECHANISM
    db 'Intel 5000P$         '

    dw INTEL_ID, 65C0h, 0000h, OFFSET Intel_Uni_List, 1, UNSUPPORTED_CONFIG_MECHANISM
    db 'Intel 5100$          '

    dw INTEL_ID, 4000h, 0000h, OFFSET Intel_Uni_List, 1, UNSUPPORTED_CONFIG_MECHANISM
    db 'Intel 5400$          '

    dw INTEL_ID, 4003h, 0000h, OFFSET Intel_Uni_List, 1, UNSUPPORTED_CONFIG_MECHANISM
    db 'Intel 5400$          '


;------------------------------- Intel Alt ------------------------------------
    dw INTEL_ID, 0486h, 0000h, OFFSET Intel_Uni_List, 0, UNSUPPORTED_UNTESTED
    db 'Intel Aries$         '

    dw INTEL_ID, 84C5h, PIIX2_ID, OFFSET PIIX_List, 1, UNSUPPORTED_UNTESTED
    db 'Intel 450KX/GX+PIIX2$'

    dw INTEL_ID, 84C5h, PIIX3_ID, OFFSET PIIX_List, 1, UNSUPPORTED_UNTESTED
    db 'Intel 450KX/GX+PIIX3$'

    dw INTEL_ID, 84CAh, 0000h, OFFSET Intel_Uni_List, 1, UNSUPPORTED_UNTESTED
    db 'Intel 440NX$         '


;-----------------------------------------
;-------------- ATI P4 -------------------
;-----------------------------------------
    dw 1002h, 0CBB2h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
    db 'ATI RS200$           '

    dw 1002h, 5830h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
    db 'ATI RS300            '
 
    dw 1002h, 5831h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
    db 'ATI RS300            '
 
    dw 1002h, 5832h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
    db 'ATI RS300            '

    dw 1002h, 5833h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
    db 'ATI IGP9100$         '

    dw 1002h, 5835h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
    db 'ATI RS300M$          '

    dw 1002h, 5A30h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
    db 'ATI RS400/100$       '
 
    dw 1002h, 5A31h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
    db 'ATI RS400/133&       '
 
    dw 1002h, 5A32h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
    db 'ATI RS400/166$       '
 
    dw 1002h, 5A33h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
    db 'ATI RS400/200$       '


;-----------------------------------------
;-------------- AMD ----------------------
;-----------------------------------------
    dw 1022h, 3000h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
    db 'AMD Elan SC520$      '


;-----------------------------------------
;-------------- nVidia -------------------
;-----------------------------------------
    dw 10DEh, 0071h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
    db 'nVidia nForce4$      '

    dw 10DEh, 03A1h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
    db 'nVidia unknown$      '


;-----------------------------------------
;-------------- VIA P2, P3 ---------------
;-----------------------------------------
 dw VIA_ID, 0691h, 0586h, OFFSET VIA_List, 1, 0
 db 'VIA Apollo Pro$      '

 dw VIA_ID, 0691h, 0596h, OFFSET VIA_List, 1, 0
 db 'VIA Apollo Pro$      '

 dw VIA_ID, 0691h, 0686h, OFFSET VIA_List, 1, 0
 db 'VIA Apollo Pro$      '

 dw VIA_ID, 0693h, 0596h, OFFSET VIA_List, 1, 0
 db 'VIA Apollo Pro Plus$ '

 dw VIA_ID, 0693h, 0686h, OFFSET VIA_List, 1, 0
 db 'VIA Apollo Pro Plus$ '

 dw VIA_ID, 0601h, 0686h, OFFSET VIA_List, 1, 0
 db 'VIA Apollo PM601$    '

 dw VIA_ID, 0601h, 08231h, OFFSET VIA_List, 1, 0
 db 'VIA Apollo PLE133$   '

 dw VIA_ID, 0605h, 0686h, OFFSET VIA_List, 1, 0
 db 'VIA Apollo PM133$    '

 dw VIA_ID, 0605h, 0000h, OFFSET VIA_List, 1, 0
 db 'VIA Apollo PM133$    '

 dw VIA_ID, 3091h, 0686h, OFFSET No_List, 1, UNSUPPORTED_NO_DATASHEET
 db 'VIA Apollo Pro 266$  '

 dw VIA_ID, 3091h, 0000h, OFFSET VIA_Uni_List, 1, 0
 db 'VIA Apollo Pro 266$  '

 dw VIA_ID, 3101h, 0000h, OFFSET No_List, 1, UNSUPPORTED_NO_DATASHEET
 db 'VIA VT8653$          '

 dw VIA_ID, 3103h, 0000h, OFFSET No_List, 1, UNSUPPORTED_NO_DATASHEET
 db 'VIA VT8615$          '

 dw VIA_ID, 3123h, 0000h, OFFSET VIA_Uni_List, 1, 0
 db 'VIA EPIA-M$          '


; ------------- VIA P4 --------------------

    dw VIA_ID, 3128h, 0000h, OFFSET VIA_Uni_List, 1, 0
    db 'VIA P4X266$          '

    dw VIA_ID, 3148h, 0000h, OFFSET VIA_Uni_List, 1, 0
    db 'VIA P4M266$          '

    dw VIA_ID, 3158h, 0000h, OFFSET VIA_Uni_List, 1, 0
    db 'VIA P4N266$          '

    dw VIA_ID, 3168h, 0000h, OFFSET VIA_Uni_List, 1, 0
    db 'VIA P4X333$          '

    dw VIA_ID, 3178h, 0000h, OFFSET VIA_Uni_List, 1, 0
    db 'VIA P4N333$          '

    dw VIA_ID, 3198h, 0000h, OFFSET VIA_Uni_List, 1, 0
    db 'VIA P4X600$          '

    dw VIA_ID, 0258h, 0000h, OFFSET VIA_Uni_List, 1, 0
    db 'VIA PT880$           '

    dw VIA_ID, 0259h, 0000h, OFFSET VIA_Uni_List, 1, 0
    db 'VIA PM880$           '

    dw VIA_ID, 0296h, 0000h, OFFSET VIA_Uni_List, 1, 0
    db 'VIA P4M800$          '

    dw VIA_ID, 0290h, 0000h, OFFSET VIA_Uni_List, 1, UNSUPPORTED_UNTESTED
    db 'VIA P4 chipset$      '

    dw VIA_ID, 0308h, 0000h, OFFSET No_List, 1, UNSUPPORTED_NO_DATASHEET
    db 'VIA PT880$           '

;    dw VIA_ID, 0314h, 0000h, OFFSET No_List, 1, UNSUPPORTED_NO_DATASHEET
;    db 'VIA P4 chipset$      '

;    dw VIA_ID, 0324h, 0000h, OFFSET No_List, 1, UNSUPPORTED_NO_DATASHEET
;    db 'VIA P4 chipset$      '

;    dw VIA_ID, 0327h, 0000h, OFFSET No_List, 1, UNSUPPORTED_NO_DATASHEET
;    db 'VIA P4M890$          '

    dw VIA_ID, 0336h, 0000h, OFFSET No_List, 1, UNSUPPORTED_NO_DATASHEET
    db 'VIA K8M890CE$        '

    dw VIA_ID, 0340h, 0000h, OFFSET No_List, 1, UNSUPPORTED_NO_DATASHEET
    db 'VIA PT900$           '

    dw VIA_ID, 0351h, 0000h, OFFSET No_List, 1, UNSUPPORTED_NO_DATASHEET
    db 'VIA P4 chipset$      '

    dw VIA_ID, 0353h, 0000h, OFFSET No_List, 1, UNSUPPORTED_NO_DATASHEET
    db 'VIA chipset$         '

    dw VIA_ID, 0364h, 0000h, OFFSET No_List, 1, UNSUPPORTED_NO_DATASHEET
    db 'VIA P4M900$          '

;------------------- VIA Unknown --------------------
    dw VIA_ID, 3133h, 0000h, OFFSET VIA_Uni_List, 1, UNSUPPORTED_UNTESTED
    db 'VIA VT3133$          '

    dw VIA_ID, 3158h, 0000h, OFFSET VIA_Uni_List, 1, UNSUPPORTED_UNTESTED
    db 'VIA P4 ??? Dev=3158$ '

    dw VIA_ID, 3156h, 0000h, OFFSET VIA_Uni_List, 1, UNSUPPORTED_UNTESTED
    db 'VIA P/KN266$         '

;--------------------- VIA K7 ------------------------
;    dw VIA_ID, 0391h, 0686h, OFFSET No_List, 1, UNSUPPORTED_WRONG_DOC
;    db 'VIA KX133$           '
;
;    dw VIA_ID, 0305h, 0686h, OFFSET No_List, 1, UNSUPPORTED_WRONG_DOC
;    db 'VIA KT133$           '
;
;    dw VIA_ID, 0305h, 0000h, OFFSET No_List, 1, UNSUPPORTED_WRONG_DOC
;    db 'VIA KT133$           '
;
;    dw VIA_ID, 3099h, 0000h, OFFSET No_List, 1, UNSUPPORTED_NO_DATASHEET
;    db 'VIA KT266/KT333$     '
;
;    dw VIA_ID, 3189h, 0000h, OFFSET No_List, 1, UNSUPPORTED_NO_DATASHEET
;    db 'VIA KT400$           '
;
;    dw VIA_ID, 3112h, 0000h, OFFSET No_List, 1, UNSUPPORTED_NO_DATASHEET
;    db 'VIA KLE133$          '
;
;    dw VIA_ID, 3102h, 0000h, OFFSET No_List, 1, UNSUPPORTED_NO_DATASHEET
;    db 'VIA VT8362$          '


; --------------------------------------------
; ------------ VIA K8 ------------------------
; --------------------------------------------
;    dw VIA_ID, 3188h, 0000h, OFFSET No_List, 1, UNSUPPORTED_NO_DATASHEET
;    db 'VIA K8HTB$           '


; --------------------------------------------
; ------------ VIA Socket 7 ------------------
; --------------------------------------------
    dw VIA_ID, 0576h, 0000h, OFFSET No_List, 0, 4
    db 'VIA Apollo$          '

    dw VIA_ID, 0585h, 0586h, OFFSET VIA_List, 0, 0
    db 'VIA Apollo VP/VPX$   '

    dw VIA_ID, 0595h, 0586h, OFFSET VIA_List, 0, 0
    db 'VIA Apollo VP2$      '

    dw VIA_ID, 1595h, 0586h, OFFSET VIA_List, 0, 0
    db 'VIA Apollo VP2/97$   '

    dw VIA_ID, 0598h, 0586h, OFFSET VIA_List, 0, 0
    db 'VIA Apollo MVP3$     '

    dw VIA_ID, 0598h, 0596h, OFFSET VIA_List, 0, 0
    db 'VIA Apollo MVP3+$    '

    dw VIA_ID, 0598h, 0686h, OFFSET VIA_List, 0, 0
    db 'VIA Apollo MVP3++$   '

    dw VIA_ID, 0597h, 0586h, OFFSET VIA_List, 0, 0
    db 'VIA Apollo VP3$      '

    dw VIA_ID, 0598h, 0586h, OFFSET VIA_List, 0, 0      ;8598h ist die AGP-Bridge...
    db 'VIA Apollo MVP3$     '

    dw VIA_ID, 0597h, 0596h, OFFSET VIA_List, 0, 0
    db 'VIA Apollo VP3+$     '

    dw VIA_ID, 0597h, 0686h, OFFSET VIA_List, 0, 0
    db 'VIA Apollo MVP3++$   '

    dw VIA_ID, 0501h, 0686h, OFFSET VIA_List, 0, 0
    db 'VIA Apollo MVP4$     '


;----------------------- VIA C7 -----------------------
;    dw VIA_ID, 7324h, 3324h, OFFSET VIA_CX700_List, 0, 0
;    db 'VIA CX700$           '
;
;    dw VIA_ID, 7353h, 3353h, OFFSET VIA_CX700_List, 0, 0
;    db 'VIA VX800/VX820$     '
;
;    dw VIA_ID, 7409h, 3409H, OFFSET VIA_CX700_List, 0, 0
;    db 'VIA VX855/VX875$     '
;
;    dw VIA_ID, 7410h, 3410H, OFFSET VIA_CX700_List, 0, 0
;    db 'VIA VX900$           '

    dw VIA_ID, 3324h, 0, OFFSET VIA_CX700_List, 0, 0
    db 'VIA CX700$           '

    dw VIA_ID, 3353h, 0, OFFSET VIA_CX700_List, 0, 0
    db 'VIA VX800/VX820$     '

    dw VIA_ID, 3409H, 0, OFFSET VIA_CX700_List, 0, 0
    db 'VIA VX855/VX875$     '

    dw VIA_ID, 3410H, 0, OFFSET VIA_CX700_List, 0, 0
    db 'VIA VX900$           '


;----------------------------------------------
;----------------------- SIS ------------------
; --------------------------------------------
    dw SIS_ID, 0496h, 0000h, OFFSET SIS496_List, 0, UNSUPPORTED_UNTESTED
    db 'SiS 496$             '

    dw SIS_ID, 0406h, 0000h, OFFSET SIS501_List, 0, 0
    db 'SiS 501$             '

    dw SIS_ID, 5511h, 0008h, OFFSET SIS511_List, 0, 0
    db 'SiS 5511$            '

    dw SIS_ID, 5571h, 0008h, OFFSET SIS571_List, 0, 0
    db 'SiS 5571$            '

    dw SIS_ID, 5596h, 0008h, OFFSET SIS59x_List, 0, 0
    db 'SiS 5596$            '

    dw SIS_ID, 5597h, 0008h, OFFSET SIS597_List, 0, 0
    db 'SiS 5581/82/97/98$   '

    dw SIS_ID, 5591h, 0008h, OFFSET SIS59x_List, 0, 0
    db 'SiS 5591/92$         '

    dw SIS_ID, 0530h, 0008h, OFFSET SIS59x_List, 0, 0
    db 'SiS 530$             '

    dw SIS_ID, 0540h, 0008h, OFFSET SIS59x_List, 0, 0
    db 'SiS 540$             '

    dw SIS_ID, 0550h, 0008h, OFFSET SIS59x_List, 0, 0
    db 'SiS 550$             '

    dw SIS_ID, 5600h, 0008h, OFFSET SIS600_List, 1, 0
    db 'SiS 600$             '

    dw SIS_ID, 0620h, 0008h, OFFSET SIS600_List, 1, 0
    db 'SiS 620$             '

    dw SIS_ID, 5630h, 0008h, OFFSET SIS600_List, 1, 0
    db 'SiS 630$             '

    dw SIS_ID, 0630h, 0008h, OFFSET SIS600_List, 1, 0
    db 'SiS 630$             '

    dw SIS_ID, 0635h, 0000h, OFFSET SIS600_List, 1, 0
    db 'SiS 635$             '

    dw SIS_ID, 0640h, 0000h, OFFSET SIS600_List, 1, 0
    db 'SiS 640$             '

    dw SIS_ID, 0645h, 0000h, OFFSET SIS600_List, 1, 0
    db 'SiS 645$             '

    dw SIS_ID, 0648h, 0000h, OFFSET SIS600_List, 1, 0
    db 'SiS 648$             '

    dw SIS_ID, 0646h, 0000h, OFFSET SIS600_List, 1, 0
    db 'SiS 645DX$           '

    dw SIS_ID, 0650h, 0000h, OFFSET SIS600_List, 1, 0
    db 'SiS 650$             '

    dw SIS_ID, 0651h, 0000h, OFFSET SIS600_List, 1, 0
    db 'SiS 651$             '

    dw SIS_ID, 0655h, 0000h, OFFSET SIS600_List, 1, 0
    db 'SiS 655$             '

    dw SIS_ID, 0656h, 0000h, OFFSET SIS600_List, 1, 0
    db 'SiS 656$             '

    dw SIS_ID, 0660h, 0000h, OFFSET SIS600_List, 1, 0
    db 'SiS 660$             '

    dw SIS_ID, 0661h, 0000h, OFFSET SIS600_List, 1, 0
    db 'SiS 661$             '

    dw SIS_ID, 0662h, 0000h, OFFSET SIS600_List, 1, 0
    db 'SiS 662$             '

    dw SIS_ID, 0663h, 0000h, OFFSET SIS600_List, 1, 0
    db 'SiS 663$             '

    dw SIS_ID, 0671h, 0000h, OFFSET SIS600_List, 1, 0
    db 'SiS 671$             '

;---------------------------------- SiS K7 ------------------------------------
;    dw SIS_ID, 0730h, 0000h, OFFSET No_List, 1, UNSUPPORTED_NO_DATASHEET
;    db 'SiS 730$             '

    dw SIS_ID, 0735h, 0000h, OFFSET SIS600_List, 1, UNSUPPORTED_UNTESTED
    db 'SiS 735$             '

    dw SIS_ID, 0740h, 0000h, OFFSET SIS600_List, 1, UNSUPPORTED_UNTESTED
    db 'SiS 740$             '
 
    dw SIS_ID, 0741h, 0000h, OFFSET SIS600_List, 1, 0
    db 'SiS 741$             '
 
    dw SIS_ID, 0745h, 0000h, OFFSET SIS600_List, 1, UNSUPPORTED_UNTESTED
    db 'SiS 745$             '

    dw SIS_ID, 0750h, 0000h, OFFSET SIS600_List, 1, UNSUPPORTED_UNTESTED
    db 'SiS 750$             '


;---------------------------------------------
;------------------- ALI ---------------------
;---------------------------------------------

;----------------- ALI 486 -------------------
    dw ALI_ID, 1451h, 0000h, OFFSET ALI486_List, 0, UNSUPPORTED_UNTESTED
    db 'ALi M1451$           '

    dw ALI_ID, 1489h, 0000h, OFFSET ALI486_List, 0, UNSUPPORTED_UNTESTED
    db 'ALi M1489$           '

;--------------- ALI Socket 7 -----------------
    dw ALI_ID, 1541h, 0000h, OFFSET ALI5_List, 0, 0
    db 'ALi Aladdin V$       '

    dw ALI_ID, 1531h, 0000h, OFFSET ALI3_List, 0, 0
    db 'ALi Aladdin IV$      '

    dw ALI_ID, 1521h, 0000h, OFFSET ALI3_List, 0, 0
    db 'ALi Aladdin III$     '

    dw ALI_ID, 1511h, 0000h, OFFSET ALI2_List, 0, 0
    db 'ALi Aladdin II$      '

;------------------- ALI P2 --------------------
    dw ALI_ID, 1621h, 0000h, OFFSET ALIP2_List, 1, 0
    db 'ALi Aladdin Pro II$  '

    dw ALI_ID, 1631h, 0000h, OFFSET ALIP2_List, 1, 0
    db 'ALi Aladdin Pro III$ '

    dw ALI_ID, 1632h, 0000h, OFFSET ALIP2_List, 1, 0
    db 'ALi i1 CyberBlade$   '

    dw ALI_ID, 1641h, 0000h, OFFSET ALIP2_List, 1, 0
    db 'ALi Aladdin Pro IV$  '

    dw ALI_ID, 1651h, 0000h, OFFSET ALIK7_List, 1, 0
    db 'ALi Aladdin Pro V$   '

    dw ALI_ID, 1644h, 0000h, OFFSET ALIK7_List, 1, 0
    db 'ALi M1644$           '

; --------------- ALI K7 ---------------------
;    dw ALI_ID, 1647h, 0000h, OFFSET ALIK7_List, 1, UNSUPPORTED_NO_DATASHEET
;    db 'ALi ALiMAGiK 1$      '


;---------------------------------------------
;-------------- OPTi--------------------------
; --------------------------------------------
 dw OPTI_ID, 0C556h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'OPTi 82C556 Viper$   '

 dw OPTI_ID, 0C557h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'OPTi 82C557 Viper$   '

 dw OPTI_ID, 0C567h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'OPTi 82C750 Vendetta$'

 dw OPTI_ID, 0C701h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'OPTi 82C701 Firestar$'


;---------------------------------------------
;-------------- UMC --------------------------
; --------------------------------------------
 dw UMC_ID, 00001h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'UMC 8881$            '

 dw UMC_ID, 0E881h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'UMC 8881 Mobile$     '

 dw UMC_ID, 00891h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'UMC 8890$            '

 dw UMC_ID, 08891h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'UMC 8891$            '

 dw UMC_ID, 0E891h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'UMC 8891 Mobile$     '


;-------------------------------------
;-------------- Exotic ---------------
 dw 1279h, 0395h, 0000h, OFFSET Intel_Uni_List, 0, 0
 db 'Transmeta CPU$       '

 dw 3388h, 8011h, 8012h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'Hint VXPro II$       '

 dw 1004h, 0005h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'VLSI 82C591/2$       '

 dw 1004h, 0007h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'VLSI 82C594$         '

 dw 1004h, 0100h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'VLSI Mobile Chipset$ '

 dw 1004h, 0104h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'VLSI 82C535$         '

 dw 1014h, 0017h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'IBM Chipset$         '

 dw 1014h, 003Ah, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'IBM Chipset$         '

 dw 1014h, 0302h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'IBM Chipset$         '

 dw 1066h, 0001h, 0000h, OFFSET No_List, 0, 4
 db 'PicoPower 521$       '

 dw 1166h, 0005h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'ServerWorks Chipset$ '

 dw 1166h, 0006h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'ServerWorks Chipset$ '

 dw 1166h, 0007h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'ServerWorks Chipset$ '

 dw 1166h, 0008h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'ServerWorks Chipset$ '

 dw 1166h, 0009h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'ServerWorks Chipset$ '

 dw 1166h, 0010h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'ServerWorks Chipset$ '

 dw 1166h, 0011h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'ServerWorks Chipset$ '

 dw 1166h, 0012h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'ServerWorks Chipset$ '

 dw 1166h, 0013h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'ServerWorks Chipset$ '

 dw 1166h, 0014h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'ServerWorks Chipset$ '

 dw 1166h, 0015h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'ServerWorks Chipset$ '

 dw 1166h, 0016h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'ServerWorks Chipset$ '

 dw 1166h, 0017h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'ServerWorks Chipset$ '

 dw 1166h, 0018h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'ServerWorks Chipset$ '

 dw 0E11h, 0AE6Dh, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'Compaq NorthStar$    '

 dw 0E11h, 0AE6Ch, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'Compaq DRACO$        '

 dw 0E11h, 0AE2Ah, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'Compaq MPC$          '

 dw 0E11h, 4000h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'Compaq Triflex$      '

 dw 1179h, 0601h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'Toshiba Notebook$    '

 dw 1179h, 0618h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'Toshiba Notebook$    '

 dw 1078h, 0001h, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'Cyrix MediaGX$       '

 dw 0FFFFh, 0FFFFh, 0000h, OFFSET No_List, 0, UNSUPPORTED_NO_HOST_BRIDGE
 db 'No valid PCI chipset$'

 dw 17f3h, 6020h, 0, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
 db 'RDC R6020$           '

    dw 17f3h, 6022h, 0, OFFSET No_List, 0, UNSUPPORTED_NO_DATASHEET
    db 'RDC R6022$           '

    ; 440ZX moved to the end of the list to test the integrity of the list in Virtual PC
    ;dw INTEL_ID, 7192h, PIIX4_ID, OFFSET IntelTestList, 1, 0
    ;db 'Intel 440ZX w/o AGPx$'

    dw INTEL_ID, 7192h, PIIX4_ID, OFFSET PIIX_List, 1, 0
    db 'Intel 440ZX w/o AGP$ '

    dw INTEL_ID, 1237h, PIIX3_ID, OFFSET PIIX_List, 1, 0
    db 'Intel 440FX$         '

    dw INTEL_ID, 1237h, 0000h, OFFSET Intel_Uni_List, 1, 0
    db 'Intel 440FX virtual$ '

    dw 0000h                       ; Chipset list end marker

;------------------------------------- END ------------------------------------


;============================ CHIPSETS CONFIG DATA ============================

;----------------- Defines for Chipsets Data Configuration List ---------------
RWC_LO     equ 00F0Fh              ; Mask
RWC_HI     equ 0F0F0h              ; Value

;---------------------
; Bits Mask
;---------------------
BIT_0      equ 0101h
BIT_1      equ 0202h
BIT_2      equ 0404h
BIT_3      equ 0808h
BIT_4      equ 1010h
BIT_5      equ 2020h
BIT_6      equ 4040h
BIT_7      equ 8080h

BITS_1_0   equ 0303h
BITS_2_1   equ 0606h
BITS_3_2   equ 0C0Ch
BITS_5_4   equ 3030h
BITS_7_6   equ 0C0C0h

NOT_BIT_0  equ 0001h
NOT_BIT_1  equ 0002h
NOT_BIT_2  equ 0004h
NOT_BIT_3  equ 0008h
NOT_BIT_4  equ 0010h
NOT_BIT_5  equ 0020h
NOT_BIT_6  equ 0040h
NOT_BIT_7  equ 0080h
;------------------------------------------------------------------------------

No_List:
    dw 00000h


; Dummy List for K7 and K8
Empty_List:
    dw 0C000h, 0Ah, 0h, 0, 0
    dw 0C400h, 0Ah, 0h, 0, 0
    dw 0C800h, 0Ah, 0h, 0, 0
    dw 0CC00h, 0Ah, 0h, 0, 0
    dw 0D000h, 0Ah, 0h, 0, 0
    dw 0D400h, 0Ah, 0h, 0, 0
    dw 0D800h, 0Ah, 0h, 0, 0
    dw 0DC00h, 0Ah, 0h, 0, 0
    dw 0E000h, 0Ah, 0h, 0, 0
    dw 0E400h, 0Ah, 0h, 0, 0
    dw 0E800h, 0Ah, 0h, 0, 0
    dw 0EC00h, 0Ah, 0h, 0, 0
    dw 0F000h, 0Ah, 0h, 0, 0 
    dw 0F400h, 0Ah, 0h, 0, 0 
    dw 0F800h, 0Ah, 0h, 0, 0 
    dw 0FC00h, 0Ah, 0h, 0, 0
    dw 00000h                      ; End of list marker


;------------------------ START OF INTEL CHIPSETS LIST ------------------------

; Segments and Register Values for Saturn, Mercury, Neptun
SIO_List:
    dw 0C000h, 12h, 5Ah, RWC_LO, 154h, 0303h,  149h, BIT_0, 0
    dw 0C400h, 12h, 5Ah, RWC_HI, 154h, 0C0Ch,  149h, BIT_1, 0
    dw 0C800h, 12h, 5Bh, RWC_LO, 154h, 3030h,  149h, BIT_2, 0
    dw 0CC00h, 12h, 5Bh, RWC_HI, 154h, 0C0C0h, 149h, BIT_3, 0
    dw 0D000h, 12h, 5Ch, RWC_LO, 155h, 0303h,  149h, BIT_4, 0
    dw 0D400h, 12h, 5Ch, RWC_HI, 155h, 0C0Ch,  149h, BIT_5, 0
    dw 0D800h, 12h, 5Dh, RWC_LO, 155h, 3030h,  149h, BIT_6, 0
    dw 0DC00h, 12h, 5Dh, RWC_HI, 155h, 0C0C0h, 149h, BIT_7, 0
    dw 0E000h, 16h, 5Eh, RWC_LO, 156h, 0303h,  148h, BIT_3, 14Eh, 0040h, 0
    dw 0E400h, 16h, 5Eh, RWC_HI, 156h, 0C0Ch,  148h, BIT_3, 14Eh, 0040h, 0
    dw 0E800h, 16h, 5Fh, RWC_LO, 156h, 3030h,  148h, BIT_3, 14Eh, 0040h, 0
    dw 0EC00h, 16h, 5Fh, RWC_HI, 156h, 0C0C0h, 148h, BIT_3, 14Eh, 0040h, 0
    dw 0F000h, 0Ah, 59h, RWC_HI, 0
    dw 0F400h, 0Ah, 59h, RWC_HI, 0
    dw 0F800h, 0Ah, 59h, RWC_HI, 0
    dw 0FC00h, 0Ah, 59h, RWC_HI, 0
    dw 00000h                      ; End of list marker


; Segments and Register Values for Intel 430 and 440 + PIIX
PIIX_List:
    dw 0C000h, 0Ah, 5Ah, RWC_LO, 0
    dw 0C400h, 0Ah, 5Ah, RWC_HI, 0
    dw 0C800h, 0Ah, 5Bh, RWC_LO, 0
    dw 0CC00h, 0Ah, 5Bh, RWC_HI, 0
    dw 0D000h, 0Ah, 5Ch, RWC_LO, 0
    dw 0D400h, 0Ah, 5Ch, RWC_HI, 0
    dw 0D800h, 0Ah, 5Dh, RWC_LO, 0
    dw 0DC00h, 0Ah, 5Dh, RWC_HI, 0
    dw 0E000h, 12h, 5Eh, RWC_LO, 169h, BIT_3, 14Eh, 0040h, 0
    dw 0E400h, 12h, 5Eh, RWC_HI, 169h, BIT_3, 14Eh, 0040h, 0
    dw 0E800h, 12h, 5Fh, RWC_LO, 169h, BIT_3, 14Eh, 0040h, 0
    dw 0EC00h, 12h, 5Fh, RWC_HI, 169h, BIT_3, 14Eh, 0040h, 0
    dw 0F000h, 0Ah, 59h, RWC_HI, 0
    dw 0F400h, 0Ah, 59h, RWC_HI, 0
    dw 0F800h, 0Ah, 59h, RWC_HI, 0
    dw 0FC00h, 0Ah, 59h, RWC_HI, 0
    dw 00000h                      ; End of list marker


; Segments and Register Values for all 'alten' Intel-PCI-Chipsets, None DMA
Intel_Uni_List:
    dw 0C000h, 0Ah, 5Ah, RWC_LO, 0
    dw 0C400h, 0Ah, 5Ah, RWC_HI, 0
    dw 0C800h, 0Ah, 5Bh, RWC_LO, 0
    dw 0CC00h, 0Ah, 5Bh, RWC_HI, 0
    dw 0D000h, 0Ah, 5Ch, RWC_LO, 0
    dw 0D400h, 0Ah, 5Ch, RWC_HI, 0
    dw 0D800h, 0Ah, 5Dh, RWC_LO, 0
    dw 0DC00h, 0Ah, 5Dh, RWC_HI, 0
    dw 0E000h, 0Ah, 5Eh, RWC_LO, 0
    dw 0E400h, 0Ah, 5Eh, RWC_HI, 0
    dw 0E800h, 0Ah, 5Fh, RWC_LO, 0
    dw 0EC00h, 0Ah, 5Fh, RWC_HI, 0
    dw 0F000h, 0Ah, 59h, RWC_HI, 0
    dw 0F400h, 0Ah, 59h, RWC_HI, 0
    dw 0F800h, 0Ah, 59h, RWC_HI, 0
    dw 0FC00h, 0Ah, 59h, RWC_HI, 0
    dw 00000h                      ; End of list marker


; Segments and Register Values for i845, i875, i9xx, X3x Chipsets, Intel
; Core 1st Generation
Intel845_List:
    dw 0C000h, 0Ah, 91h, BITS_1_0, 0
    dw 0C400h, 0Ah, 91h, BITS_5_4, 0
    dw 0C800h, 0Ah, 92h, BITS_1_0, 0
    dw 0CC00h, 0Ah, 92h, BITS_5_4, 0
    dw 0D000h, 0Ah, 93h, BITS_1_0, 0
    dw 0D400h, 0Ah, 93h, BITS_5_4, 0
    dw 0D800h, 0Ah, 94h, BITS_1_0, 0
    dw 0DC00h, 0Ah, 94h, BITS_5_4, 0
    dw 0E000h, 0Ah, 95h, BITS_1_0, 0
    dw 0E400h, 0Ah, 95h, BITS_5_4, 0
    dw 0E800h, 0Ah, 96h, BITS_1_0, 0
    dw 0EC00h, 0Ah, 96h, BITS_5_4, 0
    dw 0F000h, 0Ah, 90h, BITS_5_4, 0 
    dw 0F400h, 0Ah, 90h, BITS_5_4, 0 
    dw 0F800h, 0Ah, 90h, BITS_5_4, 0 
    dw 0FC00h, 0Ah, 90h, BITS_5_4, 0
    dw 00000h                      ; End of list marker


; Segments and Register Values for Intel Core i3, i5, i7 - xxxx (2nd, 3rd,
; 4th, 8th generation)
IntelCore2ndGen_List:
    dw 0C000h, 0Ah, 81h, BITS_1_0, 0
    dw 0C400h, 0Ah, 81h, BITS_5_4, 0
    dw 0C800h, 0Ah, 82h, BITS_1_0, 0
    dw 0CC00h, 0Ah, 82h, BITS_5_4, 0
    dw 0D000h, 0Ah, 83h, BITS_1_0, 0
    dw 0D400h, 0Ah, 83h, BITS_5_4, 0
    dw 0D800h, 0Ah, 84h, BITS_1_0, 0
    dw 0DC00h, 0Ah, 84h, BITS_5_4, 0
    dw 0E000h, 0Ah, 85h, BITS_1_0, 0
    dw 0E400h, 0Ah, 85h, BITS_5_4, 0
    dw 0E800h, 0Ah, 86h, BITS_1_0, 0
    dw 0EC00h, 0Ah, 86h, BITS_5_4, 0
    dw 0F000h, 0Ah, 80h, BITS_5_4, 0 
    dw 0F400h, 0Ah, 80h, BITS_5_4, 0 
    dw 0F800h, 0Ah, 80h, BITS_5_4, 0 
    dw 0FC00h, 0Ah, 80h, BITS_5_4, 0
    dw 00000h                      ; End of list marker


; Segments and Register values for Intel Core i3, i5, i7, i9
; (7th..12th generation, with Lock bit at 80:0 cleared first)
IntelCore7thGen_List:
    dw 0C000h, 0Eh, 80h, NOT_BIT_0, 81h, BITS_1_0, 0
    dw 0C400h, 0Eh, 80h, NOT_BIT_0, 81h, BITS_5_4, 0
    dw 0C800h, 0Eh, 80h, NOT_BIT_0, 82h, BITS_1_0, 0
    dw 0CC00h, 0Eh, 80h, NOT_BIT_0, 82h, BITS_5_4, 0
    dw 0D000h, 0Eh, 80h, NOT_BIT_0, 83h, BITS_1_0, 0
    dw 0D400h, 0Eh, 80h, NOT_BIT_0, 83h, BITS_5_4, 0
    dw 0D800h, 0Eh, 80h, NOT_BIT_0, 84h, BITS_1_0, 0
    dw 0DC00h, 0Eh, 80h, NOT_BIT_0, 84h, BITS_5_4, 0
    dw 0E000h, 0Eh, 80h, NOT_BIT_0, 85h, BITS_1_0, 0
    dw 0E400h, 0Eh, 80h, NOT_BIT_0, 85h, BITS_5_4, 0
    dw 0E800h, 0Eh, 80h, NOT_BIT_0, 86h, BITS_1_0, 0
    dw 0EC00h, 0Eh, 80h, NOT_BIT_0, 86h, BITS_5_4, 0
    dw 0F000h, 0Eh, 80h, NOT_BIT_0, 80h, BITS_5_4, 0 
    dw 0F400h, 0Eh, 80h, NOT_BIT_0, 80h, BITS_5_4, 0 
    dw 0F800h, 0Eh, 80h, NOT_BIT_0, 80h, BITS_5_4, 0 
    dw 0FC00h, 0Eh, 80h, NOT_BIT_0, 80h, BITS_5_4, 0
    dw 00000h                      ; End of list marker


; Segments and Register Values for Intel Core i3, i5, i7 - xxxx (2011 generation)
IntelCore2011_List:
    dw 0C000h, 0Ah, 41h, BITS_1_0, 0
    dw 0C400h, 0Ah, 41h, BITS_5_4, 0
    dw 0C800h, 0Ah, 42h, BITS_1_0, 0
    dw 0CC00h, 0Ah, 42h, BITS_5_4, 0
    dw 0D000h, 0Ah, 43h, BITS_1_0, 0
    dw 0D400h, 0Ah, 43h, BITS_5_4, 0
    dw 0D800h, 0Ah, 44h, BITS_1_0, 0
    dw 0DC00h, 0Ah, 44h, BITS_5_4, 0
    dw 0E000h, 0Ah, 45h, BITS_1_0, 0
    dw 0E400h, 0Ah, 45h, BITS_5_4, 0
    dw 0E800h, 0Ah, 46h, BITS_1_0, 0
    dw 0EC00h, 0Ah, 46h, BITS_5_4, 0
    dw 0F000h, 0Ah, 40h, BITS_5_4, 0 
    dw 0F400h, 0Ah, 40h, BITS_5_4, 0 
    dw 0F800h, 0Ah, 40h, BITS_5_4, 0 
    dw 0FC00h, 0Ah, 40h, BITS_5_4, 0
    dw 00000h                      ; End of list marker


; Segments and Register Values for Intel-810, None DMA
Intel810_List:
    dw 0C000h, 0Ah, 51h, BITS_1_0, 0
    dw 0C400h, 0Ah, 51h, BITS_1_0, 0
    dw 0C800h, 0Ah, 51h, BITS_1_0, 0
    dw 0CC00h, 0Ah, 51h, BITS_1_0, 0
    dw 0D000h, 0Ah, 51h, BITS_3_2, 0
    dw 0D400h, 0Ah, 51h, BITS_3_2, 0
    dw 0D800h, 0Ah, 51h, BITS_3_2, 0
    dw 0DC00h, 0Ah, 51h, BITS_3_2, 0
    dw 0E000h, 0Ah, 51h, BITS_5_4, 0
    dw 0E400h, 0Ah, 51h, BITS_5_4, 0
    dw 0E800h, 0Ah, 51h, BITS_5_4, 0
    dw 0EC00h, 0Ah, 51h, BITS_5_4, 0
    dw 0F000h, 0Ah, 51h, BITS_7_6, 0 
    dw 0F400h, 0Ah, 51h, BITS_7_6, 0 
    dw 0F800h, 0Ah, 51h, BITS_7_6, 0 
    dw 0FC00h, 0Ah, 51h, BITS_7_6, 0
    dw 00000h                      ; End of list marker

;    dw 0C000h, 0Ah, 41h, BITS_1_0, 0
;    dw 0C400h, 0Ah, 41h, BITS_5_4, 0
;    dw 0C800h, 0Ah, 42h, BITS_1_0, 0
;    dw 0CC00h, 0Ah, 42h, BITS_5_4, 0
;    dw 0D000h, 0Ah, 43h, BITS_1_0, 0
;    dw 0D400h, 0Ah, 43h, BITS_5_4, 0
;    dw 0D800h, 0Ah, 44h, BITS_1_0, 0
;    dw 0DC00h, 0Ah, 44h, BITS_5_4, 0
;    dw 0E000h, 0Ah, 45h, BITS_1_0, 0
;    dw 0E400h, 0Ah, 45h, BITS_5_4, 0
;    dw 0E800h, 0Ah, 46h, BITS_1_0, 0
;    dw 0EC00h, 0Ah, 46h, BITS_5_4, 0
;    dw 0F000h, 0Ah, 41h, BITS_5_4, 0 
;    dw 0F400h, 0Ah, 41h, BITS_5_4, 0 
;    dw 0F800h, 0Ah, 41h, BITS_5_4, 0 
;    dw 0FC00h, 0Ah, 41h, BITS_5_4, 0
;    dw 00000h


Intel_Atom_List:  ; Write access globally only by setting Bit0 at D8 to 0
    dw 0C000h, 0Ah, 0D8h, NOT_BIT_0, 0
    dw 0C400h, 0Ah, 0D8h, NOT_BIT_0, 0
    dw 0C800h, 0Ah, 0D8h, NOT_BIT_0, 0
    dw 0CC00h, 0Ah, 0D8h, NOT_BIT_0, 0
    dw 0D000h, 0Ah, 0D8h, NOT_BIT_0, 0
    dw 0D400h, 0Ah, 0D8h, NOT_BIT_0, 0
    dw 0D800h, 0Ah, 0D8h, NOT_BIT_0, 0
    dw 0DC00h, 0Ah, 0D8h, NOT_BIT_0, 0
    dw 0E000h, 0Ah, 0D8h, NOT_BIT_0, 0
    dw 0E400h, 0Ah, 0D8h, NOT_BIT_0, 0
    dw 0E800h, 0Ah, 0D8h, NOT_BIT_0, 0
    dw 0EC00h, 0Ah, 0D8h, NOT_BIT_0, 0
    dw 0F000h, 0Ah, 0D8h, NOT_BIT_0, 0 
    dw 0F400h, 0Ah, 0D8h, NOT_BIT_0, 0 
    dw 0F800h, 0Ah, 0D8h, NOT_BIT_0, 0 
    dw 0FC00h, 0Ah, 0D8h, NOT_BIT_0, 0
    dw 00000h                      ; End of list marker

;------------------------- END OF INTEL CHIPSETS LIST -------------------------


;---------- VIA PAM Constants ----------
VIA_RW0  equ  0303h
VIA_RW1  equ  0C0Ch
VIA_RW2  equ  3030h
VIA_RW3  equ 0C0C0h
;---------------------------------------

; Segments and Register Values for All VIA-Chipsets
VIA_List:
    dw 0C000h, 18, 61h, VIA_RW0, 14Eh, BIT_0, 52h, 0080h, 0
    dw 0C400h, 18, 61h, VIA_RW1, 14Eh, BIT_1, 52h, 0080h, 0
    dw 0C800h, 14, 61h, VIA_RW2, 14Eh, BIT_2, 0
    dw 0CC00h, 14, 61h, VIA_RW3, 14Eh, BIT_3, 0
    dw 0D000h, 18, 62h, VIA_RW0, 14Eh, BIT_4, 52h, 0040h, 0
    dw 0D400h, 18, 62h, VIA_RW1, 14Eh, BIT_5, 52h, 0040h, 0
    dw 0D800h, 18, 62h, VIA_RW2, 14Eh, BIT_6, 52h, 0040h, 0
    dw 0DC00h, 18, 62h, VIA_RW3, 14Eh, BIT_7, 52h, 0040h, 0
    dw 0E000h, 18, 63h, VIA_RW3, 14Fh, BIT_3, 52h, 0020h, 0
    dw 0E400h, 18, 63h, VIA_RW3, 14Fh, BIT_3, 52h, 0020h, 0
    dw 0E800h, 18, 63h, VIA_RW3, 14Fh, BIT_3, 52h, 0020h, 0
    dw 0EC00h, 18, 63h, VIA_RW3, 14Fh, BIT_3, 52h, 0020h, 0
    dw 0F000h, 14, 63h, VIA_RW2, 52h, 0010h, 0
    dw 0F400h, 14, 63h, VIA_RW2, 52h, 0010h, 0
    dw 0F800h, 14, 63h, VIA_RW2, 52h, 0010h, 0
    dw 0FC00h, 14, 63h, VIA_RW2, 52h, 0010h, 0
    dw 00000h                      ; End of list marker


; Segments and Register Values for All VIA-Chipsets
VIA_Uni_List:
    dw 0C000h, 10, 61h, VIA_RW0, 0
    dw 0C400h, 10, 61h, VIA_RW1, 0
    dw 0C800h, 10, 61h, VIA_RW2, 0
    dw 0CC00h, 10, 61h, VIA_RW3, 0
    dw 0D000h, 10, 62h, VIA_RW0, 0
    dw 0D400h, 10, 62h, VIA_RW1, 0
    dw 0D800h, 10, 62h, VIA_RW2, 0
    dw 0DC00h, 10, 62h, VIA_RW3, 0
    dw 0E000h, 10, 63h, VIA_RW3, 0
    dw 0E400h, 10, 63h, VIA_RW3, 0
    dw 0E800h, 10, 63h, VIA_RW3, 0
    dw 0EC00h, 10, 63h, VIA_RW3, 0
    dw 0F000h, 10, 63h, VIA_RW2, 0
    dw 0F400h, 10, 63h, VIA_RW2, 0
    dw 0F800h, 10, 63h, VIA_RW2, 0
    dw 0FC00h, 10, 63h, VIA_RW2, 0
    dw 00000h                      ; End of list marker


; Segments and Register Values for VIA CX700 + VX8xx + VX900 Chipsets (function 7+3)
;VIA_CX700_List:
;    dw 0C000h, 14, 61h, VIA_RW0, 180h, VIA_RW0, 0
;    dw 0C400h, 14, 61h, VIA_RW1, 180h, VIA_RW1, 0
;    dw 0C800h, 14, 61h, VIA_RW2, 180h, VIA_RW2, 0
;    dw 0CC00h, 14, 61h, VIA_RW3, 180h, VIA_RW3, 0
;    dw 0D000h, 14, 62h, VIA_RW0, 181h, VIA_RW0, 0
;    dw 0D400h, 14, 62h, VIA_RW1, 181h, VIA_RW1, 0
;    dw 0D800h, 14, 62h, VIA_RW2, 181h, VIA_RW2, 0
;    dw 0DC00h, 14, 62h, VIA_RW3, 181h, VIA_RW3, 0
;    dw 0E000h, 14, 63h, VIA_RW3, 182h, VIA_RW0, 0
;    dw 0E400h, 14, 63h, VIA_RW3, 182h, VIA_RW1, 0
;    dw 0E800h, 14, 63h, VIA_RW3, 182h, VIA_RW2, 0
;    dw 0EC00h, 14, 63h, VIA_RW3, 182h, VIA_RW3, 0
;    dw 0F000h, 14, 63h, VIA_RW2, 183h, VIA_RW2, 0
;    dw 0F400h, 14, 63h, VIA_RW2, 183h, VIA_RW2, 0
;    dw 0F800h, 14, 63h, VIA_RW2, 183h, VIA_RW2, 0
;    dw 0FC00h, 14, 63h, VIA_RW2, 183h, VIA_RW2, 0
;    dw 00000h                      ; End of list marker

; Segments and Register Values for VIA CX700 + VX8xx + VX900 Chipsets (function 7+3)
VIA_CX700_List:
    dw 0C000h, 10, 80h, VIA_RW0, 0
    dw 0C400h, 10, 80h, VIA_RW1, 0
    dw 0C800h, 10, 80h, VIA_RW2, 0
    dw 0CC00h, 10, 80h, VIA_RW3, 0
    dw 0D000h, 10, 81h, VIA_RW0, 0
    dw 0D400h, 10, 81h, VIA_RW1, 0
    dw 0D800h, 10, 81h, VIA_RW2, 0
    dw 0DC00h, 10, 81h, VIA_RW3, 0
    dw 0E000h, 10, 82h, VIA_RW0, 0
    dw 0E400h, 10, 82h, VIA_RW1, 0
    dw 0E800h, 10, 82h, VIA_RW2, 0
    dw 0EC00h, 10, 82h, VIA_RW3, 0
    dw 0F000h, 10, 83h, VIA_RW2, 0
    dw 0F400h, 10, 83h, VIA_RW2, 0
    dw 0F800h, 10, 83h, VIA_RW2, 0
    dw 0FC00h, 10, 83h, VIA_RW2, 0
    dw 00000h                      ; End of list marker

;-------------------------- END OF VIA CHIPSETS LIST --------------------------


;------------------------- START OF SIS CHIPSETS LIST -------------------------

; Segments and Register Values for SIS 6x0-PCI-Chipsets
SIS600xx_List:
    dw 0C000h, 18, 70h, BIT_0, 72h, BIT_0, 149h, BIT_0, 0
    dw 0C400h, 18, 70h, BIT_1, 72h, BIT_1, 149h, BIT_1, 0
    dw 0C800h, 18, 70h, BIT_2, 72h, BIT_2, 149h, BIT_2, 0
    dw 0CC00h, 18, 70h, BIT_3, 72h, BIT_3, 149h, BIT_3, 0
    dw 0D000h, 18, 70h, BIT_4, 72h, BIT_4, 149h, BIT_4, 0
    dw 0D400h, 18, 70h, BIT_5, 72h, BIT_5, 149h, BIT_5, 0
    dw 0D800h, 18, 70h, BIT_6, 72h, BIT_6, 149h, BIT_6, 0
    dw 0DC00h, 18, 70h, BIT_7, 72h, BIT_7, 149h, BIT_7, 0
    dw 0E000h, 18, 71h, BIT_0, 73h, BIT_0, 148h, BIT_3, 0
    dw 0E400h, 18, 71h, BIT_1, 73h, BIT_1, 148h, BIT_3, 0
    dw 0E800h, 18, 71h, BIT_2, 73h, BIT_2, 148h, BIT_3, 0
    dw 0EC00h, 18, 71h, BIT_3, 73h, BIT_3, 148h, BIT_3, 0
    dw 0F000h, 14, 71h, BIT_4, 73h, BIT_4, 0
    dw 0F400h, 14, 71h, BIT_4, 73h, BIT_4, 0
    dw 0F800h, 14, 71h, BIT_4, 73h, BIT_4, 0
    dw 0FC00h, 14, 71h, BIT_4, 73h, BIT_4, 0
    dw 00000h                      ; End of list marker


; Segments and Register Values for SIS 6x0-PCI-Chipsets
SIS600_List:
    dw 0C000h, 14, 70h, BIT_0, 72h, BIT_0, 0
    dw 0C400h, 14, 70h, BIT_1, 72h, BIT_1, 0
    dw 0C800h, 14, 70h, BIT_2, 72h, BIT_2, 0
    dw 0CC00h, 14, 70h, BIT_3, 72h, BIT_3, 0
    dw 0D000h, 14, 70h, BIT_4, 72h, BIT_4, 0
    dw 0D400h, 14, 70h, BIT_5, 72h, BIT_5, 0
    dw 0D800h, 14, 70h, BIT_6, 72h, BIT_6, 0
    dw 0DC00h, 14, 70h, BIT_7, 72h, BIT_7, 0
    dw 0E000h, 14, 71h, BIT_0, 73h, BIT_0, 0
    dw 0E400h, 14, 71h, BIT_1, 73h, BIT_1, 0
    dw 0E800h, 14, 71h, BIT_2, 73h, BIT_2, 0
    dw 0EC00h, 14, 71h, BIT_3, 73h, BIT_3, 0
    dw 0F000h, 14, 71h, BIT_4, 73h, BIT_4, 0
    dw 0F400h, 14, 71h, BIT_4, 73h, BIT_4, 0
    dw 0F800h, 14, 71h, BIT_4, 73h, BIT_4, 0
    dw 0FC00h, 14, 71h, BIT_4, 73h, BIT_4, 0
    dw 00000h                      ; End of list marker


;--------------------------------------
SIS_RWC_LO  equ 00E0Eh
SIS_RWC_HI  equ 0E0E0h
SIS_RW_LO   equ 00A0Ah
SIS_RW_HI   equ 0A0A0h
;--------------------------------------

; Segments and Register Values for SIS 5xxx-PCI-Chipsets
SIS59x_List:
    dw 0C000h, 0Eh, 70h, SIS_RW_HI, 149h, BIT_0, 0
    dw 0C400h, 0Eh, 70h, SIS_RW_LO, 149h, BIT_1, 0
    dw 0C800h, 0Eh, 71h, SIS_RW_HI, 149h, BIT_2, 0
    dw 0CC00h, 0Eh, 71h, SIS_RW_LO, 149h, BIT_3, 0
    dw 0D000h, 0Eh, 72h, SIS_RW_HI, 149h, BIT_4, 0
    dw 0D400h, 0Eh, 72h, SIS_RW_LO, 149h, BIT_5, 0
    dw 0D800h, 0Eh, 73h, SIS_RW_HI, 149h, BIT_6, 0
    dw 0DC00h, 0Eh, 73h, SIS_RW_LO, 149h, BIT_7, 0
    dw 0E000h, 0Eh, 74h, SIS_RW_HI, 148h, BIT_3, 0
    dw 0E400h, 0Eh, 74h, SIS_RW_LO, 148h, BIT_3, 0
    dw 0E800h, 0Eh, 75h, SIS_RW_HI, 148h, BIT_3, 0
    dw 0EC00h, 0Eh, 75h, SIS_RW_LO, 148h, BIT_3, 0
    dw 0F000h, 0Ah, 76h, SIS_RW_HI, 0
    dw 0F400h, 0Ah, 76h, SIS_RW_HI, 0
    dw 0F800h, 0Ah, 76h, SIS_RW_HI, 0
    dw 0FC00h, 0Ah, 76h, SIS_RW_HI, 0
    dw 00000h                      ; End of list marker


; Segments and Register Values for SIS 5xxx-PCI-Chipsets
SIS597_List:
    dw 0C000h, 0Eh, 70h, SIS_RW_HI, 149h, BIT_0, 0
    dw 0C400h, 0Eh, 70h, SIS_RW_LO, 149h, BIT_1, 0
    dw 0C800h, 0Eh, 71h, SIS_RW_HI, 149h, BIT_2, 0
    dw 0CC00h, 0Eh, 71h, SIS_RW_LO, 149h, BIT_3, 0
    dw 0D000h, 0Eh, 72h, SIS_RW_HI, 149h, BIT_4, 0
    dw 0D400h, 0Eh, 72h, SIS_RW_LO, 149h, BIT_5, 0
    dw 0D800h, 0Eh, 73h, SIS_RW_HI, 149h, BIT_6, 0
    dw 0DC00h, 0Eh, 73h, SIS_RW_LO, 149h, BIT_7, 0
    dw 0E000h, 0Eh, 74h, SIS_RW_HI, 148h, BIT_3, 0
    dw 0E400h, 0Eh, 74h, SIS_RW_LO, 148h, BIT_3, 0
    dw 0E800h, 0Eh, 75h, SIS_RW_HI, 148h, BIT_3, 0
    dw 0EC00h, 0Eh, 75h, SIS_RW_LO, 148h, BIT_3, 0
    dw 0F000h, 0Ah, 76h, SIS_RW_HI, 0
    dw 0F400h, 0Ah, 76h, SIS_RW_HI, 0
    dw 0F800h, 0Ah, 76h, SIS_RW_HI, 0
    dw 0FC00h, 0Ah, 76h, SIS_RW_HI, 0
    dw 00000h                      ; End of list marker


; Segments and Register Values for SIS 5571-PCI-Chipsets
SIS571_List:
    dw 0C000h, 0Eh, 70h, SIS_RW_HI, 149h, BIT_0, 0
    dw 0C400h, 0Eh, 70h, SIS_RW_LO, 149h, BIT_1, 0
    dw 0C800h, 0Eh, 71h, SIS_RW_HI, 149h, BIT_2, 0
    dw 0CC00h, 0Eh, 71h, SIS_RW_LO, 149h, BIT_3, 0
    dw 0D000h, 0Eh, 72h, SIS_RW_HI, 149h, BIT_4, 0
    dw 0D400h, 0Eh, 72h, SIS_RW_LO, 149h, BIT_5, 0
    dw 0D800h, 0Eh, 73h, SIS_RW_HI, 149h, BIT_6, 0
    dw 0DC00h, 0Eh, 73h, SIS_RW_LO, 149h, BIT_7, 0
    dw 0E000h, 0Eh, 74h, SIS_RW_HI, 148h, BIT_3, 0
    dw 0E400h, 0Eh, 74h, SIS_RW_LO, 148h, BIT_3, 0
    dw 0E800h, 0Eh, 75h, SIS_RW_HI, 148h, BIT_3, 0
    dw 0EC00h, 0Eh, 75h, SIS_RW_LO, 148h, BIT_3, 0
    dw 0F000h, 0Ah, 76h, SIS_RW_HI, 0
    dw 0F400h, 0Ah, 76h, SIS_RW_HI, 0
    dw 0F800h, 0Ah, 76h, SIS_RW_HI, 0
    dw 0FC00h, 0Ah, 76h, SIS_RW_HI, 0
    dw 00000h                      ; End of list marker


; Segments and Register Values for SIS 5511-PCI-Chipsets
SIS511_List:
    dw 0C000h, 0Eh, 80h, SIS_RW_HI, 149h, BIT_0, 0
    dw 0C400h, 0Eh, 80h, SIS_RW_LO, 149h, BIT_1, 0
    dw 0C800h, 0Eh, 81h, SIS_RW_HI, 149h, BIT_2, 0
    dw 0CC00h, 0Eh, 81h, SIS_RW_LO, 149h, BIT_3, 0
    dw 0D000h, 0Eh, 82h, SIS_RW_HI, 149h, BIT_4, 0
    dw 0D400h, 0Eh, 82h, SIS_RW_LO, 149h, BIT_5, 0
    dw 0D800h, 0Eh, 83h, SIS_RW_HI, 149h, BIT_6, 0
    dw 0DC00h, 0Eh, 83h, SIS_RW_LO, 149h, BIT_7, 0
    dw 0E000h, 0Eh, 84h, SIS_RW_HI, 148h, BIT_3, 0
    dw 0E400h, 0Eh, 84h, SIS_RW_LO, 148h, BIT_3, 0
    dw 0E800h, 0Eh, 85h, SIS_RW_HI, 148h, BIT_3, 0
    dw 0EC00h, 0Eh, 85h, SIS_RW_LO, 148h, BIT_3, 0
    dw 0F000h, 0Ah, 86h, SIS_RW_HI, 0
    dw 0F400h, 0Ah, 86h, SIS_RW_HI, 0
    dw 0F800h, 0Ah, 86h, SIS_RW_HI, 0
    dw 0FC00h, 0Ah, 86h, SIS_RW_HI, 0
    dw 00000h                      ; End of list marker


; Segments and Register Values for SIS 496 Chipsets
SIS496_List:
    dw 0C000h, 18, 44h, BIT_0, 45h, 0706h, 46h, BIT_0, 0
    dw 0C400h, 18, 44h, BIT_0, 45h, 0706h, 46h, BIT_0, 0
    dw 0C800h, 18, 44h, BIT_1, 45h, 0706h, 46h, BIT_1, 0
    dw 0CC00h, 18, 44h, BIT_1, 45h, 0706h, 46h, BIT_1, 0
    dw 0D000h, 18, 44h, BIT_2, 45h, 0706h, 46h, BIT_2, 0
    dw 0D400h, 18, 44h, BIT_2, 45h, 0706h, 46h, BIT_2, 0
    dw 0D800h, 18, 44h, BIT_3, 45h, 0706h, 46h, BIT_3, 0
    dw 0DC00h, 18, 44h, BIT_3, 45h, 0706h, 46h, BIT_3, 0
    dw 0E000h, 18, 44h, BIT_4, 45h, 0706h, 46h, BIT_4, 0
    dw 0E400h, 18, 44h, BIT_4, 45h, 0706h, 46h, BIT_4, 0
    dw 0E800h, 18, 44h, BIT_5, 45h, 0706h, 46h, BIT_5, 0
    dw 0EC00h, 18, 44h, BIT_5, 45h, 0706h, 46h, BIT_5, 0
    dw 0F000h, 18, 44h, BIT_6, 45h, 0706h, 46h, BIT_6, 0
    dw 0F400h, 18, 44h, BIT_6, 45h, 0706h, 46h, BIT_6, 0
    dw 0F800h, 18, 44h, BIT_7, 45h, 0706h, 46h, BIT_7, 0
    dw 0FC00h, 18, 44h, BIT_7, 45h, 0706h, 46h, BIT_7, 0
    dw 00000h                      ; End of list marker


; Segments and Register Values for SIS 501 Chipsets
SIS501_List:
    dw 0C000h, 14, 56h, 8888h, 53h, 2000h, 0
    dw 0C400h, 14, 56h, 4444h, 53h, 2000h, 0
    dw 0C800h, 14, 56h, 2222h, 53h, 2000h, 0
    dw 0CC00h, 14, 56h, 1111h, 53h, 2000h, 0
    dw 0D000h, 14, 55h, 8888h, 53h, 2000h, 0
    dw 0D400h, 14, 55h, 4444h, 53h, 2000h, 0
    dw 0D800h, 14, 55h, 2222h, 53h, 2000h, 0
    dw 0DC00h, 14, 55h, 1111h, 53h, 2000h, 0
    dw 0E000h, 14, 54h, 8888h, 53h, 2000h, 0
    dw 0E400h, 14, 54h, 4444h, 53h, 2000h, 0
    dw 0E800h, 14, 54h, 2222h, 53h, 2000h, 0
    dw 0EC00h, 14, 54h, 1111h, 53h, 2000h, 0
    dw 0F000h, 10, 53h, 6040h, 0
    dw 0F400h, 10, 53h, 6040h, 0
    dw 0F800h, 10, 53h, 6040h, 0
    dw 0FC00h, 10, 53h, 6040h, 0
    dw 00000h                      ; End of list marker

;-------------------------- END OF SIS CHIPSETS LIST --------------------------


;------------------------- START OF ALI CHIPSETS LIST -------------------------

; Segments and Register Values for ALI V
ALI5_List:
    dw 0C000h, 18, 56h, BIT_0, 58h, BIT_0, 5Ah, NOT_BIT_0, 0
    dw 0C400h, 18, 56h, BIT_1, 58h, BIT_1, 5Ah, NOT_BIT_1, 0
    dw 0C800h, 18, 56h, BIT_2, 58h, BIT_2, 5Ah, NOT_BIT_2, 0
    dw 0CC00h, 18, 56h, BIT_3, 58h, BIT_3, 5Ah, NOT_BIT_3, 0
    dw 0D000h, 18, 56h, BIT_4, 58h, BIT_4, 5Ah, NOT_BIT_4, 0
    dw 0D400h, 18, 56h, BIT_5, 58h, BIT_5, 5Ah, NOT_BIT_5, 0
    dw 0D800h, 18, 56h, BIT_6, 58h, BIT_6, 5Ah, NOT_BIT_6, 0
    dw 0DC00h, 18, 56h, BIT_7, 58h, BIT_7, 5Ah, NOT_BIT_7, 0
    dw 0E000h, 18, 57h, BIT_0, 59h, BIT_0, 5Bh, NOT_BIT_0, 0
    dw 0E400h, 18, 57h, BIT_1, 59h, BIT_1, 5Bh, NOT_BIT_1, 0
    dw 0E800h, 18, 57h, BIT_2, 59h, BIT_2, 5Bh, NOT_BIT_2, 0
    dw 0EC00h, 18, 57h, BIT_3, 59h, BIT_3, 5Bh, NOT_BIT_3, 0
    dw 00000h                      ; End of list marker


; Segments and Register Values for ALI II (1511)
ALI2_List:
    dw 0C000h, 18, 4Ah, BITS_2_1, 4Ch, BIT_0, 4Eh, NOT_BIT_0, 0
    dw 0C400h, 18, 4Ah, BITS_2_1, 4Ch, BIT_1, 4Eh, NOT_BIT_0, 0
    dw 0C800h, 18, 4Ah, BITS_2_1, 4Ch, BIT_2, 4Eh, NOT_BIT_1, 0
    dw 0CC00h, 18, 4Ah, BITS_2_1, 4Ch, BIT_3, 4Eh, NOT_BIT_1, 0
    dw 0D000h, 18, 4Ah, BITS_2_1, 4Ch, BIT_4, 4Eh, NOT_BIT_2, 0
    dw 0D400h, 18, 4Ah, BITS_2_1, 4Ch, BIT_5, 4Eh, NOT_BIT_2, 0
    dw 0D800h, 18, 4Ah, BITS_2_1, 4Ch, BIT_6, 4Eh, NOT_BIT_3, 0
    dw 0DC00h, 18, 4Ah, BITS_2_1, 4Ch, BIT_7, 4Eh, NOT_BIT_3, 0
    dw 0E000h, 18, 4Ah, BITS_2_1, 4Dh, BIT_0, 4Eh, NOT_BIT_4, 0
    dw 0E400h, 18, 4Ah, BITS_2_1, 4Dh, BIT_1, 4Eh, NOT_BIT_4, 0
    dw 0E800h, 18, 4Ah, BITS_2_1, 4Dh, BIT_2, 4Eh, NOT_BIT_5, 0
    dw 0EC00h, 18, 4Ah, BITS_2_1, 4Dh, BIT_3, 4Eh, NOT_BIT_5, 0
    dw 0F000h, 18, 4Ah, BITS_2_1, 4Dh, BIT_4, 4Eh, NOT_BIT_6, 0
    dw 0F400h, 18, 4Ah, BITS_2_1, 4Dh, BIT_5, 4Eh, NOT_BIT_6, 0
    dw 0F800h, 18, 4Ah, BITS_2_1, 4Dh, BIT_6, 4Eh, NOT_BIT_7, 0
    dw 0FC00h, 18, 4Ah, BITS_2_1, 4Dh, BIT_7, 4Eh, NOT_BIT_7, 0
    dw 00000h                      ; End of list marker


; Segments and Register Values for ALI III and IV
ALI3_List:
    dw 0C000h, 18, 4Ch, BIT_0, 4Eh, BIT_0, 50h, NOT_BIT_0, 0
    dw 0C400h, 18, 4Ch, BIT_1, 4Eh, BIT_1, 50h, NOT_BIT_1, 0
    dw 0C800h, 18, 4Ch, BIT_2, 4Eh, BIT_2, 50h, NOT_BIT_2, 0
    dw 0CC00h, 18, 4Ch, BIT_3, 4Eh, BIT_3, 50h, NOT_BIT_3, 0
    dw 0D000h, 18, 4Ch, BIT_4, 4Eh, BIT_4, 50h, NOT_BIT_4, 0
    dw 0D400h, 18, 4Ch, BIT_5, 4Eh, BIT_5, 50h, NOT_BIT_5, 0
    dw 0D800h, 18, 4Ch, BIT_6, 4Eh, BIT_6, 50h, NOT_BIT_6, 0
    dw 0DC00h, 18, 4Ch, BIT_7, 4Eh, BIT_7, 50h, NOT_BIT_7, 0
    dw 0E000h, 18, 4Dh, BIT_0, 4Fh, BIT_0, 51h, NOT_BIT_0, 0
    dw 0E400h, 18, 4Dh, BIT_1, 4Fh, BIT_1, 51h, NOT_BIT_1, 0 
    dw 0E800h, 18, 4Dh, BIT_2, 4Fh, BIT_2, 51h, NOT_BIT_2, 0 
    dw 0EC00h, 18, 4Dh, BIT_3, 4Fh, BIT_3, 51h, NOT_BIT_3, 0 
    dw 00000h                      ; End of list marker


ALIP2_List:
    dw 0C000h, 10, 84h, BITS_5_4, 0 
    dw 0C400h, 10, 84h, BITS_7_6, 0 
    dw 0C800h, 10, 85h, BITS_1_0, 0 
    dw 0CC00h, 10, 85h, BITS_3_2, 0 
    dw 0D000h, 10, 85h, BITS_5_4, 0 
    dw 0D400h, 10, 85h, BITS_7_6, 0 
    dw 0D800h, 10, 86h, BITS_1_0, 0 
    dw 0DC00h, 10, 86h, BITS_3_2, 0
    dw 0E000h, 10, 86h, BITS_5_4, 0 
    dw 0E400h, 10, 86h, BITS_7_6, 0 
    dw 0E800h, 10, 87h, BITS_1_0, 0 
    dw 0EC00h, 10, 87h, BITS_3_2, 0 
    dw 00000h                      ; End of list marker


ALIK7_List:
    dw 0C000h, 10, 90h, BITS_1_0, 0 
    dw 0C400h, 10, 90h, BITS_3_2, 0 
    dw 0C800h, 10, 90h, BITS_5_4, 0 
    dw 0CC00h, 10, 90h, BITS_7_6, 0 
    dw 0D000h, 10, 91h, BITS_1_0, 0 
    dw 0D400h, 10, 91h, BITS_3_2, 0 
    dw 0D800h, 10, 91h, BITS_5_4, 0 
    dw 0DC00h, 10, 91h, BITS_7_6, 0 
    dw 0E000h, 10, 92h, BITS_1_0, 0 
    dw 0E400h, 10, 92h, BITS_3_2, 0 
    dw 0E800h, 10, 92h, BITS_5_4, 0 
    dw 0EC00h, 10, 92h, BITS_7_6, 0 
    dw 0F000h, 10, 93h, BITS_1_0, 0 
    dw 0F400h, 10, 93h, BITS_1_0, 0 
    dw 0F800h, 10, 93h, BITS_1_0, 0 
    dw 0FC00h, 10, 93h, BITS_1_0, 0 
    dw 00000h                      ; End of list marker


ALI486_List:
    dw 0C000h, 18, 13h, BIT_0, 14h, BITS_5_4, 17h, 80C0h, 0 
    dw 0C400h, 18, 13h, BIT_1, 14h, BITS_5_4, 17h, 80C0h, 0 
    dw 0C800h, 18, 13h, BIT_2, 14h, BITS_5_4, 17h, 80C0h, 0 
    dw 0CC00h, 18, 13h, BIT_3, 14h, BITS_5_4, 17h, 80C0h, 0 
    dw 0D000h, 18, 13h, BIT_4, 14h, BITS_5_4, 17h, 80C0h, 0 
    dw 0D400h, 18, 13h, BIT_5, 14h, BITS_5_4, 17h, 80C0h, 0 
    dw 0D800h, 18, 13h, BIT_6, 14h, BITS_5_4, 17h, 80C0h, 0
    dw 0DC00h, 18, 13h, BIT_7, 14h, BITS_5_4, 17h, 80C0h, 0
    dw 0E000h, 18, 14h, BIT_0, 14h, BITS_5_4, 17h, 80C0h, 0
    dw 0E400h, 18, 14h, BIT_0, 14h, BITS_5_4, 17h, 80C0h, 0
    dw 0E800h, 18, 14h, BIT_1, 14h, BITS_5_4, 17h, 80C0h, 0
    dw 0EC00h, 18, 14h, BIT_1, 14h, BITS_5_4, 17h, 80C0h, 0
    dw 00000h                      ; End of list marker

;-------------------------- END OF ALI CHIPSETS LIST --------------------------


;------------------------ START OF PPRO CHIPSETS LIST -------------------------

; MTRR Values for PPro
PProList:
    dw 0C000h, 14, 268h, Typ_06, Typ_06, 000h, 000h
    dw 0C400h, 14, 268h, 000h, 000h, Typ_06, Typ_06
    dw 0C800h, 14, 269h, Typ_06, Typ_06, 000h, 000h
    dw 0CC00h, 14, 269h, 000h, 000h, Typ_06, Typ_06
    dw 0D000h, 14, 26Ah, Typ_06, Typ_06, 000h, 000h
    dw 0D400h, 14, 26Ah, 000h, 000h, Typ_06, Typ_06
    dw 0D800h, 14, 26Bh, Typ_06, Typ_06, 000h, 000h
    dw 0DC00h, 14, 26Bh, 000h, 000h, Typ_06, Typ_06
    dw 0E000h, 14, 26Ch, Typ_06, Typ_06, 000h, 000h
    dw 0E400h, 14, 26Ch, 000h, 000h, Typ_06, Typ_06
    dw 0E800h, 14, 26Dh, Typ_06, Typ_06, 000h, 000h
    dw 0EC00h, 14, 26Dh, 000h, 000h, Typ_06, Typ_06
    dw 0F000h, 14, 26Eh, Typ_06, Typ_06, 000h, 000h
    dw 0F400h, 14, 26Eh, 000h, 000h, Typ_06, Typ_06
    dw 0F800h, 14, 26Fh, Typ_06, Typ_06, 000h, 000h
    dw 0FC00h, 14, 26Fh, 000h, 000h, Typ_06, Typ_06
    dw 00000h                      ; End of list marker

;-------------------------- END OF PPRO CHIPSETS LIST -------------------------


;------------------------------------------------------------------------------

; MTRR Register for K7, K8
K7_List:
    dw 0C000h, 6, 268h
    dw 0C800h, 6, 269h
    dw 0D000h, 6, 26Ah
    dw 0D800h, 6, 26Bh
    dw 0E000h, 6, 26Ch
    dw 0E800h, 6, 26Dh
    dw 0F000h, 6, 26Eh
    dw 0F800h, 6, 26Fh
    dw 00000h                      ; End of list marker
;------------------------------------------------------------------------------

;========================= END OF CHIPSETS CONFIG DATA ========================


;;------------------------------------------------------------------------------
;; Prints an Only Space
;;------------------------------------------------------------------------------
;Print_Space:
;    push  dx                       ; Preserves DX for safety
;    mov   ah,02h
;    mov   dl,' '
;    int   21h
;    pop   dx                       ; Restores original DX value
;    ret


Set_PCI:                           ; SI=>Liste, BX= BUSDEV
    mov   si,liste                 ; Register-Liste

@Sloop:
    mov   ax,WORD PTR [si]
    or    ax,ax
    stc
    jz    @fertig                  ; Exit mit Carry
    mov   dx,es
    cmp   dx,ax
    je    @Found
    add   si,WORD PTR [si + 2]
    jmp   @Sloop

@Found:
    mov   ax,es

ifdef DebugVersion
    call  Print_Hex_Value
;    mov   dx,OFFSET Comma_$
;    call  Do_Print_Str
endif

    cmp   Found_Chip,0484h         ; Master Enable nur fÅr SIO, bei PIIX ist 44h 
    jne   @floop                   ; reserviert, bei PIIX3 IDE-Timing!
    mov   di,44h                   ; Master Enable
    mov   cl,17h                   ; PCIMaster: BIOS:Ro, 8000-A000:rw
    mov   bx,Bus_Dev_1
    mov   ax,0B10Bh                ; write cfg
    int   1Ah

@floop:
    add   si,4
    mov   ax,WORD PTR [si]         ; Register nach AX
    or    ax,ax
    jz    @fertig
    mov   bx,Bus_Dev_0             ; Bus+DEV+Func of the first PCI device from the table
    cmp   ah,1                     ; Kennung fÅr: use BusDev1
    jne   @Keep_Bus_Dev_0          ;
    mov   bx,Bus_Dev_1             ; Bus+DEV+Func

@Keep_Bus_Dev_0:
    mov   ah,0                     ; remove "use BusDev1" flag from AX
    mov   di,ax                    ; Register nach DI
    mov   ax,0B108h                ; read cfg byte to CL
    int   1Ah
    jc    @fertig
    mov   al,BYTE PTR [si + 2]     ; Andmaske = Not Lobyte
    not   al
    and   cl,al              
    
    ; jetzt sind die Bits, die in der Maske gesezt sind, auf Null
    mov   al,BYTE PTR [si + 2]     ; Andmaske = Not Lobyte
    mov   ah,BYTE PTR [si + 3]     ; Ormaske  = HiByte
    and   ah,al                    ; nur die Bits der Maske werden berÅcksichtigt
    or    cl,ah
    mov   ax,0B10Bh                ; write cfg byte
    int   1Ah
    jnc   @floop

@fertig:
    ;clc

ifdef DebugVersion
    mov   dx,OFFSET CR_LF_$
    call  Do_Print_Str
endif

    ret
;------------------------------- Set_PCI END ----------------------------------


;-----------------------------------------------
Set_PPro: 
    ;PPro programmieren
    GetMSR 02FFh, MTRR_Def_Type, Dummy
    ToggleCR0                          ; Cache Freeze
    wbinvd                             ; Write Back inv.
    ClearICache

    ;MTRR aus
    mov   ebx,MTRR_Def_Type
    and   ebx,not 0800h
    SetMSR MSR_CONTROL, ebx, Dummy

;jetzt kanns losgehen...
    mov   si,OFFSET PProList       ; Register-Liste

@ProSloop:
    mov   ax,WORD PTR [si]         ; Segment-Wert
    or    ax,ax
    stc
    jz    @ProFertig               ; Exit with Carry
    mov   dx,es
    cmp   dx,ax
    je    @Pro_Found
    add   si,WORD PTR [si + 2]     ; SI auf nÑchsten Segment-Wert
    jmp   @ProSloop

@Pro_Found:
    add   si,4                  ; SI auf Register
    xor   EAX, EAX
    mov   ax,WORD PTR [si]      ; MTRRnum nach AX
    mov   MTRR_Number,eax

    GetMSR MTRR_Number, MTRR_Val_Lo, MTRR_Val_Hi

    ;zwei DWord-Werte aus der Liste holen
    add   si,2
    mov   eax, DWORD PTR [si]
    add   si,4
    mov   edx, DWORD PTR [si]

    ;wenn EDX=FF dann mu· Lo durch neuen Wert ersetzt werden,
    ;sonst Hi
    cmp   edx,0
    je    @@ChangeLo

@@ChangeHi:
    mov   MTRR_Val_Hi,edx
    jmp   @@EndChange

@@ChangeLo:
    mov   MTRR_Val_Lo,eax

@@EndChange:
    SetMSR MTRR_Number, MTRR_Val_Lo, MTRR_Val_Hi
    clc                                    ; Alles OK

@ProFertig:
    ;MTRR ein
    pushf
    mov   ebx,MTRR_Def_Type
    or    ebx,0800h
    SetMSR MSR_CONTROL, ebx, Dummy
    ClearICache
    ToggleCR0                              ; Cache Freeze
    popf
    ret
;-------------------------------- Set_PPro END --------------------------------


;==============================================================================

mtrr              db 'mtrr : $'
strseg            db 'seg  : $'
Shift_Left_Count  db 0             ; Shift left counter variable


Set_K7:
    pusha
    cli

K7_Open:
    mov   ecx,0C0010010h
    rdmsr
    or    eax,80000h
    wrmsr

;K7 programmieren
    GetMSR 02FFh, MTRR_Def_Type, Dummy
    ToggleCR0                      ; Cache Freeze
    wbinvd                         ; Write Back inv.
    ClearICache

;MTRR aus
    mov   ebx,MTRR_Def_Type
    and   ebx,not 0800h
    SetMSR MSR_CONTROL, ebx, Dummy


;jetzt kanns losgehen...

    mov   si,OFFSET K7_List        ; Register-Liste

@K7Sloop:
    mov   ax,WORD PTR [si]         ; Segment-Wert
    or    ax,ax
    stc
    jz    @K7_Fertig               ; Exit with Carry

    mov   byte ptr [Shift_Left_Count],0  ; SHR fuer den neuen MTRR-Wert (18h)
    mov   dx,es                    ; die gesuchte Adresse (C800h oder sowas)
    cmp   ax,dx
    je    @K7_Found
    jg    @K7NextSegFound
    add   si,WORD PTR [si+2]       ; SI auf nÑchsten Segment-Wert
    jmp   @K7Sloop


@K7NextSegFound:
    ; das ist eine Adresse zwischen denen in der Liste, z.B. C900
    ; einen Schritt zurueck
    sub   si,WORD PTR [si + 2]     ; SI auf vorhergehenden Segment-Wert
    mov   ax,WORD PTR [si]         ; vorhergehenden Segment-Wert aus der Liste

; von hier aus 100h (4K) vorwÑrts bis =ES
@K7SearchSegLoop:
    add   byte ptr [Shift_Left_Count],8  ; weitere 8 Bit nach links
    add   ax,100h
    cmp   dx,ax
    jne   @K7SearchSegLoop

@K7_Found:
    ; ermittelt

ifdef K7DebugVersion
    pusha
    call  Print_Hex_Value
    mov   dx,OFFSET CR_LF_$
    call  Do_Print_Str
    popa
endif

    xor   eax,eax
    mov   ax,WORD PTR [si + 4]     ; MTRRnum nach AX
    mov   [MTRR_Number],eax

    GetMSR MTRR_Number, MTRR_Val_Lo, MTRR_Val_Hi

ifdef K7DebugVersion
    pusha
    mov   dx,OFFSET readstr
    call  Do_Print_Str
    mov   eax,0
    mov   eax,[MTRR_Number]
    call  PrHexDW
    call  PrStrich
    mov   eax,[MTRR_Val_Lo]
    call  PrHexDW
    call  PrStrich
    mov   eax,[MTRR_Val_Hi]
    call  PrHexDW
    mov   dx,OFFSET CR_LF$
    call  Do_Print_Str
    popa
endif

    ;die 1Eh um shlCount nach links
    cmp   Shift_Left_Count,32
    jge   @K7PrgHiWord


@K7PrgLoWord:
    mov   cl,[Shift_Left_Count]
    mov   eax,1Eh
    shl   eax,cl
    mov   ebx,0FFh                 ; Mask
    shl   ebx,cl
    not   ebx

    and   [MTRR_Val_Lo],ebx
    or    [MTRR_Val_Lo],eax
    jmp   @EndChange

@K7PrgHiWord:
    mov   cl,[Shift_Left_Count]
    sub   cl,32
    mov   eax,1Eh
    shl   eax,cl
    mov   ebx,0FFh                 ; Mask
    shl   ebx,cl
    not   ebx

    and   [MTRR_Val_Hi],ebx
    or    [MTRR_Val_Hi],eax
    jmp   @EndChange


@EndChange:
ifdef K7DebugVersion
    pusha
    mov   dx,OFFSET writestr
    call  Do_Print_Str
;    mov   eax,0
    mov   eax,[MTRR_Number]
    call  PrHexDW
    call  PrStrich
    mov   eax,[MTRR_Val_Lo]
    call  PrHexDW
    call  PrStrich
    mov   eax,[MTRR_Val_Hi]
    call  PrHexDW
    mov   dx,OFFSET CR_LF_$
    call  Do_Print_Str
    popa
endif
    
    SetMSR MTRR_Number, MTRR_Val_Lo, MTRR_Val_Hi
    clc                            ; Alles OK

@K7_Fertig:
    ; MTRR ein
    pushf
    mov   ebx,[MTRR_Def_Type]
    or    ebx,0800h
    SetMSR MSR_CONTROL, ebx, Dummy
    ClearICache
    ToggleCR0                      ; Cache Freeze
    popf

K7_Close:
    mov   ecx,0C0010010h
    rdmsr
    and   eax,not 80000h
    wrmsr
    sti
    popa
    ret
;------------------------------- Set_K7 END -----------------------------------


;==============================================================================

Found_Vendor_ID     dw 0000h       ;
Found_Device_ID     dw 0000h       ;

Init_Chipset:
    ;Get Vendor-ID Host-Bridge
;    mov   di,0                     ; Reg.0 = Vendor-ID
;    mov   bx,0                     ; Dev,Func,Bus=0
    xor   di,di                    ; Reg.0 = Vendor-ID
    xor   bx,bx                    ; Dev,Func,Bus=0
    mov   ax,0B109h                ; Read word
    int   1Ah
    mov   [Found_Vendor_ID],cx

    ;Get Device-ID Host-Bridge
    mov   di,02h                   ; Reg.2 = Device-ID
    mov   bx,00h                   ; Dev,Func,Bus=0
    mov   ax,0B109h                ; Read word
    int   1Ah
    mov   [Found_Device_ID],cx

;------------------------------------------------------------------------------
; Scan the Chipset List
;------------------------------------------------------------------------------
    mov   di,OFFSET ID_List        ; Memory offset from first ID
    sub   di,ID_LIST_LENGTH        ; (33 bytes)

Next_ID:
    add   di,ID_LIST_LENGTH
;    mov   si,0
    xor   si,si
    mov   dx, WORD PTR [di]        ; Get Vendor ID
    cmp   dx,0                     ; End of list?
    je    @No_Supported_Chipset    ; Chipset not identified
    mov   cx,WORD PTR [di + 2]     ; Get Device ID

ifdef DebugVersion
    pusha
    pushf
    push  cx
    mov   ax,dx
    call  Print_Hex_Value
    call  PrKomma
    pop   cx
    mov   ax,cx
    call  Print_Hex_Value
    mov   dx,OFFSET CR_LF$
    call  Do_Print_Str
    popf
    popa
endif

Search_Device_0:
    mov   ax,0B102h                ; Find PCI device
    int   1Ah
    jc    Next_ID
    mov   Bus_Dev_0,bx
    mov   Found_Chip,cx

ifdef DebugVersion
    pusha
    pushf
    mov   dx,OFFSET CR_LF$
    call  Do_Print_Str
    popf
    popa
endif

Search_Device_1:
    mov   cx,WORD PTR [di + 4]
    cmp   cx,0
    je    @Skip_Device_1
    mov   ax,0B102h                ; Find PCI device
    int   1Ah

    ;jc    @NoSupportedChipset
    jc    Next_ID
    mov   Bus_Dev_1,bx
    mov   Found_Chip,cx

@Skip_Device_1:
    mov   ax,WORD PTR [di + 6]
    mov   Liste,ax

    mov   ax,WORD PTR [di + 8]
    mov   PPro_Found,ax

    mov   ax,WORD PTR [di + 10]
    mov   Untested,ax
   
    push  dx

    add   di,12                    ; Length of the chip register data
    mov   dx,di                    ; Chip name
    call  Do_Print_Str

    mov   dx,OFFSET Found_String$  ; Show 'found' string
    call  Print_String

;    pop dx
;    pushf

    cmp   Untested,0
    je    @Is_Tested

    cmp   Untested,UNSUPPORTED_UNTESTED            ;1
    je    @UnTested

    cmp   Untested, UNSUPPORTED_NO_DATASHEET       ;2
    je    @UnSupp2

    cmp   Untested, UNSUPPORTED_NO_SHADOW_RAM      ;3
    je    @UnSupp3

    cmp   Untested, UNSUPPORTED_CONFIG_MECHANISM   ;4
    je    @UnSupp4

    cmp   Untested,UNSUPPORTED_WRONG_DOC           ;5
    je    @UnSupp5

    cmp   Untested,UNSUPPORTED_NO_HOST_BRIDGE      ;6
    je    @UnSupp6
    
    jmp   @Init_Cancel


@UnSupp6:
    mov   dx,OFFSET Unsupp6$       ; Unsup. ausgeben
    jmp   @Init_Cancel


@UnSupp5:
    mov   dx,OFFSET Unsupp5$       ; Unsup. ausgeben
    jmp   @Init_Cancel


@UnSupp4:
    mov   dx,OFFSET Unsupp4$       ; Unsup. ausgeben
    jmp   @Init_Cancel


@UnSupp3:
    mov   dx,OFFSET Unsupp3$       ; Unsup. ausgeben
    jmp   @Init_Cancel


@UnSupp2:
    mov   dx,OFFSET Unsupp2$       ; Unsup. ausgeben
    jmp   @Init_Cancel


@UnTested:
    mov   dx,OFFSET Untested$      ; Untested ausgeben
    call  Print_String

;    mov   ax,00h
    xor   ax,ax
    int   16h
;    cmp   al,27                    ; ESC pressed ???
    cmp   al,ESC_KEY               ; ESC pressed ???
    jne   @Is_Tested
    mov   dx,OFFSET Canceled$      ; Abgebrochen ausgeben
    jmp   @Init_Cancel


@Is_Tested:
    pop   dx
    jmp   @Init_Exit


@No_Supported_Chipset:
    push  dx
    mov   dx,OFFSET NoIntel$       ; Message
    call  Print_String
    call  Print_Device_IDs
    pop   dx
    stc                            ; Carry, da Fehler
    jmp   @Init_Exit


@IError:
    push  dx
    mov   dx,OFFSET IErr$

@Init_Cancel:
    call  Print_String
    pop   dx
    stc                            ;Carry, da Fehler
    jmp   @Init_Exit


@Init_Exit:
    ret
;----------------------------- Init_Chipset END -------------------------------


Test_K7_CPU:
    pusha

    ; K7/K8 suchen, zuerst AMD-CPU suchen
;    mov   eax,0
    xor   eax,eax
    cpuid
    cmp   DWORD PTR amd_id_string,ebx
    jne   No_AMD_CPU
    cmp   DWORD PTR amd_id_string[+4],edx
    jne   No_AMD_CPU
    cmp   DWORD PTR amd_id_string[+8],ecx
    jne   No_AMD_CPU

    ; eine AMD-CPU, jetzt die Model-Number testen
    ; erstmal sehen, ob das unterstuetzt wird...
    mov   eax,80000000h
    cpuid                          ; get max function
    cmp   eax,80000001h
    jb    No_CPUID_Extended_Func   ; kein ext
;    mov   eax,1
    xor   eax,eax
    inc   ax                       ; EAX = 1
    cpuid                          ; get family/model/stepping/features
    shr   eax,8                    ; isolate family
    and   eax,0Fh
    cmp   al,6                     ; K7
    je    Write_K7
    cmp   al,0Fh                   ; K8 (what the hell comes for a K9, K10 ???)
    je    Write_K8
    cmp   al,6                     ; K7
    jg    Write_AMD_Unknown
    jmp   No_CPUID_Extended_Func


Write_K7:
    mov   dx,OFFSET AMD_K7_Found$
    call  Do_Print_Str
    mov   dx,OFFSET Found_String$  ; erkannt ausgeben
    call  Print_String
    jmp   AMD_K7_or_Higher


Write_K8:
    mov   dx,OFFSET AMD_K8_Found$
    call  Do_Print_Str
    mov   dx,OFFSET Found_String$   ; erkannt ausgeben
    call  Print_String
    jmp   AMD_K7_or_Higher


Write_AMD_Unknown:
    mov   dx,OFFSET AMD_Unknown_Found$
    call  Do_Print_Str
    mov   dx,OFFSET Found_String$  ;erkannt ausgeben
    call  Print_String
    jmp   AMD_K7_or_Higher


AMD_K7_or_Higher:
    stc
    jmp   @End_Test_K7_CPU


No_CPUID_Extended_Func:
No_AMD_CPU:
    ;mov   dx,OFFSET No_AMD_Found$
    ;call  Print_String
    clc
;    jmp   @End_Test_K7_CPU


@End_Test_K7_CPU:
    popa
    ret
;----------------------------- Test_K7_CPU END --------------------------------


;----------------------------------------------------------
Set_Chipset:
    pusha
    call  Set_PCI
    jc    @Set_Error

;Speicher initialisieren, falls Board mit ParitÑt arbeitet
;    mov   di,0                     ; ParitÑtsprÅfung abschalten
    xor   di,di                    ; ParitÑtsprÅfung abschalten
    mov   dx,61h
    in    al,dx                    ; alte Einstellung merken
    push  ax
    or    al,0Ch
    out   dx,al
    cld                            ; vorwÑrts
    mov   cx,1000h                 ; 16K Speicher mit 0 fÅllen (1000h x 4bytes = 16KB)
;    mov   eax,0
    xor   eax,eax
    rep   stosd
    in    al,dx                    ; Reset Pararity-Flipflop
    pop   ax
    out   dx,al                    ; wieder alte Einstellung
    clc

@Set_Error:
    popa
    ret
;----------------------------- Set_Chipset END --------------------------------


;----------------------------------------------------------
Init_RAM_4KB:
    pusha
;    mov   di,0                     ; disable parity check
    xor   di,di                    ; disable parity check
    mov   dx,61h
    in    al,dx                    ; save old setting
    push  ax
    or    al,0Ch
    out   dx,al
    cld
    mov   cx,400h                  ; fill 4K memory with 0 (400h x 4bytes = 4KB)
;    mov   eax,0
    xor   eax,eax
    rep   stosd
    in    al,dx                    ; reset parity flip-flop
    pop   ax
    out   dx,al                    ; restore old setting
    clc
    popa
    ret
;---------------------------- Init_RAM_4KB END --------------------------------


END

