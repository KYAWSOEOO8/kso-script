#!/bin/bash
# KSO ZIVPN - Final Stable Version
# All Bugs & Library Issues Fixed

set -euo pipefail

# ၁။ လိုအပ်သော Library များ သွင်းခြင်း
sudo apt update
sudo apt install -y python3-flask python3-pip
pip3 install flask-cors --break-system-packages || true

# ၂။ Folder နှင့် Environment ပြင်ဆင်ခြင်း
sudo mkdir -p /etc/zivpn
sudo chmod 777 /etc/zivpn

# ၃။ စိတ်ကြိုက် Admin Name/Pass တောင်းခြင်း
echo -e "\e[1;33m--- Admin Setup ---\e[0m"
read -p "Admin Name: " ADMIN_U
read -p "Admin Password: " ADMIN_P

echo "WEB_ADMIN_USER=$ADMIN_U" > /etc/zivpn/web.env
echo "WEB_ADMIN_PASSWORD=$ADMIN_P" >> /etc/zivpn/web.env
echo "WEB_SECRET=$(openssl rand -hex 16)" >> /etc/zivpn/web.env

# ၄။ Web UI Script (web.py)
cat >/etc/zivpn/web.py <<'PY'
import os, json, subprocess, datetime
from flask import Flask, render_template_string, request, redirect, session

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET")
USERS_FILE = "/etc/zivpn/users.json"

HTML = """
<!doctype html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
    <style>
        body { font-family: sans-serif; background: #f0f2f5; padding: 15px; text-align: center; }
        .card { background: #fff; border-radius: 15px; padding: 25px; max-width: 400px; margin: auto; box-shadow: 0 4px 10px rgba(0,0,0,0.1); }
        #capture { background: #121212; color: #fff; padding: 20px; border-radius: 12px; margin-bottom: 15px; border: 2px solid #0084ff; }
        .row { display: flex; justify-content: space-between; margin: 8px 0; border-bottom: 1px dashed #333; padding-bottom: 5px; font-size: 14px; }
        .val { color: #00ff00; font-weight: bold; }
        input { width: 100%; padding: 12px; margin: 8px 0; border: 1px solid #ddd; border-radius: 8px; box-sizing: border-box; }
        .btn { width: 100%; padding: 12px; border-radius: 8px; border: none; cursor: pointer; font-weight: bold; color: #fff; background: #0084ff; }
    </style>
</head>
<body>
<div class="card">
    <h2>KSO ZIVPN PANEL</h2>
    {% if not session.get('auth') %}
        <form method="POST" action="/login">
            <input type="text" name="u" placeholder="Username" required>
            <input type="password" name="p" placeholder="Password" required>
            <button class="btn">LOGIN</button>
        </form>
    {% else %}
        <div id="capture">
            <div style="color:#0084ff; font-weight:bold; margin-bottom:10px;">🛡️ VPN INFO</div>
            <div class="row"><span>1. VPS IP:</span> <span class="val">{{vps_ip}}</span></div>
            <div class="row"><span>2. Name:</span> <span class="val">{{u or '---'}}</span></div>
            <div class="row"><span>3. Password:</span> <span class="val">{{p or '---'}}</span></div>
            <div class="row"><span>Expiry:</span> <span style="color:yellow;">{{e or '---'}}</span></div>
        </div>
        <button onclick="save()" class="btn" style="background:#6f42c1;">📸 Save အပုံဒေါင်းရန်</button>
        <form method="POST" action="/add" style="margin-top:20px;">
            <input name="user" placeholder="Name" required>
            <input name="pass" placeholder="Pass" required>
            <button class="btn">Add User</button>
        </form>
    {% endif %}
</div>
<script>
function save() { html2canvas(document.querySelector("#capture")).then(c => { let l=document.createElement('a'); l.download='VPN.png'; l.href=c.toDataURL(); l.click(); }); }
</script>
</body></html>"""

@app.route('/')
def index():
    users = json.load(open(USERS_FILE)) if os.path.exists(USERS_FILE) else []
    vps_ip = subprocess.check_output(["hostname", "-I"]).decode().split()[0]
    return render_template_string(HTML, users=users, vps_ip=vps_ip, u=session.get('u'), p=session.get('p'), e=session.get('e'))

@app.route('/login', methods=['POST'])
def login():
    if request.form.get('u') == os.environ.get("WEB_ADMIN_USER") and request.form.get('p') == os.environ.get("WEB_ADMIN_PASSWORD"):
        session['auth'] = True
    return redirect('/')

@app.route('/add', methods=['POST'])
def add():
    u, p = request.form.get('user'), request.form.get('pass')
    e = (datetime.datetime.now() + datetime.timedelta(days=30)).strftime("%Y-%m-%d")
    users = json.load(open(USERS_FILE)) if os.path.exists(USERS_FILE) else []
    users.append({"user":u, "password":p, "expiry":e})
    with open(USERS_FILE, 'w') as f: json.dump(users, f)
    session['u'], session['p'], session['e'] = u, p, e
    return redirect('/')

if __name__ == "__main__": app.run(host="0.0.0.0", port=8080)
PY

# ၅။ Service ပြန်တင်ခြင်း
echo '[]' > /etc/zivpn/users.json
cat >/etc/systemd/system/zivpn-web.service <<EOF
[Unit]
After=network.target
[Service]
EnvironmentFile=/etc/zivpn/web.env
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now zivpn-web
sudo ufw allow 8080/tcp

echo -e "\n✅ တပ်ဆင်မှု အောင်မြင်ပါသည်။"
echo -e "🌐 Browser Link: http://$(hostname -I | awk '{print $1}'):8080"
