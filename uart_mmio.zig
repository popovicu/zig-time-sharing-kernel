// UART MMIO address (standard for QEMU virt machine)
pub const UART_BASE: usize = 0x10000000;
pub const UART_TX: *volatile u8 = @ptrFromInt(UART_BASE);

// Direct UART write function (fallback when SBI is not available)
pub fn uart_write_string(message: []const u8) void {
    for (message) |byte| {
        UART_TX.* = byte;
    }
}
