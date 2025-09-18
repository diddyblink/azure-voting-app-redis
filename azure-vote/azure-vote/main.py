from flask import Flask, request, render_template
import os
import random
import redis
import socket
import sys

app = Flask(__name__)

# Load configurations from environment or config file
app.config.from_pyfile('config_file.cfg')

if ("VOTE1VALUE" in os.environ and os.environ['VOTE1VALUE']):
    button1 = os.environ['VOTE1VALUE']
else:
    button1 = app.config['VOTE1VALUE']

if ("VOTE2VALUE" in os.environ and os.environ['VOTE2VALUE']):
    button2 = os.environ['VOTE2VALUE']
else:
    button2 = app.config['VOTE2VALUE']

if ("TITLE" in os.environ and os.environ['TITLE']):
    title = os.environ['TITLE']
else:
    title = app.config['TITLE']

# Redis configurations (compatibile con Azure Cache for Redis)
# Legge nuove variabili, ma mantiene compatibilità con REDIS/REDIS_PWD se presenti
redis_host = os.environ.get("REDIS_HOST") or os.environ.get("REDIS")  # Fallback
redis_port = int(os.environ.get("REDIS_PORT", "6380"))               # 6380 (TLS)
redis_ssl  = os.environ.get("REDIS_SSL", "true").lower() == "true"   # TLS ON di default
redis_pwd  = os.environ.get("REDIS_PASSWORD") or os.environ.get("REDIS_PWD")

# Redis Connection (TLS + password)
try:
    r = redis.Redis(
        host=redis_host,
        port=redis_port,
        password=redis_pwd,
        ssl=redis_ssl,
        db=0,
        decode_responses=True,
        socket_connect_timeout=5, 
        socket_timeout=5,
    )
    r.ping()
except redis.ConnectionError:
    exit('Failed to connect to Redis, terminating.')


# Change title to host name to demo NLB
if app.config['SHOWHOST'] == "true":
    title = socket.gethostname()

# Init Redis
if not r.get(button1): r.set(button1,0)
if not r.get(button2): r.set(button2,0)

@app.route('/', methods=['GET', 'POST'])
def index():

    if request.method == 'GET':

        # Get current values
        vote1 = r.get(button1)
        vote2 = r.get(button2)           

        # Return index with values
        return render_template("index.html", value1=int(vote1), value2=int(vote2), button1=button1, button2=button2, title=title)

    elif request.method == 'POST':

        if request.form['vote'] == 'reset':
            
            # Empty table and return results
            r.set(button1,0)
            r.set(button2,0)
            vote1 = r.get(button1)
            vote2 = r.get(button2)
            return render_template("index.html", value1=int(vote1), value2=int(vote2), button1=button1, button2=button2, title=title)
        
        else:

            # Insert vote result into DB
            vote = request.form['vote']
            r.incr(vote,1)
            
            # Get current values
            vote1 = r.get(button1)
            vote2 = r.get(button2) 
                
            # Return results
            return render_template("index.html", value1=int(vote1), value2=int(vote2), button1=button1, button2=button2, title=title)

if __name__ == "__main__":
    app.run()
