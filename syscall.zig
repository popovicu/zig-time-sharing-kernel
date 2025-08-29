// User-level debug_print function
pub fn debug_print(message: []const u8) void {
    const msg_ptr = @intFromPtr(message.ptr);
    const msg_len = message.len;

    // Let's say syscall number 64
    // a7 = syscall number
    // a0 = message pointer
    // a1 = message length
    asm volatile (
        \\mv a0, %[msg]
        \\mv a1, %[len]
        \\li a7, 64
        \\ecall
        :
        : [msg] "r" (msg_ptr),
          [len] "r" (msg_len),
        : .{ .x10 = true, .x11 = true, .x17 = true, .memory = true });

    // Ignore return value for simplicity
}
