const sbi = @import("sbi");

pub fn set_timer_in_near_future() sbi.SbiRet {
    var err: isize = undefined;
    var val: isize = undefined;

    asm volatile (
        \\rdtime t0
        \\li t1, 10000000
        \\add a0, t0, t1
        \\li a6, 0x00
        \\li a7, 0x54494D45
        \\ecall
        \\mv %[err], a0
        \\mv %[val], a1
        : [err] "=r" (err),
          [val] "=r" (val),
        :
        : .{ .x5 = true, .x6 = true, .x10 = true, .x11 = true, .x16 = true, .x17 = true, .memory = true });

    return sbi.SbiRet{
        .sbi_error = err,
        .value = val,
    };
}

pub fn enable_s_mode_timer_interrupt() void {
    asm volatile (
        \\li t1, 32
        \\csrs sie, t1
        ::: .{ .x6 = true, .memory = true });
}

pub fn clear_timer_pending_bit() void {
    asm volatile (
        \\li t0, 32
        \\csrc sip, t0
        ::: .{ .x5 = true, .memory = true });
}
