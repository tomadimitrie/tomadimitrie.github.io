---
title: Trapped in Plain Sight 2
description: |
  Only the chosen may see.

  The password is password.

  by Caleb (@eden.caleb.a on discord)
  ssh -p 4302 trapped@challenge.utctf.live 
categories: ["ctf", "UTCTF 2025"]
tags: ["misc"]
media_subpath: "/assets/posts/2025/utctf/trapped-in-plain-sight-2"
---

We are given a SSH port we can connect to. We see a `start.sh` script that grants ACL permissions to a secret
user over the flag:

![](1.png)

We see that only root can read the file, but `secretuser` has special permissions:

![](2.png)

In `/etc/passwd` we see a potential password:

![](3.png)

We can `su` as this user and get the flag:

![](4.png)
