// -------------------------------------------------------------------------------------
// Name:        Interrupt_Countdown.S
// Purpose:     This code has 2 parts: the first part is to flash all 8 LED's on and off
//              at a rate between 1 - 10Hz while the random number generator is called
//              continuosly. The random number generated will generate a number that
//              gives a time delay of 5.0 to 25.0 seconds. with a resolution of 0.1s.
//              Pressing pushbutton S1 will create an interrupt in the microprocessor,
//              forcing the interrupt service routine (ISR) to run.
//              The ISR program displays this random number (without a decimal) on
//              the 8 LED's.  The program delays for 1 second (count of 10) and the
//              new count (time left) is diplayed. This continues until the count is
//              equal to or less than 0.  The program then exits the ISR and returns to
//              the main program and flashes all 8 LED's again as before.  
//              The program then waits for another press of pushbutton S1 and everything
//              repeats.

// Author:      Maheen Shoaib
// -------------------------------------------------------------------------------------

.section .text
.align 2
.globl _start

// Constants
GPIO_BASE                   = 0x10012000      // GPIO base address
GPIO_OUTPUT                 = 0x0C            // GPIO output register offset
GPIO_OUTPUT_ENABLE          = 0x08            // GPIO output enable register offset
GPIO_INPUT                  = 0x00            // GPIO input register offset
GPIO_INPUT_ENABLE           = 0x04            // GPIO input enable register offset
GPIO_7SEGLED_PINS           = 0x0000023F      // Seven Segment LED Display Pins (7)
GPIO_LEDBAR_PINS            = 0x00FC0C00      // LED Bar Pins (8)
GPIO_ALL_LED_PINS           = 0x00FC0E3F      // All LED Pins (15)
GPIO_FALL_INTERRUPT_ENABLE  = 0x20            // Falling edge interrupt enable register offset
GPIO_FALL_INTERRUPT_PENDING = 0x24            // Falling Edge interrupt pending register offset
GPIO_IO_FUNCTION_ENABLE     = 0x028           // I/O function enable register offset
GPIO_IO_FUNCTION_SELECT     = 0x02C           // I/O function select register offset
GPIO_SW_1                   = 0x00001000      // SW1 pushbutton (bit 12)
PLIC_BASE                   = 0x0C000000      // PLIC base address
PLIC_ENABLE                 = 0x2000          // PLIC interrupt enable register offset
PLIC_PRIORITY               = 0x0004          // PLIC priority register offset
PLIC_THRESHOLD              = 0x200000        // PLIC threshold register offset
PLIC_CLAIM                  = 0x200004        // PLIC claim/complete register offset
PLIC_INT_PEND               = 0x1000          // PLIC Interrupt pending register 1 offset
S1_GPIO_PIN                 = 12              // S1 pushbutton pin number (active low)
S1_IRQ                      = 12              // IRQ number for GPIO pin 12
S1_PLIC_ID                 = 20              // PLIC Interrupt source ID for GPIO pin 12
S1_PRIORITY                 = 7               // Interrupt priority for S1

_start:
    // Set up interrupt vector
    la t0, S1_interrupt      // load address of S1 interrupt into t0
    csrw mtvec, t0

    // Enable external machine interrupts
    li t0, (1 << 11)         // Enable MEIE
    csrs mie, t0

    // Enable global interrupts
    csrr t0, mstatus
    li t1, (1 << 3)          // Set MIE bit
    or t0, t0, t1
    csrw mstatus, t0

    // GPIO Setup
    li t0, GPIO_BASE
   
    // Configure S1 as input
    li t1, GPIO_SW_1
    sw t1, GPIO_INPUT_ENABLE(t0)
   
    // Enable falling edge interrupt for S1
    sw t1, GPIO_FALL_INTERRUPT_ENABLE(t0)
   
    // Configure LED outputs
    li t1, GPIO_ALL_LED_PINS
    sw t1, GPIO_OUTPUT_ENABLE(t0)
   
    // Initialize LEDs to off
    li t2, 0xFF03F1C0
    sw t2, GPIO_OUTPUT(t0)

    // PLIC Setup
    // Enable S1 interrupt in PLIC
    li t1, PLIC_BASE + PLIC_ENABLE
    li t2, (1 << S1_PLIC_ID)
    sw t2, 0(t1)
   
    // Set priority
    li t1, PLIC_BASE
    li t2, 4 * S1_PLIC_ID
    add t2, t2, t1
    li t3, S1_PRIORITY
    sw t3, 0(t2)
   
    // Set threshold
    li t1, PLIC_BASE + PLIC_THRESHOLD
    li t2, 6
    sw t2, 0(t1)

    // Initialize random number generator seed in a7
    li a7, 0xABCD

