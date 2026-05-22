format ELF64
public _start

section '.bss' writable
    urandom_fd   dq 0
    balance      dq 0           ; счет игрока
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
    save_file    db 'balance.dat', 0      ; Имя файла для сохранения сессии

    msg_bal      db 0x0A, '====================', 0x0A, 'Текущие очки: ', 0
    msg_dcount   db 'Введите количество кубиков (0 для выхода): ', 0
    msg_dsides   db 'Введите количество граней: ', 0
    msg_range    db '-> Диапазон возможных сумм: от ', 0
    msg_to       db ' до ', 0
    msg_thresh   db '-> Порог (среднее): ', 0
    msg_guess    db 0x0A, 'Введите задуманное число: ', 0
    msg_bet      db 'Введите вашу ставку: ', 0

    msg_err_fmt  db '!!! ОШИБКА: Некорректный ввод! Введите только целое положительное число.', 0x0A, 0
    msg_err_rng  db '!!! ОШИБКА: Число вне диапазона возможных значений кубиков!', 0x0A, 0
    msg_err_bet  db '!!! ОШИБКА: У вас недостаточно очков!', 0x0A, 0

    msg_roll     db 'Выпали кубики: ', 0
    msg_plus     db ' + ', 0
    msg_eq       db ' = ', 0

    msg_win4     db 0x0A, '>>> ТОЧНО! Вы выиграли ставку x4!', 0x0A, 0
    msg_win1     db 0x0A, '>>> ПОПАДАНИЕ В ДИАПАЗОН! Ставка выиграна!', 0x0A, 0
    msg_lose     db 0x0A, '>>> ПРОИГРЫШ. Попробуйте еще раз.', 0x0A, 0
    msg_over     db 0x0A, 'ИГРА ОКОНЧЕНА. Очки закончились.', 0x0A, 0

    msg_loaded   db '>>> Сессия восстановлена. Ваш баланс загружен из файла.', 0x0A, 0

    newline      db 0x0A, 0

    ; Флаги для файловых операций (Linux x86_64)
    O_RDONLY equ 0
    O_WRONLY equ 1
    O_CREAT  equ 64
    O_TRUNC  equ 512

section '.text' executable

_start:
    ; Загружаем баланс из файла (или ставим 100 по умолчанию)
    call load_balance

    ; Открываем ГСЧ
    mov rax, 2
    mov rdi, urandom_path
    mov rsi, O_RDONLY
    syscall
    test rax, rax
    js exit_program
    mov [urandom_fd], rax

game_loop:
    cmp qword [balance], 0
    jle game_over

    mov rdi, msg_bal
    call print_string
    mov rax, [balance]
    call print_num
    mov rdi, newline
    call print_string

input_dcount:
    ; 1. Ввод параметров кубиков
    mov rdi, msg_dcount
    call print_string
    call read_num
    cmp rdx, 1                  ; Проверка на мусор/буквы
    je .invalid_fmt_dcount
    cmp rax, 0
    je close_input              ; Если 0 - корректный выход
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
    cmp rdx, 1
    je .invalid_fmt_dsides
    cmp rax, 2                  ; Защита: граней должно быть >= 2
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
    mov [max_possible], rax

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
    cmp rdx, 1
    je .invalid_fmt_guess

    ;проверка валидности числа
    cmp rax, [dice_count]
    jl .invalid_range
    cmp rax, [max_possible]
    jg .invalid_range
    mov [guess], rax
    jmp input_bet

.invalid_fmt_guess:
    mov rdi, msg_err_fmt
    call print_string
    jmp input_guess

.invalid_range:
    mov rdi, msg_err_rng
    call print_string
    jmp input_guess

input_bet:
    mov rdi, msg_bet
    call print_string
    call read_num
    cmp rdx, 1
    je .invalid_fmt_bet
    cmp rax, 1                  ; Ставка должна быть >= 1
    jl .invalid_fmt_bet
    cmp rax, [balance]
    jg .invalid_bet
    mov [bet], rax
    jmp roll_process

