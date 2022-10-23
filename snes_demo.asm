; SPDX-FileCopyrightText: 2022 Zeal 8-bit Computer <contact@zeal8bit.com>
;
; SPDX-License-Identifier: Apache-2.0

    ; Macro related to Zeal 8-bit OS syscall interface
    ; TODO: include the OS public header file once there will be one...
    DEFC DEV_STDOUT = 0

    MACRO WRITE dev
        ld h, dev
        ld l, 1 ; Syscall 1
        rst 0x8
    ENDM
    
    MACRO  MSLEEP  _
        ld l, 18 ; Syscall 18
        rst 0x8
    ENDM


    ; Macros related to the PIO Port A
    DEFC IO_PIO_DATA_A = 0xd0
    DEFC IO_PIO_CTRL_A = 0xd2
    DEFC IO_PIO_DISABLE_INT = 0x03
    DEFC IO_PIO_BITCTRL = 0xcf

    DEFC IO_DATA = 0
    DEFC IO_LATCH = 2
    DEFC IO_CLOCK = 3

    ORG 0x4000

main:
    ; Initialize the user port (port A) of the PIO
    ; Set it to bit control mode so that each I/O can be controlled independently.
    ld a, IO_PIO_BITCTRL
    out (IO_PIO_CTRL_A), a
    ; After setting the port as a bit-controlled one, we need to give a bitmask of
    ; pins that needs to be output (0) and input (1).
    ; Set them all to output except DATA pin.
    ld a, 1 << IO_DATA
    out (IO_PIO_CTRL_A), a
    ; Disable the interrupts for this port just in case it was activated
    ld a, IO_PIO_DISABLE_INT
    out (IO_PIO_CTRL_A), a
    ; Set the default value of each pin:
    ;   - LATCH must be LOW (0)
    ;   - CLOCK must be HIGH (1)
    ; Set other pins to 0, not very important
    ld a, 1 << IO_CLOCK
    out (IO_PIO_DATA_A), a

    ; The port is configured, we can start the reading process.
    ; Here is how the registers will be used:
    ;   C  - Address of IO_PIO_DATA_A (port A address)
    ;   HL - 12-bit data containing the state of the buttons, highest 4 bits unused
    ;   B  - State of the I/Os where both CLOCK and LATCH are HIGH (optimizes the speed)
    ;   D  - State of the I/Os where both CLOCK and LATCH are LOW (optimizes the speed)
    ;   E  - State of the I/Os where CLOCK is HIGH and LATCH is LOW (optimizes the speed)
read_controller_loop:
    ld c, IO_PIO_DATA_A
    ld b, 1 << IO_CLOCK | 1 << IO_LATCH
    ld e, 1 << IO_CLOCK
    ld d, 0
    ld hl, 0xffff
    ; Generate a pulse on the LATCH pin, CLOCK must remain high during this process
    ; Thanks to the preconfigured registers, this takes 24 T-States (2.4 microseconds @ 10MHz)
    out (c), b
    out (c), e
    ; Now, the DATA line contains the first button (B) state
    in a, (c)
    ; Let's optmize a bit by using rrca instead of and+add or bit+jp instructions
    ASSERT(IO_DATA == 0)
    rrca
    ; Put the resulted bit in H lowest bit (L will contain the last 8 buttons)
    rl h
    ; First bit is done, we have to clock the CLOCK line 15 times now!
    ; Repeat the following 3 times, the result is put in H
    ; This will be unrolled by the preprocessor
    REPT 3
        out (c), d
        out (c), e
        ; Next bit is available
        in a, (c)
        rrca
        rl h
    ENDR
    ; Repeat the following 8 times, the result is put in L
    ; This will be unrolled by the preprocessor
    REPT 8
        out (c), d
        out (c), e
        ; Next bit is available
        in a, (c)
        rrca
        rl l
    ENDR
    ; Clock 4 more times to get rid of the unused final 4 bits
    REPT 4
        out (c), d
        out (c), e
    ENDR
    ; HL contains the buttons state now!
    call print_button_state
    ; Sleep for 16ms before starting again
    ld de, 16
    MSLEEP()
    jp read_controller_loop


    ; Print the new buttons that are pressed if their state changed between
    ; two iterations.
    ; Parameter:
    ;   HL - 12-bit value representing the buttons state (highest 4 bits unused)
    ; Returns:
    ;   None
    ; Alters:
    ;   A, BC, DE, HL
print_button_state:
    ; When pressed, the buttons are set to 0. Invert HL in order to have
    ; pressed buttons set to 1.
    ld a, h
    cpl
    ld h, a
    ld a, l
    cpl
    ld l, a
    ; Retrieve the previous state and save HL as the current state
    ld de, (previous_state)
    ld (previous_state), hl
    ; Check which bits changed first.
    ; A = H XOR D
    ld a, h
    xor d
    ; Only keep the ones that are pressed (=1)
    and h
    ; If the result is 0, no button became pressed, jump to the lowest byte
    jp z, print_button_state_lowest
    ; Check the bits one by one. Be careful, we are checking from the lowest bits
    ; of the highest byte. So the order is:
    ;   Start, Select, Y, B
    ; L and E must not be altered because we need them later
    ld h, e
    push hl
    rrca
    call c, print_button_start
    rrca
    call c, print_button_select
    rrca
    call c, print_button_y
    rrca
    call c, print_button_b
    pop hl
    ld e, h
print_button_state_lowest:
    ld a, l
    xor e
    and l
    ret z   ; No change in the lowest byte, we can return
    ; Same as above, but the order is:
    ;   R, L, X, A, Right, Left, Down, Top
    rrca
    call c, print_button_r
    rrca
    call c, print_button_l
    rrca
    call c, print_button_x
    rrca
    call c, print_button_a
    rrca
    call c, print_button_right
    rrca
    call c, print_button_left
    rrca
    call c, print_button_down
    rrca
    jp c, print_button_top
    ret

    ; Print the buttons name.
    ; To do so, generate a small block for each button which let them load their string
    ; and the string length before jumping to the subroutine that does the syscall: print_button_syscall
    REPTI name, select, start, y, b, r, l, x, a, right, left, down, top

print_button_ ## name:
    ld de, name ## _str
    ld bc, name ## _str_end - name ## _str
    jp print_button_syscall

    ENDR

print_button_syscall:
    ; A must not be altered, it is required by the caller!
    push af
    WRITE(DEV_STDOUT)
    pop af
    ret

    ; Reserve 2 bytes to store the previous value of HL. The program will be loaded
    ; to RAM by Zeal 8-bit OS kernel, so we will be able to modifyt his variable.
previous_state: DEFW 0x0000
select_str: DEFM "Select\n"
select_str_end:
start_str:  DEFM "Start\n"
start_str_end:
y_str:      DEFM "Y\n"
y_str_end:
b_str:      DEFM "B\n"
b_str_end:
r_str:      DEFM "R\n"
r_str_end:
l_str:      DEFM "L\n"
l_str_end:
x_str:      DEFM "X\n"
x_str_end:
a_str:      DEFM "A\n"
a_str_end:
right_str:  DEFM "Right\n"
right_str_end:
left_str:   DEFM "Left\n"
left_str_end:
down_str:   DEFM "Down\n"
down_str_end:
top_str:    DEFM "Top\n"
top_str_end: