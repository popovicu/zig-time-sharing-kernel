const sbi = @import("sbi");
const std = @import("std");
const context = @import("context");
const uart = @import("uart_mmio");
const syscall = @import("syscall");

// This file is mostly AI generated :)

/// Configuration constants
pub const MAX_THREADS = 16;
pub const STACK_SIZE = 8192; // 8 KB per thread stack

/// Thread states
pub const ThreadState = enum(u8) {
    /// Slot is free for allocation
    free,
    /// Thread is ready to run
    ready,
    /// Thread is currently running
    running,
    /// Thread is blocked waiting for something
    blocked,
    /// Thread has terminated
    terminated,
};

// Thread control block
pub const Thread = struct {
    /// Unique thread identifier
    id: u32,

    /// Thread state
    state: ThreadState,

    /// Index into the global stack array
    stack_index: u8,

    /// Thread priority (if implementing priority scheduling)
    priority: u8,

    /// Time slice remaining (for round-robin scheduling)
    time_slice: u32,

    /// Saved stack pointer for context switching
    sp_save: usize,
};

/// Static memory pools for threads and stacks
pub const ThreadPool = struct {
    /// Pre-allocated thread control blocks
    threads: [MAX_THREADS]Thread,

    /// Pre-allocated stacks for all threads
    /// Each stack is STACK_SIZE bytes, aligned to 16 bytes
    stacks: [MAX_THREADS][STACK_SIZE]u8 align(16),

    /// Simple free list implemented as a bitfield
    /// Bit i is 1 if thread slot i is in use
    used_mask: u16,

    /// Currently running thread index (MAX_THREADS means none)
    current_thread: u8,

    /// Ready queue - circular buffer of thread indices
    ready_queue: struct {
        buffer: [MAX_THREADS]u8,
        head: u8,
        tail: u8,
        count: u8,
    },
};

/// Global thread pool - statically allocated
pub var thread_pool: ThreadPool = initThreadPool();

fn initThreadPool() ThreadPool {
    var pool: ThreadPool = undefined;

    // Initialize all threads as free
    for (&pool.threads, 0..) |*thread, i| {
        thread.* = Thread{
            .id = @intCast(i),
            .state = .free,
            .stack_index = @intCast(i),
            .priority = 0,
            .time_slice = 0,
            .sp_save = 0, // Initialize sp_save
        };
    }

    // Clear the stacks (optional, helps with debugging)
    for (&pool.stacks) |*stack| {
        @memset(stack, 0);
    }

    pool.used_mask = 0;
    pool.current_thread = MAX_THREADS; // No thread running

    // Initialize ready queue
    pool.ready_queue = .{
        .buffer = undefined,
        .head = 0,
        .tail = 0,
        .count = 0,
    };

    return pool;
}

// Allocate a new thread from the pool
pub fn allocThread() ?*Thread {
    // Find first free slot
    var i: u8 = 0;
    while (i < MAX_THREADS) : (i += 1) {
        const mask = @as(u16, 1) << @intCast(i);
        if ((thread_pool.used_mask & mask) == 0) {
            // Found free slot
            thread_pool.used_mask |= mask;
            thread_pool.threads[i].state = .ready;
            return &thread_pool.threads[i];
        }
    }
    return null; // No free threads
}

/// Free a thread back to the pool
pub fn freeThread(thread: *Thread) void {
    const index = thread.id;
    const mask = @as(u16, 1) << @intCast(index);

    thread.state = .free;
    thread_pool.used_mask &= ~mask;
}

/// Get the stack for a thread
pub fn getThreadStack(thread: *Thread) []u8 {
    return &thread_pool.stacks[thread.stack_index];
}

