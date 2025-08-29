const std = @import("std");

pub fn build(b: *std.Build) void {
    // Define the target
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .riscv64,
        .os_tag = .freestanding,
        .abi = .none,
    });

    const optimize = .ReleaseSmall;

    // Create the executable
    const exe = b.addExecutable(.{
        .name = "kernel",
        .root_module = b.createModule(.{
            .root_source_file = b.path("kernel.zig"),
            .target = target,
            .optimize = optimize,
            .strip = false, // -fno-strip equivalent
            .code_model = .medium, // -mcmodel=medium
        }),
    });

    const enable_debug_logs = b.option(bool, "debug-logs", "Enable debug logging") orelse false;
    const options = b.addOptions();
    options.addOption(bool, "enable_debug_logs", enable_debug_logs);
    const build_options_module = options.createModule();

    // Create modules that don't have dependencies first
    const sbi_module = b.createModule(.{
        .root_source_file = b.path("sbi.zig"),
        .optimize = optimize,
    });

    const thread_module = b.createModule(.{
        .root_source_file = b.path("thread.zig"),
        .optimize = optimize,
    });

    const uart_mmio_module = b.createModule(.{
        .root_source_file = b.path("uart_mmio.zig"),
        .optimize = optimize,
    });

    const interrupts_module = b.createModule(.{
        .root_source_file = b.path("interrupts.zig"),
        .optimize = optimize,
    });

    const context_module = b.createModule(.{
        .root_source_file = b.path("context.zig"),
        .optimize = optimize,
    });

    // Create timer module with sbi as a dependency
    const timer_module = b.createModule(.{
        .root_source_file = b.path("timer.zig"),
        .optimize = optimize,
    });
    timer_module.addImport("sbi", sbi_module);

    const scheduling_module = b.createModule(.{
        .root_source_file = b.path("scheduling.zig"),
        .optimize = optimize,
    });
    scheduling_module.addImport("sbi", sbi_module);
    scheduling_module.addImport("thread", thread_module);
    scheduling_module.addImport("build_options", build_options_module);

    const syscall_module = b.createModule(.{
        .root_source_file = b.path("syscall.zig"),
        .optimize = optimize,
    });

    // Add all imports to the main executable
    exe.root_module.addImport("thread", thread_module);
    exe.root_module.addImport("sbi", sbi_module);
    exe.root_module.addImport("uart_mmio", uart_mmio_module);
    exe.root_module.addImport("interrupts", interrupts_module);
    exe.root_module.addImport("timer", timer_module);
    exe.root_module.addImport("scheduling", scheduling_module);
    exe.root_module.addImport("context", context_module);
    exe.root_module.addImport("build_options", build_options_module);
    thread_module.addImport("sbi", sbi_module);
    thread_module.addImport("context", context_module);
    thread_module.addImport("uart_mmio", uart_mmio_module);
    thread_module.addImport("syscall", syscall_module);

    // Add the assembly source file
    exe.addAssemblyFile(b.path("startup.S"));

    // Set the linker script
    exe.setLinkerScript(b.path("linker.ld"));

    // Install the executable
    b.installArtifact(exe);
}
