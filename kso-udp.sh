#!/bin/bash
# ZIVPN PREMIUM FULL SCRIPT (Logic + Ultra UI)
# Features: Logo Center, Renew Button, Auto-Port, Status Check

set -euo pipefail

# ===== Colors =====
G="\e[1;32m"; B="\e[1;34m"; Y="\e[1;33m"; R="\e[1;31m"; Z="\e[0m"

# Root check
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}Error: Root အဖြစ် Run ပါ။${Z}"; exit 1
fi

echo -e "${B}🚀 ZIVPN Premium Server ကို စတင်တပ်ဆင်နေပါပြီ...${Z}"

# 1. Install Dependencies
apt-get update -y >/dev/null
apt-get install -y curl ufw jq python3 python3-flask iproute2 conntrack openssl >/dev/null

# 2. Setup Directories
mkdir -p /etc/zivpn
USERS_FILE="/etc/zivpn/users.json"
CONFIG_FILE="/etc/zivpn/config.json"

if [ ! -f "$USERS_FILE" ]; then echo "[]" > "$USERS_FILE"; fi
if [ ! -f "$CONFIG_FILE" ]; then echo '{"auth":{"mode":"passwords","config":[]},"listen":":5667"}' > "$CONFIG_FILE"; fi

# 3. SSL Certs (For VPN)
if [ ! -f /etc/zivpn/zivpn.crt ]; then
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# 4. Create Full Python Web App
cat >/etc/zivpn/web.py <<'PY'
from flask import Flask, render_template_string, request, redirect, url_for
import json, os, subprocess
from datetime import datetime, timedelta

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LOGO_URL = "https://raw.githubusercontent.com/Upk123/upkvip-ziscript/refs/heads/main/20251018_231111.png"

app = Flask(__name__)
app.secret_key = "upk_secret_key"

def read_db():
    with open(USERS_FILE, 'r') as f: return json.load(f)

def write_db(data):
    with open(USERS_FILE, 'w') as f: json.dump(data, f, indent=2)

def sync_vpn():
    users = read_db()
    pws = [u['password'] for u in users]
    with open(CONFIG_FILE, 'r') as f: cfg = json.load(f)
    cfg['auth']['config'] = pws
    with open(CONFIG_FILE, 'w') as f: json.dump(cfg, f, indent=2)
    subprocess.run(["systemctl", "restart", "zivpn"], stderr=subprocess.DEVNULL)

def get_online_status(port):
    try:
        out = subprocess.check_output(f"conntrack -L -p udp --dport {port} 2>/dev/null", shell=True).decode()
        return "Online" if out else "Offline"
    except: return "Offline"

