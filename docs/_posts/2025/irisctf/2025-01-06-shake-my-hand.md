---
title: Shake my hand
description: A great way to start a conversation is with a handshake.
categories: ["ctf", "IrisCTF 2025"]
tags: ["networking"]
media_subpath: "/assets/posts/2025/irisctf/shake-my-hand"
---

We are given a server to connect via `netcat`:
![](01.png)

We can send packets using `emit` and receive packets using `recv`.

We know our IP and the challenge IP and port. Given the challenge name, we must complete a TCP handshake.

The easiest way to do so is by using `scapy`. I also used `pwntools` for communication.

Helper functions will be provided at the end of the post, in the final exploit script.

In order to send a TCP packet, first you have to create an IP packet:

```py
ip = IP(
    src=my_ip,
    dst="192.168.1.10",
    frag=0
)
```

The first component in a TCP handshake is the initial SYN packet. The client (us) sends a packet with the SYN flag.
In `scapy`, this is done with the `/` operator between an IP packet and a TCP packet:

```py
syn = ip / TCP(
    sport=1234,
    dport=9999,
    flags="S",
    seq=1000,
)
```

The server responded with a SYN-ACK packet (packet displayed using the `.display()` function in `scapy`):

![](02.png)

Note the flags being set to S (SYN) and A (ACK).

Now we have to complete the handshake by sending an ACK packet:

```py
ack = ip / TCP(
    sport=1234,
    dport=9999,
    flags="A",
    seq=syn_ack[TCP].ack,
    ack=syn_ack[TCP].seq + 1
)
```

However, we need to pay attention to the `syn` and `ack` fields.
`syn` needs to be set to the `ack` of the SYN-ACK packet, and `ack` needs to be
set to the `seq` of the SYN-ACK packet, plus one.

Immediately after we completed the handshake, if we `recv` again we receive something from the server:

![](03.png)

The server asks us if we want to print the flag.
Before responding, we have to make sure we have ack-ed the question packet.

```py
question_ack = ip / TCP(
    sport=1234,
    dport=9999,
    flags="A",
    seq=server_question[TCP].ack,
    ack=server_question[TCP].seq + len(server_question[TCP].payload)
)
```

`seq` needs to be set to the last packet's `ack`, and `ack` needs to be set to the last packet's `seq`,
while also adding the length of the data in the packet.

After this, we can actually send our response and wait for the server to reply. This packet has to have the
`ACK` and `PUSH` flags set. The `seq` and `ack` are the same as for the packet where we ack-ed the question.
This time, they are not reversed. `syn` is actually last packet's `syn`, and same for `ack`.

```py
data = ip / TCP(
    sport=1234,
    dport=9999,
    flags="PA",
    seq=question_ack[TCP].seq,
    ack=question_ack[TCP].ack
) / Raw("yes")
```

We got the flag:

![](04.png)


Final exploit script:
```py
from scapy.all import IP, TCP, Raw, raw, sr1
from base64 import b64encode, b64decode
from pwn import remote, context, log
import re
import time


# context.log_level = 'debug'


def send_packet(packet):
    packet.display()
    packet = raw(packet)
    packet = b64encode(packet).decode()
    io.sendline(f"emit {packet}".encode())
    io.recvuntil(b"> ")
    io.clean()


def receive_packet():
    io.sendline(b"recv")
    data = io.recvuntil(b"> ")
    io.clean()
    if b"empty" in data:
        log.info("no packet, trying again...")
        receive_packet()
        return
    packet = data.split(b"\n")[1].strip()
    log.success(f"Received packet: {packet}")
    packet = IP(b64decode(packet))
    packet.display()
    return packet


io = remote("shake-my-hand.chal.irisc.tf", 10501)
text = io.recvuntil(b"> ").decode()
io.clean()
my_ip = re.search(r"Your IP: (\d+\.\d+\.\d+\.\d+)", text).group(1)
log.success(f"{my_ip = }")

ip = IP(
    src=my_ip,
    dst="192.168.1.10",
    frag=0
)

syn = ip / TCP(
    sport=1234,
    dport=9999,
    flags="S",
    seq=1000,
)
print("Sending syn...")
send_packet(syn)

print("Receiving syn-ack...")
syn_ack = receive_packet()

ack = ip / TCP(
    sport=1234,
    dport=9999,
    flags="A",
    seq=syn_ack[TCP].ack,
    ack=syn_ack[TCP].seq + 1
)
print("Sending ack...")
send_packet(ack)

print("Getting server question...")
server_question = receive_packet()

question_ack = ip / TCP(
    sport=1234,
    dport=9999,
    flags="A",
    seq=server_question[TCP].ack,
    ack=server_question[TCP].seq + len(server_question[TCP].payload)
)
print("Sending question ack...")
send_packet(question_ack)

data = ip / TCP(
    sport=1234,
    dport=9999,
    flags="PA",
    seq=question_ack[TCP].seq,
    ack=question_ack[TCP].ack
) / Raw("yes")
print("Sending answer...")
send_packet(data)

server_response = receive_packet()

io.interactive()
```