/// Initialize a thread's context
pub fn initThread(
    thread: *Thread,
    entry_point: usize,
    arg: usize,
) void {
    const stack = getThreadStack(thread);

    // Stack grows down, so start at the top of the allocated stack space.
    // The context frame is CONTEXT_FRAME_SIZE bytes.
    // The stack pointer will point to the bottom of this frame.
    var sp: usize = @intFromPtr(&stack[STACK_SIZE]);
    sp -= context.CONTEXT_FRAME_SIZE; // Allocate space for the context frame

    // Store the initial stack pointer in the thread control block
    thread.sp_save = sp;

    // Pre-populate the stack with initial register values
    // Offsets match the s_mode_interrupt_handler_naked prologue/epilogue in kernel.zig

    // General purpose registers (x1-x31)
    // x1 (ra) should point to thread_exit
    @as(*usize, @ptrFromInt(sp + context.X1_OFFSET)).* = @intFromPtr(&thread_exit);
    // x10 (a0) should hold the argument
    @as(*usize, @ptrFromInt(sp + context.X10_OFFSET)).* = arg;
    // Other GPRs can be initialized to 0 (already done by @memset in initThreadPool)

    // S-level CSRs
    // sstatus: Supervisor mode, interrupts enabled (SPIE), previous privilege mode to User (SPP=0), SUM=1
    const SSTATUS_SPP_USER = @as(usize, 0); // Previous Privilege Mode: User
    const SSTATUS_SPIE = @as(usize, 1) << 5; // Supervisor Previous Interrupt Enable
    const SSTATUS_SUM = @as(usize, 1) << 18; // Permit Supervisor User Memory access
    @as(*usize, @ptrFromInt(sp + context.SSTATUS_OFFSET)).* = SSTATUS_SPP_USER | SSTATUS_SPIE | SSTATUS_SUM;

    // sepc: Entry point of the thread
    @as(*usize, @ptrFromInt(sp + context.SEPC_OFFSET)).* = entry_point;

    // scause: 0 (no specific cause for a new thread)
    @as(*usize, @ptrFromInt(sp + context.SCAUSE_OFFSET)).* = 0;

    // stval: 0 (no specific fault value)
    @as(*usize, @ptrFromInt(sp + context.STVAL_OFFSET)).* = 0;
}

/// Function to call when a thread's entry_point returns
fn thread_exit() noreturn {
    // For now, just loop indefinitely or panic
    std.debug.panic("Thread exited unexpectedly!", .{});
}

/// Add thread to ready queue
pub fn enqueueReady(thread: *Thread) void {
    const q = &thread_pool.ready_queue;
    if (q.count >= MAX_THREADS) return; // Queue full

    q.buffer[q.tail] = @intCast(thread.id);
    q.tail = (q.tail + 1) % MAX_THREADS;
    q.count += 1;
    thread.state = .ready;
}

/// Get next thread from ready queue
pub fn dequeueReady() ?*Thread {
    const q = &thread_pool.ready_queue;
    if (q.count == 0) return null;

    const thread_id = q.buffer[q.head];
    q.head = (q.head + 1) % MAX_THREADS;
    q.count -= 1;

    return &thread_pool.threads[thread_id];
}

/// Get currently running thread
pub fn getCurrentThread() ?*Thread {
    if (thread_pool.current_thread >= MAX_THREADS) return null;
    return &thread_pool.threads[thread_pool.current_thread];
}

/// Set currently running thread
pub fn setCurrentThread(thread: ?*Thread) void {
    if (thread) |t| {
        thread_pool.current_thread = @intCast(t.id);
        t.state = .running;
    } else {
        thread_pool.current_thread = MAX_THREADS;
    }
}

/// Example: Create a simple printing thread
pub fn createPrintingThread(thread_number: usize) !*Thread {
    const thread = allocThread() orelse return error.NoFreeThreads;

    const print_fn = struct {
        fn print(thread_arg: usize) noreturn {
            while (true) {
                var buffer: [256]u8 = undefined;
                const content = std.fmt.bufPrint(&buffer, "Printing from thread ID: {d}\n", .{thread_arg}) catch {
                    continue;
                };

                syscall.debug_print(content);

                // Simulate a delay
                var i: u32 = 0;
                while (i < 300000000) : (i += 1) {
                    asm volatile ("" ::: .{ .memory = true }); // Memory barrier to prevent optimization
                }
            }
            unreachable;
        }
    }.print;

    initThread(thread, @intFromPtr(&print_fn), thread_number);
    return thread;
}
