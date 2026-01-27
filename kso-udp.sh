#!/bin/bash
# ZIVPN PREMIUM FULL SCRIPT (Logic + Ultra UI + Snow + Auto Download)

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

# 3. SSL Certs
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
    active_pws = [u['password'] for u in users if u.get('status', 'active') == 'active']
    with open(CONFIG_FILE, 'r') as f: cfg = json.load(f)
    cfg['auth']['config'] = active_pws
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
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
    <style>
        :root { --bg: #0f172a; --accent: #3b82f6; --glass: rgba(30, 41, 59, 0.7); --text: #f8fafc; }
        body { background: radial-gradient(circle at top, #1e293b, #0f172a); color: var(--text); font-family: 'Inter', sans-serif; margin: 0; padding: 20px; min-height: 100vh; overflow-x: hidden; }
        #snow-canvas { position: fixed; top: 0; left: 0; width: 100%; height: 100%; pointer-events: none; z-index: 999; }
        .snow-menu { position: fixed; top: 15px; right: 15px; z-index: 1000; background: var(--glass); padding: 8px 12px; border-radius: 12px; display: flex; align-items: center; gap: 8px; font-size: 0.8rem; border: 1px solid rgba(255,255,255,0.1); }
        .switch { position: relative; display: inline-block; width: 34px; height: 18px; }
        .switch input { opacity: 0; width: 0; height: 0; }
        .slider { position: absolute; cursor: pointer; top: 0; left: 0; right: 0; bottom: 0; background-color: #475569; transition: .4s; border-radius: 20px; }
        .slider:before { position: absolute; content: ""; height: 12px; width: 12px; left: 3px; bottom: 3px; background-color: white; transition: .4s; border-radius: 50%; }
        input:checked + .slider { background-color: var(--accent); }
        input:checked + .slider:before { transform: translateX(16px); }
        .container { max-width: 900px; margin: 0 auto; position: relative; z-index: 10; }
        .header { text-align: center; margin-bottom: 30px; }
        .header img { height: 90px; border-radius: 18px; border: 3px solid var(--accent); margin-bottom: 10px; box-shadow: 0 0 15px var(--accent); }
        .glass { background: var(--glass); backdrop-filter: blur(10px); border: 1px solid rgba(255,255,255,0.1); border-radius: 20px; padding: 25px; margin-bottom: 25px; }
        .form-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 10px; }
        input { background: #0f172a; border: 1px solid #334155; padding: 12px; border-radius: 10px; color: white; outline: none; }
        .btn { padding: 12px; border-radius: 10px; border: none; font-weight: 600; cursor: pointer; transition: 0.3s; }
        .btn-primary { background: var(--accent); color: white; }
        .btn-renew { background: rgba(16,185,129,0.2); color: #10b981; border: 1px solid #10b981; }
        .btn-del { background: rgba(244,63,94,0.2); color: #f43f5e; border: 1px solid #f43f5e; }
        .btn-toggle { background: rgba(245,158,11,0.2); color: #f59e0b; border: 1px solid #f59e0b; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th { text-align: left; color: #94a3b8; font-size: 0.8rem; padding: 15px; border-bottom: 1px solid #334155; }
        td { padding: 15px; border-bottom: 1px solid rgba(255,255,255,0.05); }
        .status { padding: 4px 10px; border-radius: 20px; font-size: 0.7rem; font-weight: 700; }
        .Online { background: #10b981; color: white; }
        .Offline { background: #475569; color: white; }
        #slip { background: #0f172a; padding: 25px; border-radius: 15px; border: 2px solid var(--accent); position: fixed; left: -9999px; width: 300px; text-align: center; }
    </style>
</head>
<body>
<canvas id="snow-canvas"></canvas>
<div class="snow-menu">
    <span>SNOW</span>
    <label class="switch"><input type="checkbox" id="snow-toggle" checked onclick="toggleSnow()"><span class="slider"></span></label>
</div>

<div class="container">
    <div class="header">
        <img src="{{ logo }}">
        <h1 style="margin:0; font-size: 1.5rem;">ZIVPN <span style="color:var(--accent)">PREMIUM</span></h1>
        <p style="color:var(--accent); margin:5px 0; font-weight:600; letter-spacing:1px;">PREMIUM SERVICE BY UPK</p>
    </div>

    <div class="glass">
        <form id="u-form" method="POST" action="/add" class="form-grid">
            <input type="hidden" name="old_user" id="old_user">
            <input name="user" id="i_user" placeholder="Name 1" required>
            <input name="password" id="i_pass" placeholder="Password 2" required>
            <input name="days" id="i_days" placeholder="Days 3" required>
            <button class="btn btn-primary" type="submit" onclick="doDownload()"><i class="fa-solid fa-download"></i> SAVE & DOWNLOAD 4</button>
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
                <tr style="{{ 'opacity: 0.4;' if u.status_v == 'disabled' else '' }}">
                    <td><b style="color:var(--accent)">{{u.user}}</b></td>
                    <td><small>{{u.expires}} ({{u.rem}} d)</small></td>
                    <td><code>{{u.port}}</code></td>
                    <td><span class="status {{ u.status }}">{{ u.status }}</span></td>
                    <td style="text-align:right">
                        <button onclick="editU('{{u.user}}','{{u.password}}','{{u.rem}}')" class="btn btn-renew" style="padding: 5px 8px;"><i class="fa-solid fa-rotate"></i></button>
                        <button onclick="location.href='/toggle/{{u.user}}'" class="btn btn-toggle" style="padding: 5px 8px;"><i class="fa-solid {{ 'fa-play' if u.status_v == 'disabled' else 'fa-pause' }}"></i></button>
                        <button onclick="if(confirm('Delete?')) location.href='/delete/{{u.user}}'" class="btn btn-del" style="padding: 5px 8px;"><i class="fa-solid fa-trash"></i></button>
                    </td>
                </tr>
                {% endfor %}
            </tbody>
        </table>
    </div>
</div>

<div id="slip">
    <img src="{{ logo }}" width="60" style="border-radius:10px;">
    <h3 style="color:var(--accent); margin:10px 0;">ZIVPN PREMIUM SLIP</h3>
    <div style="text-align:left; font-size:14px; color:white;">
        <p>User: <b id="s_u"></b></p>
        <p>Pass: <b id="s_p"></b></p>
        <p>Days: <b id="s_d"></b></p>
    </div>
</div>

<script>
    // Snow Effect
    const canvas = document.getElementById('snow-canvas');
    const ctx = canvas.getContext('2d');
    let particles = [];
    function initSnow() {
        canvas.width = window.innerWidth; canvas.height = window.innerHeight;
        particles = [];
        for(let i=0; i<80; i++) particles.push({x:Math.random()*canvas.width, y:Math.random()*canvas.height, r:Math.random()*3+1, d:Math.random()*1});
    }
    function drawSnow() {
        ctx.clearRect(0,0,canvas.width,canvas.height); ctx.fillStyle="white"; ctx.beginPath();
        for(let p of particles) { ctx.moveTo(p.x,p.y); ctx.arc(p.x,p.y,p.r,0,Math.PI*2,true); }
        ctx.fill(); moveSnow();
    }
    function moveSnow() {
        for(let p of particles) { p.y+=Math.pow(p.d,2)+1; if(p.y>canvas.height){p.y=-10; p.x=Math.random()*canvas.width;} }
    }
    let snowInt = setInterval(drawSnow, 30);
    initSnow();
    function toggleSnow() { canvas.style.display = document.getElementById('snow-toggle').checked ? 'block' : 'none'; }

    // Logic
    function editU(n, p, d) {
        document.getElementById('old_user').value = n;
        document.getElementById('i_user').value = n;
        document.getElementById('i_pass').value = p;
        document.getElementById('i_days').value = d;
        window.scrollTo({top:0, behavior:'smooth'});
    }
    function doDownload() {
        const n=document.getElementById('i_user').value, p=document.getElementById('i_pass').value, d=document.getElementById('i_days').value;
        if(!n||!p) return;
        document.getElementById('s_u').innerText=n; document.getElementById('s_p').innerText=p; document.getElementById('s_d').innerText=d;
        html2canvas(document.getElementById('slip')).then(c => {
            const l=document.createElement('a'); l.download=n+'_slip.png'; l.href=c.toDataURL(); l.click();
        });
    }
</script>
</body>
</html>"""

@app.route("/")
def index():
    users = read_db()
    for u in users:
        u['status'] = get_online_status(u['port'])
        try:
            delta = (datetime.strptime(u['expires'], "%Y-%m-%d") - datetime.now()).days + 1
            u['rem'] = delta if delta > 0 else 0
        except: u['rem'] = 0
    return render_template_string(HTML, logo=LOGO_URL, users=users)

@app.route("/add", methods=["POST"])
def add():
    old_user = request.form.get("old_user")
    user, pw, days = request.form.get("user"), request.form.get("password"), int(request.form.get("days", 30))
    db = read_db()
    if old_user: db = [u for u in db if u['user'] != old_user]
    exp = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
    port = 6000
    used_ports = [u['port'] for u in db]
    while port in used_ports: port += 1
    db.append({"user": user, "password": pw, "expires": exp, "port": port, "status_v": "active"})
    write_db(db); sync_vpn()
    return redirect("/")

@app.route("/toggle/<name>")
def toggle(name):
    db = read_db()
    for u in db:
        if u['user'] == name: u['status_v'] = 'disabled' if u.get('status_v','active')=='active' else 'active'
    write_db(db); sync_vpn()
    return redirect("/")

@app.route("/delete/<name>")
def delete(name):
    db = [u for u in read_db() if u['user'] != name]
    write_db(db); sync_vpn()
    return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY

# 5. Services Setup
systemctl stop zivpn-web >/dev/null 2>&1 || true
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

# 6. Firewall
ufw allow 8080/tcp >/dev/null; ufw allow 5667/udp >/dev/null; ufw allow 6000:7000/udp >/dev/null

echo -e "${G}✅ အောင်မြင်စွာ Update ပြုလုပ်ပြီးပါပြီ။${Z}"
echo -e "${Y}Web UI Link: http://$(hostname -I | awk '{print $1}'):8080${Z}"

