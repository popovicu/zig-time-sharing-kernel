pub fn setup_s_mode_interrupt(handler_ptr: *const fn () callconv(.naked) void) void {
    asm volatile (
        \\csrw stvec, %[handler]
        \\csrsi sstatus, 2
        :
        : [handler] "r" (@intFromPtr(handler_ptr)),
        : .{ .memory = true });
}
