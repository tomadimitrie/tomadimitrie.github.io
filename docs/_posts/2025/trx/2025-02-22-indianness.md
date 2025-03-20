---
title: indianness
categories: ["ctf", "TRX CTF 2025"]
tags: ["reverse"]
media_subpath: "/assets/posts/2025/trx/indianness"
---

This is a VM which takes the bytecode and the flag as inputs and runs the program with the flag as an argument.

The operations are implemented as big switch statements, and each instruction has an opcode, which has multiple modes.
Each mode changes the operand types of the instruction. An example is:

![](1.png)

We can emulate all instructions in Python (or just the relevant ones that our bytecode uses, anyway):

```py
with open("bytecode.bin", "rb") as file:
    bytecode = file.read()

class Memory:
    def __init__(self, size):
        self.buffer = [0] * size

    def __getitem__(self, index):
        if index >= 256:
            print(f"Accessing flag index {index - 256}")
            print(f"Registers dump: ")
            print("-------------------")
            for index_, register in enumerate(registers):
                print(f"r{index_}. {register}")
            print("-------------------")
            global flag_access_index
            flag_access_index = index - 256
        return self.buffer[index]

    def __setitem__(self, index, item):
        self.buffer[index] = item
      

registers = [0] * 8
memory = Memory(286)
cursor = 0
equal_flag = False
count = 0
flag = ["?"] * 30
flag_access_register = None
flag_access_index = None
flag_access_xor_value = None

while cursor < len(bytecode):
    opcode = bytecode[cursor]
    count += 1
    try:
        mode = bytecode[cursor + 1]
    except IndexError:
        mode = None

    try:
        operand1 = bytecode[cursor + 2]
    except IndexError:
        operand1 = None

    try:
        operand2 = bytecode[cursor + 3]
    except IndexError:
        operand2 = None
    # print(f"[{count}] {cursor} ({opcode}:{mode}, {operand1}, {operand2}). ", end="")
    match opcode:
        case 0:
            match mode: 
                case 0:
                    print(f"add r{operand1}, r{operand2}")
                    registers[operand1] += registers[operand2]
                    registers[operand1] &= 0xff
                    cursor += 4
                case 5:
                    print(f"add r{operand1}, {operand2}")
                    registers[operand1] += operand2
                    registers[operand1] &= 0xff
                    cursor += 4
                case 7:
                    print(f"add r{operand1}, [r{operand2}]")
                    registers[operand1] += memory[registers[operand2]]
                    registers[operand1] &= 0xff
                    cursor += 4
                case _:
                    raise Exception(f"Unknown mode {mode} for opcode {opcode}")
        case 8:
            match mode: 
                case 12:
                    print(f"xor r{operand1}, flag[{operand2}]")
                    xor_value = memory[operand2 + 256]
                    if flag_access_index is not None:
                        flag_access_register = operand1
                        flag_access_xor_value = registers[operand1]
                    registers[operand1] ^= xor_value
                    cursor += 4
                case _:
                    raise Exception(f"Unknown mode {mode} for opcode {opcode}")
        case 9:
            match mode: 
                case 0:
                    print(f"mov r{operand1}, r{operand2}")
                    registers[operand1] = registers[operand2]
                    cursor += 4
                case 2:
                    print(f"mov [{operand1}], [r{operand2}]")
                    memory[operand1] = memory[registers[operand2]]
                    cursor += 4
                case 4:
                    print(f"mov [r{operand1}], [r{operand2}]")
                    memory[registers[operand1]] = memory[registers[operand2]]
                    cursor += 4
                case 5:
                    print(f"mov r{operand1}, {operand2}")
                    registers[operand1] = operand2
                    cursor += 4
                case 6:
                    print(f"mov r{operand1}, [{operand2}]")
                    registers[operand1] = memory[operand2]
                    cursor += 4
                case 7:
                    print(f"mov r{operand1}, [r{operand2}]")
                    registers[operand1] = memory[registers[operand2]]
                    cursor += 4
                case 8:
                    print(f"mov [{operand1}], {operand2}")
                    memory[operand1] = operand2
                    cursor += 4
                case 11:
                    print(f"mov [r{operand1}], r{operand2}")
                    memory[registers[operand1]] = registers[operand2]
                    cursor += 4
                case _:
                    raise Exception(f"Unknown mode {mode} for opcode {opcode}")
        case 10:
            match mode:
                case 5:
                    print(f"cmp r{operand1}, {operand2}")
                    print(operand1, flag_access_register)
                    assert operand1 == flag_access_register
                    print(flag_access_index)
                    flag[flag_access_index] = chr(flag_access_xor_value ^ operand2)
                    flag_access_index = None
                    flag_access_xor_value = None
                    flag_access_register = None
                    equal_flag = (registers[operand1] == operand2) & equal_flag
                    cursor += 4
                case _:
                    raise Exception(f"Unknown mode {mode} for opcode {opcode}")
        case 11:
            print(f"{equal_flag = }")
            cursor += 1
        case _:
            raise Exception(f"invalid opcode {opcode}")


print("".join(flag))
```
