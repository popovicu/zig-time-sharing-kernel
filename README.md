# Zig time sharing OS kernel

**This repo is meant to accompany the article at https://popovicu.com/posts/writing-an-operating-system-kernel-from-scratch/**

## Building

This should be as simple as:

```
zig build
```

To build the kernel in an extremely verbose mode, build like this:

```
zig build -Ddebug-logs=true
```

Run the kernel in RISC-V QEMU like this:

```
qemu-system-riscv64 -machine virt -nographic -bios /tmp/opensbi/build/platform/generic/firmware/fw_dynamic.bin -kernel zig-out/bin/kernel
```

The `-bios` path to OpenSBI should point where you built it on your machine. Building OpenSBI from source is highly encouraged. Please check the article for more pointers on building OpenSBI.

The output should be something like this:

```
Booting the kernel...
Printing from thread ID: 0
Printing from thread ID: 0
Printing from thread ID: 0
Printing from thread ID: 1
Printing from thread ID: 1
Printing from thread ID: 1
Printing from thread ID: 2
Printing from thread ID: 2
Printing from thread ID: 2
Printing from thread ID: 0
Printing from thread ID: 0
Printing from thread ID: 1
Printing from thread ID: 1
Printing from thread ID: 2
Printing from thread ID: 2
Printing from thread ID: 0
Printing from thread ID: 0
Printing from thread ID: 0
Printing from thread ID: 1
Printing from thread ID: 1
Printing from thread ID: 1
Printing from thread ID: 2
Printing from thread ID: 2
Printing from thread ID: 2
```
