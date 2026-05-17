format ELF64
public _start

section '.bss' writable
    urandom_fd   dq 0
    balance      dq 0           ; счет игрока
    casino_bal   dq 0           ; счет казино
    dice_count   dq 0
    dice_sides   dq 0
    threshold    dq 0
    guess        dq 0
    bet          dq 0
    dice_sum     dq 0
    max_possible dq 0

    BUFFER_SIZE equ 256
    buffer       rb BUFFER_SIZE
    num_buf      rb 32

section '.data' writable
    urandom_path db '/dev/urandom', 0

    msg_bal      db 0x0A, '====================', 0x0A, 'Игрок: ', 0
    msg_casino   db ' | Казино: ', 0
    msg_dcount   db 'Введите количество кубиков (0 для выхода): ', 0
    msg_dsides   db 'Введите количество граней: ', 0
    msg_range    db '-> Диапазон возможных сумм: от ', 0
    msg_to       db ' до ', 0
    msg_thresh   db '-> Порог (среднее): ', 0
    msg_guess    db 0x0A, 'Введите задуманное число: ', 0
    msg_bet      db 'Введите вашу ставку: ', 0

    msg_err_fmt  db '!!! ОШИБКА: Некорректный ввод! Введите только целое положительное число.', 0x0A, 0
    msg_err_rng  db '!!! ОШИБКА: Число вне диапазона возможных значений кубиков!', 0x0A, 0
    msg_err_bet_p db '!!! ОШИБКА: У вас недостаточно очков!', 0x0A, 0
    msg_err_bet_c db '!!! ОШИБКА: Казино не сможет выплатить выигрыш (ставка х4)! Уменьшите ставку.', 0x0A, 0

    msg_roll     db 'Выпали кубики: ', 0
    msg_plus     db ' + ', 0
    msg_eq       db ' = ', 0

    msg_win4     db 0x0A, '>>> ТОЧНО! Вы выиграли ставку x4!', 0x0A, 0
    msg_win1     db 0x0A, '>>> ПОПАДАНИЕ В ДИАПАЗОН! Ставка выиграна!', 0x0A, 0
    msg_lose     db 0x0A, '>>> ПРОИГРЫШ. Попробуйте еще раз.', 0x0A, 0

    msg_game_over db 0x0A, 'ИГРА ОКОНЧЕНА. Ваши очки закончились.', 0x0A, 0
    msg_casino_bankrupt db 0x0A, '>>> КАЗИНО ОБАНКРОТИЛОСЬ! ВЫ ПОБЕДИЛИ!', 0x0A, 0

    newline      db 0x0A, 0

section '.text' executable

_start:
    ; Начальные значения счетов
    mov qword [balance], 100
    mov qword [casino_bal], 1000

    ; Открываем ГСЧ
    mov rax, 2
    mov rdi, urandom_path
    mov rsi, 0
    syscall
    test rax, rax
    js exit_program
    mov [urandom_fd], rax

game_loop:
    ; Проверки на банкротство
    cmp qword [balance], 0
    jle game_over
    cmp qword [casino_bal], 0
    jle casino_bankrupt

    ; Вывод баланса игрока и казино
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

input_dcount:
    mov rdi, msg_dcount
    call print_string
    call read_num
    cmp rdx, 1              ; Проверка флага ошибки ввода
    je .invalid_fmt_dcount
    cmp rax, 0
    je close_input          ; Выход, если ввели 0
    mov [dice_count], rax
    jmp input_dsides

.invalid_fmt_dcount:
    mov rdi, msg_err_fmt
    call print_string
    jmp input_dcount

input_dsides:
    mov rdi, msg_dsides
    call print_string
    call read_num
    cmp rdx, 1              ; Проверка флага ошибки ввода
    je .invalid_fmt_dsides
    cmp rax, 2              ; Защита: граней не может быть меньше 2
    jl .invalid_fmt_dsides
    mov [dice_sides], rax
    jmp calc_threshold

.invalid_fmt_dsides:
    mov rdi, msg_err_fmt
    call print_string
    jmp input_dsides

calc_threshold:
    ; 2. Расчет границ и порога
    mov rax, [dice_count]
    mov rbx, [dice_sides]
    mul rbx
    mov [max_possible], rax     ; Max = count * sides

    ; Порог = (Min + Max) / 2
    mov rbx, [max_possible]
    add rbx, [dice_count]
    shr rbx, 1
    mov [threshold], rbx

    ; Вывод информации о диапазоне
    mov rdi, msg_range
    call print_string
    mov rax, [dice_count]
    call print_num
    mov rdi, msg_to
    call print_string
    mov rax, [max_possible]
    call print_num
    mov rdi, newline
    call print_string

    mov rdi, msg_thresh
    call print_string
    mov rax, [threshold]
    call print_num
    mov rdi, newline
    call print_string

input_guess:
    mov rdi, msg_guess
    call print_string
    call read_num
    cmp rdx, 1              ; Проверка флага ошибки ввода
    je .invalid_fmt_guess

    ; ПРОВЕРКА ДИАПАЗОНА
    cmp rax, [dice_count]
    jl .invalid_range
    cmp rax, [max_possible]
    jg .invalid_range
    mov [guess], rax
    jmp input_bet

