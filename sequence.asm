section .data
    SYS_EXIT          equ 60
    SYS_READ          equ 0
    SYS_OPEN          equ 2
    SYS_CLOSE         equ 3
    
    O_RDONLY          equ 0
    
    EXIT_CODE_CORRECT equ 0
    EXIT_CODE_ERROR   equ 1
    
    bufsize           equ 4096
    n_of_buckets      equ 4

section .bss
    buf resb bufsize
    
    ;permutations are represented by bitmasks; every permutation consist of
    ;numbers from 1 to 255, hence to represent a permutation we need 255 bits
    ;(where 1 - number is in permutation, 0 otherwise), thus every bitmask
    ;consist of 4 "smaller" 64-bit (qword) bitmasks (let's name them "buckets")
    ;
    ;every number is represented as (number mod 64)th bit in (number/64)th bucket
    first_bitmask resq n_of_buckets
    current_bitmask resq n_of_buckets

section .text
    global _start
    
_start:
    pop rcx; rcx - number of arguments + 1
    cmp rcx, 2; if number of args != 1:
    jne exit_error; exit with error
    
    add rsp, 8; rsp points at the name of a file
    pop rsi; rsi - pointer to the name of a file

    mov rax, SYS_OPEN; open(
    mov rdi, rsi;           filename,
    mov rsi, O_RDONLY;      O_RDONLY
    syscall;           )
    
    mov r14, rax; r14 - file descriptor (or error if < 0)
    
    test r14, r14; if open() returned an incorrect file descriptor (fd < 0):
    js exit_error; exit with error
    
    ;rbx: 
    ;   bh: 1 if there has been a permutation already, 0 if not
    ;   bl - last bit read
    
    mov bl, 1; set bl to something other than 0 - to 'error' empty files 

while_data_to_process:
    mov rax, SYS_READ; read(
    mov rdi, r14;          fd,
    mov rsi, buf;          buf
    mov rdx, bufsize;      count
    syscall;           )
    
    mov r13, rax; r13 - returned value - number of bytes read (or error if < 0)

    test r13, r13; if there was error in read (value returned by read() was < 0):
    js exit_error; exit with error
    
    test r13, r13; if there is no data left:
    jz while_data_to_process_end; exit loop
    
    mov r15, buf; r15 - pointer to buffer
    
    while_data_in_current_buffer:
        xor rax, rax; clear rax for byte read
        mov al, [r15]; al - current number (from buffer)
        mov bl, al; update bl - last byte read
        
        inc r15; progress buffer
        dec r13; decrement number of bytes left to read
        
        test al, al; if current number is 0:
        jz full_permutation; summarize permutation
        
        ;else: process it as a next number
        
        ;find representation of number:
        shl rax, 2; tricky division by base (64) ->
        shr al, 2; -> now ah - bucket number (number/64), al - bit (number mod 64)
     
        ;make r8 a bitmask for a new byte:
        mov r8, 1; set r8 to 1
        mov cl, al; set cl (needed for shl operation) to al (bit position)
        shl r8, cl; shift r8 (before operation: 1) by cl (bit position) 
        ;now r8 - a bitmask with only a proper bit set 
        
        xor rcx, rcx; clear rcx
        mov cl, ah; rcx - bucket number
        
        mov rsi, current_bitmask; rsi - pointer to bucket array, [rsi + rcx*8] - bucket we need 

        mov r9, [rsi + rcx*8]; r9 - old bucket bitmask
        or [rsi + rcx*8], r8; set current bit in a proper bucket bitmask
        
        cmp [rsi + rcx*8], r9; if a proper bucket old bitmask and new bitmask are equal:
        je exit_error; it means this bit was already set - second occurence of this number - error -> exit with error
            
        jmp full_permutation_end; we processed it as a normal number, not as end of permutation
        
        full_permutation:
            test bh, bh; if there has been a permutation already:
            jnz check_new_permutation ;check if this permutation is "correct"
            
            ;otherwise: treat it as the first permutation
            copy_first_permutation:
                mov bh, 1; first permutation is only once
                mov r8, first_bitmask;   r8 - pointer to the first buckets array
                mov r9, current_bitmask; r9 - pointer to the current buckets array
                
                xor r12, r12; r12 - buckets counter (there are n_of_buckets pairs to be copied)
                
                copy_bitmasks_loop:
                    mov r11, [r9 + r12*8]; r11 - current bucket from current permutation
                    mov qword [r8 + r12*8], r11; set r12'th bucket from first permutation
                    ;to r12'th bucket from current permutation
                    mov qword [r9 + r12*8], 0; clear r12'th bucket from current permutation
                    
                    inc r12; increment buckets counter
                    cmp r12, n_of_buckets; if buckets counter reached the total number of buckets: 
                    je copy_bitmasks_loop_end; exit loop
                    
                    ; otherwise: continue loop
                    jmp copy_bitmasks_loop
                copy_bitmasks_loop_end:
                
            copy_first_permutation_end:
                jmp full_permutation_end
            
            check_new_permutation:
                mov r8, first_bitmask;   r8 - pointer to the first buckets array
                mov r9, current_bitmask; r9 - pointer to the current buckets array
                
                ;if both permutations (current and first one) are equal,
                ;then "xor" from their bitmasks should give 0
                ;as we have "buckets" with bitmasks, we check it bucket by bucket
                ;and "or" all "xor"s to see if there was any bit set to 1 (in "xor"s)
                
                xor r11, r11; r11 - "or" from "xor" pairs - if 0, then this permutation is correct
                xor r12, r12; r12 - bitmasks counter (there are n_of_buckets pairs to be xor'ed)
                
                check_bitmasks_loop:
                    mov r10, [r8 + r12*8]; set r10 to r12'th bucket from first permutation
                    xor r10, [r9 + r12*8]; now r10 - "xor" from current pair of buckets
                    
                    mov qword [r9 + r12*8], 0; clear r12'th bucket from current permutation
                    
                    or r11, r10; accumulate current "xor"
                    inc r12; increment buckets counter
                    
                    cmp r12, n_of_buckets; if buckets counter reached the total number of buckets: 
                    jne check_bitmasks_loop; exit loop
                    
                check_bitmasks_loop_end:
                test r11, r11; if "or" from "xor" pairs is not 0:
                jnz exit_error; permutations are not equal - error -> exit with error
            check_new_permutation_end:
              
        full_permutation_end:
        
        test r13, r13; if there are no bytes left:
        jnz while_data_in_current_buffer; exit loop
        
    while_data_in_current_buffer_end:
    
    jmp while_data_to_process
       
while_data_to_process_end:
    test bl, bl; if the last bit wasn't 0:
    jnz exit_error; sequence is bad - error -> exit with error
    
    ;otherwise: we have processed the whole file, and encountered no errors -> exit as correct
    jmp exit_correct
    
exit_error:
    mov rdi, EXIT_CODE_ERROR
    jmp exit

exit_correct:
    mov rdi, EXIT_CODE_CORRECT
    jmp exit

exit:
    mov r13, rdi; r13 - exit code

    cmp r14, 0; if file hasn't been opened:
    jle exit_file_close_end; don't close it
    
    mov rax, SYS_CLOSE; close(
    mov rdi, r14;             fd
    syscall;            )
    
    exit_file_close_end:
    
    mov rax, SYS_EXIT; exit(
    mov rdi, r13;           status
    syscall;           )

