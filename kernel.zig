const interrupts = @import("interrupts");
const std = @import("std");
const sbi = @import("sbi");
const scheduling = @import("scheduling");
const thread = @import("thread");
const timer = @import("timer");
const uart = @import("uart_mmio");
const context = @import("context");
const build_options = @import("build_options");

const BOOT_MSG = "Booting the kernel...\n";

const InterruptSource = enum {
    Timer,
    EcallFromUser,
    EcallFromSupervisor,
    Unknown,
};

export fn handle_kernel(current_stack: usize) usize {
    // Current stack is the stack top prior to this function.
    //
    // Returns the new stack to restore to, which may or may not be the same.

    const scause = asm volatile ("csrr %[ret], scause"
        : [ret] "=r" (-> usize),
    );

    // Check if it's an interrupt (MSB set) or exception
    const is_interrupt = (scause >> (@bitSizeOf(usize) - 1)) != 0;
    const cause_code = scause & ~(@as(usize, 1) << (@bitSizeOf(usize) - 1));

    const interrupt_source = blk: {
        if (is_interrupt) {
            // S-mode interrupt codes
            if (cause_code == 5) {
                break :blk InterruptSource.Timer; // Supervisor timer interrupt
            }
            break :blk InterruptSource.Unknown;
        }

        // Exception codes - check for ecalls
        switch (cause_code) {
            8 => break :blk InterruptSource.EcallFromUser, // Environment call from U-mode
            9 => break :blk InterruptSource.EcallFromSupervisor, // Environment call from S-mode
            else => break :blk InterruptSource.Unknown,
        }
    };

    if (comptime build_options.enable_debug_logs) {
        var buffer: [256]u8 = undefined;
        const interrupt_name = switch (interrupt_source) {
            .Timer => "Timer",
            .EcallFromUser => "Ecall from User mode",
            .EcallFromSupervisor => "Ecall from Supervisor mode",
            .Unknown => "Unknown",
        };
        const content = std.fmt.bufPrint(&buffer, "Interrupt source: {s}, Current stack: {x}\n", .{ interrupt_name, current_stack }) catch {
            return 0; // Return bogus stack, should be more robust in reality
        };
        _ = sbi.debug_print(content);
    }

    // Handle based on interrupt source
    switch (interrupt_source) {
        .Timer => {
            timer.clear_timer_pending_bit();
            const new_stack = scheduling.schedule(current_stack);
            _ = timer.set_timer_in_near_future();
            return new_stack;
        },
        .EcallFromUser => {
            // Read syscall number and arguments from saved registers
            const syscall_num = @as(*usize, @ptrFromInt(current_stack + context.X17_OFFSET)).*;
            const arg0 = @as(*usize, @ptrFromInt(current_stack + context.X10_OFFSET)).*;
            const arg1 = @as(*usize, @ptrFromInt(current_stack + context.X11_OFFSET)).*;

            // Handle the syscall
            const result = switch (syscall_num) {
                64 => blk: { // Printing system call
                    // arg0 = message pointer, arg1 = message length
                    const msg_ptr = @as([*]const u8, @ptrFromInt(arg0));
                    const msg_len = arg1;

                    // Validate length (basic sanity check)
                    if (msg_len > 1024) {
                        _ = sbi.debug_print("Error: Message too long\n");
                        break :blk @as(usize, @bitCast(@as(isize, -1)));
                    }

                    // Print the user's message
                    const message = msg_ptr[0..msg_len];
                    _ = sbi.debug_print(message);

                    break :blk msg_len; // Return number of bytes printed
                },
                else => blk: {
                    // Unknown syscall
                    var buffer: [128]u8 = undefined;
                    const content = std.fmt.bufPrint(&buffer, "Unknown syscall: {} from user mode\n", .{syscall_num}) catch {
                        return 0; // Return bogus stack, should be more robust in reality
                    };
                    _ = sbi.debug_print(content);
                    break :blk @as(usize, @bitCast(@as(isize, -38))); // -ENOSYS, I guess?
                },
            };

            // Store return value in a0
            @as(*usize, @ptrFromInt(current_stack + context.X10_OFFSET)).* = result;

            // Increment SEPC to skip the ecall instruction
            @as(*usize, @ptrFromInt(current_stack + context.SEPC_OFFSET)).* += 4;

            return current_stack;
        },
        .EcallFromSupervisor => {
            _ = sbi.debug_print("Supervisor mode ecall received, likely delegated from M-mode\n");

            @as(*usize, @ptrFromInt(current_stack + context.SEPC_OFFSET)).* += 4;
            return current_stack;
        },
        .Unknown => {
            if (comptime build_options.enable_debug_logs) {
                var buffer: [256]u8 = undefined;
                const desc = if (is_interrupt) "interrupt" else "exception";
                const content = std.fmt.bufPrint(&buffer, "Unknown {s}. scause: {x} (code: {})\n", .{ desc, scause, cause_code }) catch {
                    return 0; // Return bogus stack, should be more robust in reality
                };
                _ = sbi.debug_print(content);
            }

            // Unknown interrupts/exceptions might be critical errors
            // TODO: Consider panicking or handling specific cases here
            return current_stack;
        },
    }
}

