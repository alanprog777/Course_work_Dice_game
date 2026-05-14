format ELF64

public _start

section '.bss' writable
    urandom_fd  dq 0
    balance     dq 0          ; счет игрока
    casino_bal  dq 0          ; счет казино
    guess       dq 0
    bet         dq 0
    dice_sum    dq 0

    BUFFER_SIZE equ 256
    buffer      rb BUFFER_SIZE
    num_buf     rb 32

section '.data' writable
    urandom_path db '/dev/urandom', 0

    msg_bal      db 0x0A, '====================', 0x0A, 'Игрок: ', 0
    msg_casino   db ' | Казино: ', 0
    msg_guess    db 'Введите задуманное число (2-12, или 0 для выхода): ', 0
    msg_bet      db 'Введите вашу ставку: ', 0
    msg_roll     db 'Выпали кубики: ', 0
    msg_plus     db ' + ', 0
    msg_eq       db ' = ', 0

    msg_win4     db 0x0A, '>>> Точное совпадение! Вы выиграли ставку в 4-кратном размере!', 0x0A, 0
    msg_win1     db 0x0A, '>>> Совпадение по диапазону! Вы выиграли ставку!', 0x0A, 0
    msg_lose     db 0x0A, '>>> Неудача. Ставка проиграна.', 0x0A, 0
    msg_game_over db 0x0A, 'Игра окончена. У одного из участников закончились очки.', 0x0A, 0
    msg_casino_bankrupt db 0x0A, 'Казино обанкротилось! Вы победили!', 0x0A, 0
    
    newline      db 0x0A, 0

section '.text' executable

_start:
    ; Начальные очки
    mov qword [balance], 100     ; у игрока 100 очков
    mov qword [casino_bal], 1000 ; у казино 1000 очков

    ; Открываем /dev/urandom
    mov rax, 2
    mov rdi, urandom_path
    mov rsi, 0
    syscall
    test rax, rax
    js exit_program
    mov [urandom_fd], rax

game_loop:
    ; Проверка на окончание игры
    cmp qword [balance], 0
    jle game_over
    cmp qword [casino_bal], 0
    jle casino_bankrupt

    ; Вывод текущих балансов
    mov rdi, msg_bal
    call print_string
    mov rax, [balance]
    call print_num
    mov rdi, msg_casino
    call print_string
    mov rax, [casino_bal]
    call print_num
    mov rdi, newline
    call print_string

    ; Запрос задуманного числа
    mov rdi, msg_guess
    call print_string
    call read_num
    mov [guess], rax

    ; Выход если ввели 0
    cmp qword [guess], 0
    je close_input

    ; Запрос ставки
    mov rdi, msg_bet
    call print_string
    call read_num
    mov [bet], rax
    
    ; Проверка: ставка не больше счета игрока
    mov rax, [bet]
    cmp rax, [balance]
    jg game_loop        ; недостаточно у игрока
    
    ; Проверка: у казино достаточно денег на максимальный выигрыш (ставка * 4)
    mov rbx, rax
    shl rbx, 2          ; rbx = bet * 4
    cmp rbx, [casino_bal]
    jg game_loop        ; казино не может выплатить максимальный выигрыш

    ; Бросок кубиков
    mov rax, 0
    mov rdi, [urandom_fd]
    mov rsi, buffer
    mov rdx, 2
    syscall

    ; Первый кубик
    movzx ax, byte [buffer]
    mov cl, 6
    div cl
    mov al, ah
    inc al
    movzx r12, al

    ; Второй кубик
    movzx ax, byte [buffer+1]
    div cl
    mov al, ah
    inc al
    movzx r13, al

    ; Сумма кубиков
    mov r14, r12
    add r14, r13
    mov [dice_sum], r14

    ; Вывод результата броска
    mov rdi, msg_roll
    call print_string
    mov rax, r12
    call print_num
    mov rdi, msg_plus
    call print_string
    mov rax, r13
    call print_num
    mov rdi, msg_eq
    call print_string
    mov rax, [dice_sum]
    call print_num
    mov rdi, newline
    call print_string

    ; Игровая логика
    mov rax, [dice_sum]
    mov rbx, [guess]
    mov r10, [bet]

    ; Точное совпадение?
    cmp rax, rbx
    je exact_win

    ; Проверка диапазонов
    cmp rax, 7
    jl check_low
    jg check_high
    jmp lose_bet

check_low:
    cmp rbx, 7
    jl range_win
    jmp lose_bet

check_high:
    cmp rbx, 7
    jg range_win
    jmp lose_bet

exact_win:
    ; Выигрыш: ставка * 4
    mov rax, r10
    shl rax, 2
    add [balance], rax   ; игрок получает
    sub [casino_bal], rax ; казино теряет
    mov rdi, msg_win4
    call print_string
    jmp game_loop

range_win:
    ; Выигрыш: ставка
    add [balance], r10
    sub [casino_bal], r10
    mov rdi, msg_win1
    call print_string
    jmp game_loop

lose_bet:
    ; Проигрыш: теряем ставку
    sub [balance], r10
    add [casino_bal], r10
    mov rdi, msg_lose
    call print_string
    jmp game_loop

game_over:
    mov rdi, msg_game_over
    call print_string
    jmp close_input

casino_bankrupt:
    mov rdi, msg_casino_bankrupt
    call print_string

close_input:
    ; Закрываем /dev/urandom
    mov rax, 3
    mov rdi, [urandom_fd]
    syscall

exit_program:
    mov rax, 60
    xor rdi, rdi
    syscall

; =========================================
; ПОДПРОГРАММЫ
; =========================================

print_string:
    push rax
    push rdi
    push rsi
    push rdx

    mov rsi, rdi
    xor rax, rax
.strlen_loop:
    cmp byte [rsi + rax], 0
    je .strlen_done
    inc rax
    jmp .strlen_loop
.strlen_done:
    mov rdx, rax
    test rdx, rdx
    jz .print_done
    mov rax, 1
    mov rdi, 1
    syscall
.print_done:
    pop rdx
    pop rsi
    pop rdi
    pop rax
    ret

print_num:
    push rax
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi

    mov rbx, 10
    mov rsi, num_buf + 31
    mov byte [rsi], 0
    dec rsi

.itoa_loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    mov [rsi], dl
    dec rsi
    test rax, rax
    jnz .itoa_loop

    inc rsi
    mov rdi, rsi
    call print_string

    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

read_num:
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi

    mov rax, 0
    mov rdi, 0
    mov rsi, buffer
    mov rdx, BUFFER_SIZE
    syscall

    xor rax, rax
    xor rbx, rbx
    mov rsi, buffer

.atoi_loop:
    movzx rcx, byte [rsi]
    cmp rcx, 0x0A
    je .atoi_done
    cmp rcx, '0'
    jl .atoi_done
    cmp rcx, '9'
    jg .atoi_done

    sub rcx, '0'
    imul rax, 10
    add rax, rcx
    inc rsi
    jmp .atoi_loop

.atoi_done:
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    ret