.invalid_range:
    mov rdi, msg_err_rng
    call print_string
    jmp input_guess

.invalid_fmt_guess:
    mov rdi, msg_err_fmt
    call print_string
    jmp input_guess


input_bet:
    mov rdi, msg_bet
    call print_string
    call read_num
    cmp rdx, 1              ; Проверка флага ошибки ввода
    je .invalid_fmt_bet

    cmp rax, 1              ; Ставка не может быть 0
    jl .invalid_fmt_bet

    ; Проверка средств игрока
    cmp rax, [balance]
    jg .invalid_bet_p

    ; Проверка средств казино (ставка * 4 <= casino_bal)
    mov rbx, rax
    shl rbx, 2
    cmp rbx, [casino_bal]
    jg .invalid_bet_c

    mov [bet], rax
    jmp roll_process

.invalid_bet_p:
    mov rdi, msg_err_bet_p
    call print_string
    jmp input_bet

.invalid_bet_c:
    mov rdi, msg_err_bet_c
    call print_string
    jmp input_bet

.invalid_fmt_bet:
    mov rdi, msg_err_fmt
    call print_string
    jmp input_bet

roll_process:
    ; Читаем случайные байты
    mov rax, 0
    mov rdi, [urandom_fd]
    mov rsi, buffer
    mov rdx, [dice_count]
    syscall

    mov rdi, msg_roll
    call print_string
    xor r12, r12 ; общая сумма
    xor r13, r13 ; счетчик кубиков

.loop:
    cmp r13, [dice_count]
    je .done
    xor rdx, rdx
    movzx rax, byte [buffer + r13]
    div [dice_sides]
    inc rdx
    add r12, rdx

    push rdx
    mov rax, rdx
    call print_num
    pop rdx

    inc r13
    cmp r13, [dice_count]
    je .loop
    mov rdi, msg_plus
    call print_string
    jmp .loop

.done:
    mov [dice_sum], r12
    mov rdi, msg_eq
    call print_string
    mov rax, [dice_sum]
    call print_num
    mov rdi, newline
    call print_string

    mov rax, [dice_sum]
    mov rbx, [guess]
    mov rcx, [threshold]

    cmp rax, rbx
    je .win_x4

    cmp rax, rcx
    jl .check_low
    jg .check_high
    jmp .lose

.check_low:
    cmp rbx, rcx
    jl .win_x1
    jmp .lose
.check_high:
    cmp rbx, rcx
    jg .win_x1
    jmp .lose

.win_x4:
    mov rdi, msg_win4
    call print_string
    mov rax, [bet]
    shl rax, 2
    add [balance], rax       ; Игрок в плюсе
    sub [casino_bal], rax    ; Казино в минусе
    jmp game_loop

.win_x1:
    mov rdi, msg_win1
    call print_string
    mov rax, [bet]
    add [balance], rax
    sub [casino_bal], rax
    jmp game_loop

.lose:
    mov rdi, msg_lose
    call print_string
    mov rax, [bet]
    sub [balance], rax
    add [casino_bal], rax
    jmp game_loop

game_over:
    mov rdi, msg_game_over
    call print_string
    jmp close_input

casino_bankrupt:
    mov rdi, msg_casino_bankrupt
    call print_string

close_input:
    mov rax, 3
    mov rdi, [urandom_fd]
    syscall

exit_program:
    mov rax, 60
    xor rdi, rdi
    syscall

print_string:
    push rax
    push rdi
    push rsi
    push rdx
    mov rsi, rdi
    xor rax, rax
.slen:
    cmp byte [rsi+rax], 0
    je .sdone
    inc rax
    jmp .slen
.sdone:
    mov rdx, rax
    mov rax, 1
    mov rdi, 1
    syscall
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
.loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    mov [rsi], dl
    dec rsi
    test rax, rax
    jnz .loop
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
    push rdi
    push rsi

    mov rax, 0
    mov rdi, 0
    mov rsi, buffer
    mov rdx, BUFFER_SIZE    ; Читаем больше данных, чтобы исключить зависания буфера
    syscall

    test rax, rax
    jle .read_error         ; Если ошибка чтения системного вызова

    xor rax, rax
    xor rbx, rbx            ; RBX будем использовать как счетчик валидных цифр
    mov rsi, buffer
.loop:
    movzx rcx, byte [rsi]
    cmp rcx, 0x0A           ; Конец строки (Enter)
    je .check_empty
    cmp rcx, '0'
    jl .read_error          ; Если символ ДО '0' (буквы, минус, пробел) -> ОШИБКА
    cmp rcx, '9'
    jg .read_error          ; Если символ ПОСЛЕ '9' (буквы и тд) -> ОШИБКА

    sub rcx, '0'
    imul rax, 10
    add rax, rcx
    inc rsi
    inc rbx                 ; Увеличиваем счетчик цифр
    jmp .loop

.check_empty:
    test rbx, rbx
    jz .read_error          ; Если игрок нажал просто Enter без цифр -> ОШИБКА
    xor rdx, rdx            ; rdx = 0 (Успешно)
    jmp .done

.read_error:
    mov rdx, 1              ; rdx = 1 (Флаг ошибки)
    xor rax, rax            ; Обнуляем результат на всякий случай

.done:
    pop rsi
    pop rdi
    pop rcx
    pop rbx
    ret
