format ELF64
public _start

section '.bss' writable
    urandom_fd  dq 0
    balance     dq 0
    guess       dq 0
    bet         dq 0
    dice_sum    dq 0

    BUFFER_SIZE equ 256
    buffer      rb BUFFER_SIZE
    num_buf     rb 32

section '.data' writable
    urandom_path db '/dev/urandom', 0

    msg_bal      db 0x0A, '====================', 0x0A, 'Текущие очки: ', 0
    msg_guess    db 'Введите задуманное число (2-12, или 0 для выхода): ', 0
    msg_bet      db 'Введите вашу ставку: ', 0
    msg_roll     db 'Выпали кубики: ', 0
    msg_plus     db ' + ', 0
    msg_eq       db ' = ', 0

    msg_win4     db 0x0A, '>>> Точное совпадение! Вы выиграли ставку в 4-кратном размере!', 0x0A, 0
    msg_win1     db 0x0A, '>>> Совпадение по диапазону! Вы выиграли ставку!', 0x0A, 0
    msg_lose     db 0x0A, '>>> Неудача. Ставка проиграна.', 0x0A, 0
    msg_over     db 0x0A, 'Игра окончена. У вас закончились очки.', 0x0A, 0

    newline      db 0x0A, 0

section '.text' executable

_start:
    ; Инициализация начальных очков (100)
    mov qword [balance], 100

    ; Открываем /dev/urandom для получения случайных чисел
    mov rax, 2          ; syscall: sys_open
    mov rdi, urandom_path
    mov rsi, 0          ; флаг O_RDONLY
    syscall
    test rax, rax
    js exit_program     ; если ошибка открытия - выходим
    mov [urandom_fd], rax

game_loop:
    ; Проверка на проигрыш (баланс <= 0)
    cmp qword [balance], 0
    jle game_over

    ; Вывод текущего баланса
    mov rdi, msg_bal
    call print_string
    mov rax, [balance]
    call print_num
    mov rdi, newline
    call print_string

    ; Вывод запроса на задуманное число
    mov rdi, msg_guess
    call print_string

    ; Чтение числа
    call read_num
    mov [guess], rax

    ; Если ввели 0 - выход из игры
    cmp qword [guess], 0
    je close_input

    ; Вывод запроса на ставку
    mov rdi, msg_bet
    call print_string

    ; Чтение ставки
    call read_num
    mov [bet], rax

    ; ---- БРОСОК КУБИКОВ ----
    ; Читаем 2 случайных байта из /dev/urandom
    ; ---- БРОСОК КУБИКОВ ----
    mov rax, 0          ; syscall: sys_read
    mov rdi, [urandom_fd]
    mov rsi, buffer
    mov rdx, 2
    syscall

    ; Вычисляем 1-й кубик: (byte1 % 6) + 1
    movzx ax, byte [buffer]
    mov cl, 6
    div cl              ; al = результат, ah = остаток (0-5)

    mov al, ah          ; Переносим остаток в AL, чтобы избежать конфликта MOVZX
    inc al              ; сдвигаем в диапазон 1-6
    movzx r12, al       ; Теперь r12 безопасно получает значение

    ; Вычисляем 2-й кубик: (byte2 % 6) + 1
    movzx ax, byte [buffer+1]
    div cl

    mov al, ah          ; Переносим остаток в AL
    inc al
    movzx r13, al       ; r13 = второй кубик
    
    ; Считаем сумму
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

    ; ---- ИГРОВАЯ ЛОГИКА И ПРОВЕРКА УСЛОВИЙ ----
    mov rax, [dice_sum]
    mov rbx, [guess]
    mov r10, [bet]

    ; 1. Проверка на точное совпадение
    cmp rax, rbx
    je exact_win

    ; 2. Проверка диапазонов (меньше 7 или больше 7)
    cmp rax, 7
    jl check_low
    jg check_high
    jmp lose_bet        ; Если сумма ровно 7, но мы не угадали точно - проигрыш

check_low:
    cmp rbx, 7
    jl range_win        ; Сумма < 7 и задумано < 7
    jmp lose_bet

check_high:
    cmp rbx, 7
    jg range_win        ; Сумма > 7 и задумано > 7
    jmp lose_bet

exact_win:
    ; Выигрыш = ставка * 4
    mov rax, r10
    shl rax, 2          ; Быстрое умножение на 4 через сдвиг
    add [balance], rax
    mov rdi, msg_win4
    call print_string
    jmp game_loop

range_win:
    ; Выигрыш = ставка
    add [balance], r10
    mov rdi, msg_win1
    call print_string
    jmp game_loop

lose_bet:
    ; Проигрыш = минус ставка
    sub [balance], r10
    mov rdi, msg_lose
    call print_string
    jmp game_loop

game_over:
    mov rdi, msg_over
    call print_string

close_input:
    ; Закрываем файловый дескриптор urandom (аналог твоего close_input)
    mov rax, 3
    mov rdi, [urandom_fd]
    syscall

exit_program:
    mov rax, 60
    xor rdi, rdi
    syscall

; =========================================
; ПОДПРОГРАММЫ (Helpers)
; =========================================

; Печать строки (использует твой алгоритм strlen_loop)
; Вход: RDI - указатель на нуль-терминированную строку
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
    mov rdx, rax        ; длина строки

    test rdx, rdx
    jz .print_done

    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    syscall
.print_done:
    pop rdx
    pop rsi
    pop rdi
    pop rax
    ret

; Печать целого числа (itoa)
; Вход: RAX - число для вывода
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
    div rbx             ; делим на 10
    add dl, '0'         ; переводим остаток в символ ASCII
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

; Чтение ввода пользователя (atoi)
; Выход: RAX - введенное число
read_num:
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi

    mov rax, 0          ; sys_read
    mov rdi, 0          ; stdin
    mov rsi, buffer
    mov rdx, BUFFER_SIZE
    syscall

    xor rax, rax
    xor rbx, rbx
    mov rsi, buffer

.atoi_loop:
    movzx rcx, byte [rsi]
    cmp rcx, 0x0A       ; конец строки (Enter)
    je .atoi_done
    cmp rcx, '0'
    jl .atoi_done
    cmp rcx, '9'
    jg .atoi_done

    sub rcx, '0'        ; ASCII в число
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
