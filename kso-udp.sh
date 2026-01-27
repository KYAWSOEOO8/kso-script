#!/bin/bash
# KSO ZIVPN - FULL COMPLETE 3D VERSION

# Install dependencies
apt-get update && apt-get install -y python3-flask conntrack

cat > /etc/zivpn/web.py << 'PY'
from flask import Flask, render_template_string, request, redirect
import json, os, subprocess
from datetime import datetime, timedelta

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LOGO_URL = "https://raw.githubusercontent.com/KYAWSOEOO8/kso-script/blob/main/icon.png"

def read_db():
    try:
        with open(USERS_FILE, 'r') as f: return json.load(f)
    except: return []

def write_db(data):
    with open(USERS_FILE, 'w') as f: json.dump(data, f, indent=2)

def sync_vpn():
    users = read_db()
    active_pws = [u['password'] for u in users if u.get('status', 'active') == 'active']
    try:
        with open(CONFIG_FILE, 'r') as f: cfg = json.load(f)
        cfg['auth']['config'] = active_pws
        with open(CONFIG_FILE, 'w') as f: json.dump(cfg, f, indent=2)
        subprocess.run(["systemctl", "restart", "zivpn"], stderr=subprocess.DEVNULL)
    except: pass

app = Flask(__name__)

HTML = """<!doctype html>
<html>
<head>
    <meta charset="utf-8"><title>KSO ZIVPN 3D</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { background: #1e293b; color: #e2e8f0; font-family: sans-serif; padding: 20px; text-align: center; }
        .card-3d { background: #1e293b; border-radius: 20px; padding: 25px; margin: 20px auto; max-width: 850px;
                box-shadow: 10px 10px 20px #000, -5px -5px 15px #334155; border: 1px solid rgba(255,255,255,0.05); }
        input { background: #1e293b; border: none; padding: 12px; border-radius: 10px; color: #fff; 
                box-shadow: inset 5px 5px 10px #000, inset -2px -2px 5px #334155; margin: 5px; outline: none; }
        .btn-3d { padding: 10px 20px; border-radius: 10px; border: none; cursor: pointer; background: #3b82f6; color: #fff;
               box-shadow: 5px 5px 10px #000; font-weight: bold; transition: 0.2s; text-decoration: none; display: inline-block; }
        .btn-3d:active { box-shadow: inset 3px 3px 7px #000; transform: translateY(2px); }
        table { width: 100%; margin-top: 20px; border-spacing: 0 15px; }
        tr { background: #1e293b; box-shadow: 8px 8px 15px #000, -3px -3px 10px #334155; border-radius: 15px; }
        td { padding: 15px; border-radius: 15px; }
        .bar-bg { width: 100%; background: #0f172a; height: 10px; border-radius: 5px; margin-top: 8px; box-shadow: inset 2px 2px 5px #000; }
        .bar-fill { height: 100%; border-radius: 5px; box-shadow: 0 0 10px rgba(59,130,246,0.5); }
    </style>
</head>
<body>
    <div class="card-3d" style="padding: 15px; display: inline-block;">
        <img src="{{ logo }}" style="height:90px; border-radius:50%; border:3px solid #3b82f6; box-shadow: 0 0 15px #3b82f6;">
    </div>
    <h1 style="text-shadow: 3px 3px 5px #000;">KSO ZIVPN</h1>
    <p style="color:#3b82f6; font-weight:bold; letter-spacing:2px;">PREMIUM SERVICE BY UPK</p>

    <div class="card-3d">
        <form method="POST" action="/add">
            <input name="user" placeholder="User Name" required>
            <input name="password" placeholder="Password" required>
            <input name="days" placeholder="Days" required style="width: 80px;">
            <button class="btn-3d" type="submit">CREATE ACCOUNT</button>
        </form>
    </div>

    <table>
        {% for u in users %}
        {% set rem = u.rem %}
        {% set color = '#10b981' if rem > 10 else ('#f59e0b' if rem > 3 else '#f43f5e') %}
        <tr style="{{ 'opacity: 0.5;' if u.status == 'disabled' else '' }}">
            <td style="text-align: left;">
                <b style="color:#3b82f6; font-size: 1.2rem;">{{u.user}}</b><br>
                <small style="color:#94a3b8;">Expires: {{u.expires}} ({{rem}} days left)</small>
                <div class="bar-bg"><div class="bar-fill" style="width:{{ (rem/30)*100 if rem < 30 else 100 }}%; background:{{color}};"></div></div>
            </td>
            <td><code>Port: {{u.port}}</code><br><code>Pass: {{u.password}}</code></td>
            <td style="text-align: right;">
                <a href="/extend/{{u.user}}" class="btn-3d" style="background:#10b981; font-size:11px;">RENEW</a>
                <a href="/toggle/{{u.user}}" class="btn-3d" style="background:{{ '#3b82f6' if u.status=='disabled' else '#f59e0b' }}; font-size:11px;">{{ 'ENABLE' if u.status=='disabled' else 'DISABLE' }}</a>
                <a href="/delete/{{u.user}}" onclick="return confirm('Delete?')" class="btn-3d" style="background:#f43f5e; font-size:11px;">DEL</a>
            </td>
        </tr>
        {% endfor %}
    </table>
</body>
</html>"""

@app.route("/")
def index():
    users = read_db()
    for u in users:
        try:
            delta = (datetime.strptime(u['expires'], "%Y-%m-%d") - datetime.now()).days + 1
            u['rem'] = delta if delta > 0 else 0
        except: u['rem'] = 0
    return render_template_string(HTML, logo=LOGO_URL, users=users)

@app.route("/add", methods=["POST"])
def add():
    user, pw, days = request.form.get("user"), request.form.get("password"), int(request.form.get("days"))
    exp = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
    db = read_db(); db.append({"user": user, "password": pw, "expires": exp, "port": 6000+len(db), "status": "active"})
    write_db(db); sync_vpn(); return redirect("/")

@app.route("/toggle/<name>")
def toggle(name):
    db = read_db()
    for u in db:
        if u['user'] == name: u['status'] = 'disabled' if u.get('status','active')=='active' else 'active'
    write_db(db); sync_vpn(); return redirect("/")

@app.route("/delete/<name>")
def delete(name):
    db = [u for u in read_db() if u['user'] != name]
    write_db(db); sync_vpn(); return redirect("/")

@app.route("/extend/<name>")
def extend(name):
    db = read_db()
    for u in db:
        if u['user'] == name:
            cur = datetime.strptime(u['expires'], "%Y-%m-%d")
            u['expires'] = (max(cur, datetime.now()) + timedelta(days=30)).strftime("%Y-%m-%d")
    write_db(db); sync_vpn(); return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY

# Kill old process and start new one
pkill -f web.py
nohup python3 /etc/zivpn/web.py > /dev/null 2>&1 &

echo "Success! Web UI is active at http://147.50.253.235:8080"