.invalid_fmt_bet:
    mov rdi, msg_err_fmt
    call print_string
    jmp input_bet

.invalid_bet:
    mov rdi, msg_err_bet
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
    xor r12, r12 ; сумма
    xor r13, r13 ; счетчик

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

    ; Логика выигрыша
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
    add [balance], rax
    call save_balance
    jmp game_loop

.win_x1:
    mov rdi, msg_win1
    call print_string
    mov rax, [bet]
    add [balance], rax
    call save_balance
    jmp game_loop

.lose:
    mov rdi, msg_lose
    call print_string
    mov rax, [bet]
    sub [balance], rax
    call save_balance
    jmp game_loop

game_over:
    mov rdi, msg_over
    call print_string

close_input:
    mov rax, 3
    mov rdi, [urandom_fd]
    syscall

exit_program:
    mov rax, 60
    xor rdi, rdi
    syscall

; загрузка баланса из файла
load_balance:
    ; Пытаемся открыть файл на чтение
    mov rax, 2                  ; sys_open
    mov rdi, save_file
    mov rsi, O_RDONLY
    syscall
    test rax, rax
    js .no_file                 ; Если файла нет - идем к дефолту

    mov rdi, rax                ; Передаем дескриптор в rdi
    mov rax, 0                  ; sys_read
    mov rsi, balance
    mov rdx, 8                  ; Читаем 8 байт (qword)
    syscall

    mov rax, 3                  ; sys_close
    syscall                     ; Дескриптор всё еще в rdi

    ; Проверка: если в прошлом сейве баланс был <= 0, начинаем заново
    cmp qword [balance], 0
    jle .no_file

    ; Сообщаем об успешной загрузке
    mov rdi, msg_loaded
    call print_string
    ret

.no_file:
    mov qword [balance], 100    ; Баланс по умолчанию
    ret

; сохранение баланса в файл
save_balance:
    push rax
    push rdi
    push rsi
    push rdx

    mov rax, 2                          ; sys_open
    mov rdi, save_file
    mov rsi, O_WRONLY + O_CREAT + O_TRUNC ; Открыть для записи/Создать/Очистить
    mov rdx, 420                        ; Права доступа 0644 (в десятичной 420)
    syscall
    test rax, rax
    js .save_done                       ; Ошибка при открытии - выходим

    mov rdi, rax                        ; Дескриптор
    mov rax, 1                          ; sys_write
    mov rsi, balance
    mov rdx, 8                          ; Пишем 8 байт
    syscall

    mov rax, 3                          ; sys_close
    syscall
.save_done:
    pop rdx
    pop rsi
    pop rdi
    pop rax
    ret

; вывод ставки
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

; вывод числа
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

; безопасный вывод числа с проверкой
read_num:
    push rbx
    push rcx
    push rdi
    push rsi

    mov rax, 0
    mov rdi, 0
    mov rsi, buffer
    mov rdx, BUFFER_SIZE
    syscall

    test rax, rax
    jle .read_error

    xor rax, rax
    xor rbx, rbx            ; Считаем количество распознанных цифр
    mov rsi, buffer
.loop:
    movzx rcx, byte [rsi]
    cmp rcx, 0x0A           ; Нажали Enter
    je .check_empty
    cmp rcx, '0'
    jl .read_error          ; Меньше '0' (буквы, спецсимволы, минус) -> Ошибка
    cmp rcx, '9'
    jg .read_error          ; Больше '9' -> Ошибка

    sub rcx, '0'
    imul rax, 10
    add rax, rcx
    inc rsi
    inc rbx
    jmp .loop

.check_empty:
    test rbx, rbx
    jz .read_error          ; Если ничего не ввели (просто Enter) -> Ошибка
    xor rdx, rdx            ; RDX = 0 (Успешно)
    jmp .done

.read_error:
    mov rdx, 1              ; RDX = 1 (Флаг ошибки)
    xor rax, rax            ; Чистим результат

.done:
    pop rsi
    pop rdi
    pop rcx
    pop rbx
    ret
