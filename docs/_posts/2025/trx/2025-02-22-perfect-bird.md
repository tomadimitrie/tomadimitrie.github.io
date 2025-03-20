---
title: perfect bird
categories: ["ctf", "TRX CTF 2025"]
tags: ["misc"]
media_subpath: "/assets/posts/2025/trx/perfect-bird"
---

This is a `dreamberd` script (renamed to `GulfOfMexico` at the time of writing): [https://github.com/TodePond/GulfOfMexico](https://github.com/TodePond/GulfOfMexico):

![](1.png)

There is no public interpreter for it, but the rules are explained on the repo's readme. The language is similar to
JavaScript, so we can just write a script that converts it to valid JavaScript.

```py
import re

with open("chall.db3") as file:
    lines = file.readlines()

variables = {}

found_lifetime = True
while found_lifetime:
    for index, line in enumerate(lines):
        lifetime_declaration = re.search(r"<(\S+)>", line)
        if lifetime_declaration is None:
            found_lifetime = False
        else:
            found_lifetime = True
            lifetime = lifetime_declaration.group(1)
            line = re.sub(r"<(\S+)>", "", line)
            lines.pop(index)
            if lifetime == "Infinity":
                lines.insert(0, line)
            else:
                lines.insert(max(0, index + int(lifetime)), line)
            break
 
for i in range(len(lines)):
    line = lines[i]

    replace = {
        "!": "",
        "var var": "var",
        "functi main () => {": "function main() {",
        "const var": "var",
        "const const const": "var",
        "print(m)": "console.log(m)\nconsole.log(String.fromCharCode(...m))",
    }
    for key, value in replace.items():
        line = line.replace(key, value)

    variable_declaration = re.search(r"var (\d+)", line)
    if variable_declaration is not None:
        name = variable_declaration.group(1)
        variables[name] = "_" + name

    for key, value in variables.items():
        line = re.sub(f"(?<!0x){key}", value, line)

    subscript_declaration = re.search(r"(\S+)\[(\S+)\]", line)
    if subscript_declaration is not None:
        array = subscript_declaration.group(1)
        subscript = subscript_declaration.group(2)
        line = re.sub(r"(\S+)\[(\S+)\]", f"{array}[{subscript} + 1]", line)

    semicolons = line.count(";")
    if semicolons % 2 == 1:
        line = line.replace(";" * semicolons, "!")
    else:
        line = line.replace(";" * semicolons, "")


    lines[i] = line

print(variables)

with open("out.js", "w") as file:
    for line in lines:
        file.write(line)
    file.write("main()")
```