main_program:
    li t0, GPIO_BASE           // load GPIO base address into t0    
    // Flash LEDs: Turn all LED Bar pins on
    li t2, GPIO_LEDBAR_PINS
    sw t2, GPIO_OUTPUT(t0)
   
    // Delay (100ms)
    li a0, 1
    jal ra, DELAY
   
    // Turn LEDs off
    li t2, 0xFF03F1C0
    sw t2, GPIO_OUTPUT(t0)
   
    // Delay (100ms)
    li a0, 1
    jal ra, DELAY
   
    j main_program

// Interrupt Service Routine
S1_interrupt:
    // Save registers on stack
    addi sp, sp, -28
    sw t0, 0(sp)
    sw t1, 4(sp)
    sw t2, 8(sp)
    sw t3, 12(sp)
    sw t4, 16(sp)
    sw t5, 20(sp)
    sw ra, 24(sp)


    // Get interrupt claim (identifies the source)
    li t1, PLIC_BASE + PLIC_CLAIM
    lw t5, 0(t1)

    // Generate a new random number
    jal RandomNum

    // Scale random number to a value between 50 and 250 (tenths of a second)
    li t1, 0xC9         // 0xC9 = 201 decimal
    li t3, 0x32         // 0x32 = 50 decimal
    rem t4, a7, t1      // t4 = a7 % 201, range 0-200
    add a4, t4, t3      // a4 = (a7 % 201) + 50, range 50-250

COUNTDOWN_LOOP:
    // Display the current countdown (a4) on the LEDs
    mv t0, a4
    jal ra, DISPLAY_NUM

    // Decrement the countdown value by 10 (1.0 sec = 10 tenths)
    addi a4, a4, -10

    // Delay for 1 second (using 10 iterations of 100ms delay)
    li a0, 10
    jal ra, DELAY

    // Continue the countdown loop if a4 > 0
    bgt a4, x0, COUNTDOWN_LOOP

    // Display zero on the LEDs at the end of the countdown
    li t0, 0
    jal ra, DISPLAY_NUM

    // Clear GPIO interrupt pending flag for SW1
    li t0, GPIO_BASE
    li t1, GPIO_SW_1
    sw t1, GPIO_FALL_INTERRUPT_PENDING(t0)

    // Complete PLIC interrupt by writing back the claim value
    li t1, PLIC_BASE + PLIC_CLAIM
    sw t5, 0(t1)

    li a4, 0

    // Restore registers from stack
    lw t0, 0(sp)
    lw t1, 4(sp)
    lw t2, 8(sp)
    lw t3, 12(sp)
    lw t4, 16(sp)
    lw t5, 20(sp)
    lw ra, 24(sp)
    addi sp, sp, 28

    mret

// Random Number Generator Subroutine
RandomNum:
    addi sp, sp, -16
    sw ra, 12(sp)

    li s4, 0x8000
    and t1, a7, s4
    li s4, 0x2000
    and t3, a7, s4

    slli t3, t3, 2
    xor t3, t1, t3
    li s4, 0x1000
    and t1, a7, s4

    slli t1, t1, 3
    xor t3, t3, t1
    andi t1, a7, 0x0400
    slli t1, t1, 5
    xor t3, t3, t1
    srli t3, t3, 15
    slli a7, a7, 1
    or a7, a7, t3

    lw ra, 12(sp)
    addi sp, sp, 16
    ret

// Delay Subroutine (100ms resolution)
// a0 holds the number of 100ms intervals to delay.
DELAY:
    addi sp, sp, -16
    sw ra, 12(sp)
    sw a0, 8(sp)
    sw t4, 4(sp)

DELAY_CYCLE:
    li t4, 0xC3500   // Approximately 800K cycles for 100ms (adjust if necessary)
CYCLE_COUNTDOWN:
    addi t4, t4, -1
    bnez t4, CYCLE_COUNTDOWN
    addi a0, a0, -1
    bnez a0, DELAY_CYCLE

    lw t4, 4(sp)
    lw a0, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret

// Display Number Subroutine
// Assumes t0 holds the number to be displayed.
DISPLAY_NUM:
    addi sp, sp, -16     // Create space on the stack
    sw ra, 12(sp)        // Save return address
    sw t0, 8(sp)
    sw t4, 4(sp)
    sw t5, 0(sp)

    // Shift and mask to position the binary number on the LED bar
    slli t0, t0, 10      // Shift left by 10 bits
    li t5, 0x0           // Clear mask register
    li t4, 0xC00         // Mask for bits 10 and 11
    and t5, t0, t4       // Extract lower LED bits into t5
    slli t0, t0, 6       // Shift left again by 6 bits
    li t4, 0xFC0000      // Mask for upper LED bits
    and t0, t0, t4       // Extract upper LED bits into t0
    or t5, t5, t0        // Combine both portions

    // Output the final pattern to the LED registers
    li t0, GPIO_BASE
    sw t5, GPIO_OUTPUT(t0)

    lw t4, 4(sp)         // Restore registers
    lw t5, 0(sp)
    lw t0, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16
    ret
