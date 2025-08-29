const build_options = @import("build_options");
const sbi = @import("sbi");
const std = @import("std");
const thread = @import("thread");

pub fn schedule(current_stack: usize) usize {
    const maybe_current_thread = thread.getCurrentThread();

    if (maybe_current_thread) |current_thread| {
        current_thread.sp_save = current_stack;

        if (comptime build_options.enable_debug_logs) {
            _ = sbi.debug_print("[I] Enqueueing the current thread\n");
        }
        thread.enqueueReady(current_thread);
    } else {
        if (comptime build_options.enable_debug_logs) {
            _ = sbi.debug_print("[W] NO CURRENT THREAD AVAILABLE!\n");
        }
    }

    const maybe_new_thread = thread.dequeueReady();

    if (maybe_new_thread) |new_thread| {
        // TODO: software interrupt to yield to the user thread

        if (comptime build_options.enable_debug_logs) {
            _ = sbi.debug_print("Yielding to the new thread\n");
        }

        thread.setCurrentThread(new_thread);

        if (comptime build_options.enable_debug_logs) {
            var buffer: [256]u8 = undefined;
            const content = std.fmt.bufPrint(&buffer, "New thread ID: {d}, stack top: {x}\n", .{ new_thread.id, new_thread.sp_save }) catch {
                return 0; // Return bogus stack, should be more robust in reality
            };
            _ = sbi.debug_print(content);
        }

        return new_thread.sp_save;
    }

    _ = sbi.debug_print("NO NEW THREAD AVAILABLE!\n");

    while (true) {
        asm volatile ("wfi");
    }
    unreachable;
}
