// Struct containing the return status of OpenSBI
pub const SbiRet = struct {
    sbi_error: isize,
    value: isize,
};

pub fn debug_print(message: []const u8) SbiRet {
    var err: isize = undefined;
    var val: isize = undefined;

    const msg_ptr = @intFromPtr(message.ptr);
    const msg_len = message.len;

    asm volatile (
        \\mv a0, %[len]
        \\mv a1, %[msg]
        \\li a2, 0
        \\li a6, 0x00
        \\li a7, 0x4442434E
        \\ecall
        \\mv %[err], a0
        \\mv %[val], a1
        : [err] "=r" (err),
          [val] "=r" (val),
        : [msg] "r" (msg_ptr),
          [len] "r" (msg_len),
        : .{ .x10 = true, .x11 = true, .x12 = true, .x16 = true, .x17 = true, .memory = true });

    return SbiRet{
        .sbi_error = err,
        .value = val,
    };
}
