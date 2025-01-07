---
title: webwebhookhook
description: I made a service to convert webhooks into webhooks.
categories: ["ctf", "IrisCTF 2025"]
tags: ["web"]
media_subpath: "/assets/posts/2025/irisctf/webwebhookhook"
---

We are given a Spring application written in Kotlin that allows us to create webhooks:

```kotlin
package tf.irisc.chal.webwebhookhook

import java.net.URI
import java.net.URL

class StateType(
    hook: String,
    var template: String,
    var response: String
) {
    var hook: URL = URI.create(hook).toURL()
}

object State {
    var arr = ArrayList<StateType>()
}
```
{: file="State.kt" }

```kotlin
package tf.irisc.chal.webwebhookhook.controller

import org.springframework.http.MediaType
import org.springframework.stereotype.Controller
import org.springframework.ui.Model
import org.springframework.web.bind.annotation.*
import tf.irisc.chal.webwebhookhook.State
import tf.irisc.chal.webwebhookhook.StateType
import java.net.HttpURLConnection
import java.net.URI

@Controller
class MainController {

    @GetMapping("/")
    fun home(model: Model): String {
        return "home.html"
    }

    @PostMapping("/webhook")
    @ResponseBody
    fun webhook(
        @RequestParam("hook") hook_str: String, 
        @RequestBody body: String, 
        @RequestHeader("Content-Type") contentType: String, 
        model: Model
    ): String {
        var hook = URI.create(hook_str).toURL();
        System.out.println(hook);
        for (h in State.arr) {
            if (h.hook == hook) {
                var newBody = h.template.replace("_DATA_", body);
                var conn = hook.openConnection() as? HttpURLConnection;
                if (conn === null) break;
                conn.requestMethod = "POST";
                conn.doOutput = true;
                conn.setFixedLengthStreamingMode(newBody.length);
                conn.setRequestProperty("Content-Type", contentType);
                conn.connect()
                conn.outputStream.use { os ->
                    os.write(newBody.toByteArray())
                }

                return h.response
            }
        }
        return "{\"result\": \"fail\"}"
    }

    @PostMapping("/create", consumes = [MediaType.APPLICATION_JSON_VALUE])
    @ResponseBody
    fun create(@RequestBody body: StateType): String {
        for(h in State.arr) {
            if(body.hook == h.hook)
                return "{\"result\": \"fail\"}"
        }
        State.arr.add(body)
        return "{\"result\": \"ok\"}"
    }
}
```
{: file="MainController.kt" }

```kotlin
package tf.irisc.chal.webwebhookhook

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication

@SpringBootApplication
class WebwebhookhookApplication

const val FLAG = "irisctf{test_flag}";

fun main(args: Array<String>) {
    State.arr.add(StateType(
            "http://example.com/admin",
            "{\"data\": _DATA_, \"flag\": \"" + FLAG + "\"}",
            "{\"response\": \"ok\"}"))
    runApplication<WebwebhookhookApplication>(*args)
}
```
{: file="WebwebhookhookApplication.kt" }

We can create a webhook, which will be stored in a global array.
When we call the webhook, it iterates through all saved webhooks, comparing the URL.

The flag is stored for the `example.com` domain, which we do not control.

The URLs are compared using the equality operator: `if (h.hook == hook) {`.
The operator, in Kotlin, is translated to the underlying Java function `equals`.

![](01.png)

It compares the ref (the hash, `#`, part of the URL) and then the files.

![](02.png)

It compares other stuff like protocol and path. The check we are interested in is the `hostsEqual` function.

![](03.png)

This is actually a DNS request for both hosts. If the DNS request is successful for both, then two hosts are
considered equal if they both point to the same IP.

Going back to our challenge, after checking `if (h.hook == hook) {` it makes a connection to the URL in the 
`hook` variable, which is user-controlled, instead of using the safe `h.hook` field.

The vulnerability here is that `hook` can resolve to one IP in the `if` condition, and to another IP when the
connection is actually made. This is called DNS rebinding. You don't need to buy a domain for this, there are 
free tools available online. I used this one: [https://lock.cmpxchg8b.com/rebinder.html](https://lock.cmpxchg8b.com/rebinder.html).

The only thing needed to do is create a script that continuously calls `<challenge host>/webhook?hook=<rebinder address>`.
In the favorable case, the rebinder will resolve to `example.com` in the `if` condition, and to our IP when the connection
is being made. We can set up a web server on our IP that catches incoming POST data.
