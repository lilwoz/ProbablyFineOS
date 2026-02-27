// =============================================================
// ProbablyFineOS — Kernel Panic Handler
// Exception handler for CPU exceptions 0-31
// =============================================================

#include <stdint.h>

// External functions (from vga.asm)
extern void vga_puts(const char* str);
extern void vga_print_hex(uint32_t value);
extern void vga_set_color(uint8_t attr);
extern void freeze(void);

// VGA colors
#define VGA_RED     0x04
#define VGA_WHITE   0x0F
#define VGA_LRED    0x0C

// Register frame (from pushad + push_segs)
struct registers {
    uint32_t gs, fs, es, ds;                // Segment registers
    uint32_t edi, esi, ebp, esp, ebx, edx, ecx, eax; // General purpose (pushad order)
};

// Exception names
static const char* exception_names[] = {
    "Divide by Zero",
    "Debug",
    "Non-Maskable Interrupt",
    "Breakpoint",
    "Overflow",
    "Bound Range Exceeded",
    "Invalid Opcode",
    "Device Not Available",
    "Double Fault",
    "Coprocessor Segment Overrun",
    "Invalid TSS",
    "Segment Not Present",
    "Stack-Segment Fault",
    "General Protection Fault",
    "Page Fault",
    "(Reserved)",
    "x87 FPU Error",
    "Alignment Check",
    "Machine Check",
    "SIMD Floating-Point Exception",
    "(Reserved)", "(Reserved)", "(Reserved)", "(Reserved)",
    "(Reserved)", "(Reserved)", "(Reserved)", "(Reserved)",
    "(Reserved)", "(Reserved)", "(Reserved)", "(Reserved)"
};

// Simple integer to string (hex)
static void print_hex_value(const char* label, uint32_t value) {
    vga_puts(label);
    vga_print_hex(value);
    vga_puts("\n");
}

// Exception handler (called from exception_common in exceptions.asm)
void exception_handler(uint32_t exc_num, uint32_t error_code, uint32_t eip, struct registers* regs) {
    // Set red background for panic
    vga_set_color((VGA_RED << 4) | VGA_WHITE);

    vga_puts("\n*** KERNEL PANIC ***\n");

    // Print exception name
    vga_puts("Exception: ");
    if (exc_num < 32) {
        vga_puts(exception_names[exc_num]);
    } else {
        vga_puts("Unknown");
    }
    vga_puts("\n\n");

    // Print exception details
    print_hex_value("Exception Number: 0x", exc_num);
    print_hex_value("Error Code:       0x", error_code);
    print_hex_value("EIP:              0x", eip);

    // For page fault, read CR2 (faulting address)
    if (exc_num == 14) {
        uint32_t cr2;
        __asm__ volatile("mov %0, cr2" : "=r"(cr2));
        print_hex_value("CR2 (fault addr): 0x", cr2);

        // Decode page fault error code
        vga_puts("Page fault: ");
        if (error_code & 0x01) vga_puts("Present ");
        else vga_puts("Not-present ");
        if (error_code & 0x02) vga_puts("Write ");
        else vga_puts("Read ");
        if (error_code & 0x04) vga_puts("User-mode");
        else vga_puts("Kernel-mode");
        vga_puts("\n");
    }

    // Print register dump
    vga_puts("\nRegisters:\n");
    print_hex_value("  EAX=0x", regs->eax);
    print_hex_value("  EBX=0x", regs->ebx);
    print_hex_value("  ECX=0x", regs->ecx);
    print_hex_value("  EDX=0x", regs->edx);
    print_hex_value("  ESI=0x", regs->esi);
    print_hex_value("  EDI=0x", regs->edi);
    print_hex_value("  EBP=0x", regs->ebp);
    print_hex_value("  ESP=0x", regs->esp);

    vga_puts("\nSegments:\n");
    print_hex_value("  CS:  0x", eip >> 16);  // CS from stack
    print_hex_value("  DS:  0x", regs->ds);
    print_hex_value("  ES:  0x", regs->es);
    print_hex_value("  FS:  0x", regs->fs);
    print_hex_value("  GS:  0x", regs->gs);

    vga_puts("\nSystem halted.\n");

    // Freeze (cli + hlt loop)
    freeze();
}