export fn s_mode_interrupt_handler() align(16) linksection(".text.interrupt") callconv(.naked) void {
    // TODO: use the constants from the context module, don't hardcode here
    asm volatile (
    // Prologue: Save context
    // Allocate stack space.
        \\addi sp, sp, -288

        // Save general purpose registers x1-x31
        // x2 is sp.
        \\sd x1, 0(sp)
        \\sd x3, 8(sp)
        \\sd x4, 16(sp)
        \\sd x5, 24(sp)
        \\sd x6, 32(sp)
        \\sd x7, 40(sp)
        \\sd x8, 48(sp)
        \\sd x9, 56(sp)
        \\sd x10, 64(sp)
        \\sd x11, 72(sp)
        \\sd x12, 80(sp)
        \\sd x13, 88(sp)
        \\sd x14, 96(sp)
        \\sd x15, 104(sp)
        \\sd x16, 112(sp)
        \\sd x17, 120(sp)
        \\sd x18, 128(sp)
        \\sd x19, 136(sp)
        \\sd x20, 144(sp)
        \\sd x21, 152(sp)
        \\sd x22, 160(sp)
        \\sd x23, 168(sp)
        \\sd x24, 176(sp)
        \\sd x25, 184(sp)
        \\sd x26, 192(sp)
        \\sd x27, 200(sp)
        \\sd x28, 208(sp)
        \\sd x29, 216(sp)
        \\sd x30, 224(sp)
        \\sd x31, 232(sp)

        // Save S-level CSRs (using x5 as a temporary register)
        \\csrr x5, sstatus
        \\sd x5, 240(sp)
        \\csrr x5, sepc
        \\sd x5, 248(sp)
        \\csrr x5, scause
        \\sd x5, 256(sp)
        \\csrr x5, stval
        \\sd x5, 264(sp)

        // Call handle_kernel
        \\mv a0, sp
        \\call handle_kernel
        \\mv sp, a0

        // Epilogue: Restore context
        // Restore S-level CSRs (using x5 as a temporary register)
        \\ld x5, 264(sp)
        \\csrw stval, x5
        \\ld x5, 256(sp)
        \\csrw scause, x5
        \\ld x5, 248(sp)
        \\csrw sepc, x5
        \\ld x5, 240(sp)
        \\csrw sstatus, x5

        // Restore general purpose registers x1-x31
        \\ld x1, 0(sp)
        \\ld x3, 8(sp)
        \\ld x4, 16(sp)
        \\ld x5, 24(sp)
        \\ld x6, 32(sp)
        \\ld x7, 40(sp)
        \\ld x8, 48(sp)
        \\ld x9, 56(sp)
        \\ld x10, 64(sp)
        \\ld x11, 72(sp)
        \\ld x12, 80(sp)
        \\ld x13, 88(sp)
        \\ld x14, 96(sp)
        \\ld x15, 104(sp)
        \\ld x16, 112(sp)
        \\ld x17, 120(sp)
        \\ld x18, 128(sp)
        \\ld x19, 136(sp)
        \\ld x20, 144(sp)
        \\ld x21, 152(sp)
        \\ld x22, 160(sp)
        \\ld x23, 168(sp)
        \\ld x24, 176(sp)
        \\ld x25, 184(sp)
        \\ld x26, 192(sp)
        \\ld x27, 200(sp)
        \\ld x28, 208(sp)
        \\ld x29, 216(sp)
        \\ld x30, 224(sp)
        \\ld x31, 232(sp)

        // Deallocate stack space
        \\addi sp, sp, 288

        // Return from supervisor mode
        \\sret
        ::: .{ .memory = true });
}

export fn main() void {
    const initial_print_status = sbi.debug_print(BOOT_MSG);

    if (initial_print_status.sbi_error != 0) {
        // SBI debug console not available, fall back to direct UART
        const error_msg = "ERROR: OpenSBI debug console not available! You need the latest OpenSBI.\n";
        const fallback_msg = "Falling back to direct UART at 0x10000000...\n";

        uart.uart_write_string(error_msg);
        uart.uart_write_string(fallback_msg);
        uart.uart_write_string("Stopping... We rely on OpenSBI, cannot continue.\n");

        while (true) {
            asm volatile ("wfi");
        }

        unreachable;
    }

    if (comptime build_options.enable_debug_logs) {
        _ = sbi.debug_print("DEBUG mode on\n");
    }

    for (0..3) |i| {
        const print_thread_result = thread.createPrintingThread(i);

        if (print_thread_result) |print_thread| {
            thread.enqueueReady(print_thread);
        } else |_| {
            uart.uart_write_string("Cannot create print thread!!!...\n");
            while (true) {
                asm volatile ("wfi");
            }
        }
    }

    interrupts.setup_s_mode_interrupt(&s_mode_interrupt_handler);
    _ = timer.set_timer_in_near_future();
    timer.enable_s_mode_timer_interrupt();

    // TODO: don't just busy wait until the timer kicks in, yield right away.
    while (true) {
        asm volatile ("wfi");
    }

    unreachable;
}

pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    uart.uart_write_string("Panic!!!...\n");
    uart.uart_write_string(msg);

    // Halt
    while (true) {
        asm volatile ("wfi");
    }
}