HTML = """<!doctype html>
<html>
<head>
    <meta charset="utf-8">
    <title>ZIVPN PREMIUM</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
    <style>
        :root { --bg: #0f172a; --accent: #3b82f6; --glass: rgba(30, 41, 59, 0.7); --text: #f8fafc; }
        body { background: radial-gradient(circle at top, #1e293b, #0f172a); color: var(--text); font-family: 'Inter', sans-serif; margin: 0; padding: 20px; min-height: 100vh; }
        .container { max-width: 900px; margin: 0 auto; }
        .header { text-align: center; margin-bottom: 30px; }
        .header img { height: 90px; border-radius: 18px; border: 3px solid var(--accent); margin-bottom: 10px; box-shadow: 0 0 15px var(--accent); }
        .glass { background: var(--glass); backdrop-filter: blur(10px); border: 1px solid rgba(255,255,255,0.1); border-radius: 20px; padding: 25px; margin-bottom: 25px; }
        .form-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 10px; }
        input { background: #0f172a; border: 1px solid #334155; padding: 12px; border-radius: 10px; color: white; }
        .btn { padding: 12px; border-radius: 10px; border: none; font-weight: 600; cursor: pointer; transition: 0.3s; }
        .btn-primary { background: var(--accent); color: white; }
        .btn-renew { background: rgba(16,185,129,0.2); color: #10b981; border: 1px solid #10b981; }
        .btn-del { background: rgba(244,63,94,0.2); color: #f43f5e; border: 1px solid #f43f5e; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th { text-align: left; color: #94a3b8; font-size: 0.8rem; padding: 15px; border-bottom: 1px solid #334155; }
        td { padding: 15px; border-bottom: 1px solid rgba(255,255,255,0.05); }
        .status { padding: 4px 10px; border-radius: 20px; font-size: 0.7rem; font-weight: 700; }
        .Online { background: #10b981; color: white; }
        .Offline { background: #475569; color: white; }
    </style>
</head>
<body>
<div class="container">
    <div class="header">
        <img src="{{ logo }}">
        <h1 style="margin:0; font-size: 1.5rem;">ZIVPN <span style="color:var(--accent)">PREMIUM</span></h1>
        <p style="color:var(--accent); margin:5px 0; font-weight:600; letter-spacing:1px;">PREMIUM SERVICE BY UPK</p>
    </div>

    <div class="glass">
        <form method="POST" action="/add" class="form-grid">
            <input name="user" placeholder="Username" required>
            <input name="password" placeholder="Password" required>
            <input name="days" placeholder="Days (eg. 30)" required>
            <button class="btn btn-primary" type="submit">CREATE ACCOUNT</button>
        </form>
    </div>

    <div class="glass" style="padding: 10px; overflow-x: auto;">
        <table>
            <thead>
                <tr>
                    <th>USER</th>
                    <th>EXPIRY</th>
                    <th>PORT</th>
                    <th>STATUS</th>
                    <th style="text-align:right">ACTION</th>
                </tr>
            </thead>
            <tbody>
                {% for u in users %}
                <tr>
                    <td><b style="color:var(--accent)">{{u.user}}</b></td>
                    <td><small>{{u.expires}}</small></td>
                    <td><code>{{u.port}}</code></td>
                    <td><span class="status {{ u.status }}">{{ u.status }}</span></td>
                    <td style="text-align:right">
                        <button onclick="location.href='/extend/{{u.user}}'" class="btn btn-renew" style="padding: 5px 10px; font-size: 0.7rem;">RENEW</button>
                        <button onclick="if(confirm('Delete?')) location.href='/delete/{{u.user}}'" class="btn btn-del" style="padding: 5px 10px; font-size: 0.7rem;">DEL</button>
                    </td>
                </tr>
                {% endfor %}
            </tbody>
        </table>
    </div>
</div>
</body>
</html>"""

@app.route("/")
def index():
    users = read_db()
    for u in users: u['status'] = get_online_status(u['port'])
    return render_template_string(HTML, logo=LOGO_URL, users=users)

@app.route("/add", methods=["POST"])
def add():
    user = request.form.get("user")
    pw = request.form.get("password")
    days = int(request.form.get("days", 30))
    exp = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
    
    db = read_db()
    # Auto Port
    used_ports = [u['port'] for u in db]
    port = 6000
    while port in used_ports: port += 1
    
    db.append({"user": user, "password": pw, "expires": exp, "port": port})
    write_db(db); sync_vpn()
    return redirect("/")

@app.route("/delete/<name>")
def delete(name):
    db = [u for u in read_db() if u['user'] != name]
    write_db(db); sync_vpn()
    return redirect("/")

@app.route("/extend/<name>")
def extend(name):
    db = read_db()
    for u in db:
        if u['user'] == name:
            cur = datetime.strptime(u['expires'], "%Y-%m-%d")
            u['expires'] = (max(cur, datetime.now()) + timedelta(days=30)).strftime("%Y-%m-%d")
    write_db(db); sync_vpn()
    return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY

# 5. Services Setup
cat >/etc/systemd/system/zivpn-web.service <<'EOF'
[Unit]
Description=ZIVPN Web UI
After=network.target
[Service]
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now zivpn-web

# 6. Firewall & Forwarding
sysctl -w net.ipv4.ip_forward=1 >/dev/null
ufw allow 8080/tcp >/dev/null; ufw allow 5667/udp >/dev/null; ufw allow 6000:7000/udp >/dev/null

echo -e "${G}✅ အားလုံးပြီးစီးပါပြီ။${Z}"
echo -e "${Y}Web UI Link: http://$(hostname -I | awk '{print $1}'):8080${Z}"

