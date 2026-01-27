#!/bin/bash
# KSO ZIVPN - Ultimate Full Package
# Version: 10.0 (All-in-One)

set -euo pipefail

# ၁။ လိုအပ်သော Packages များနှင့် Directory များ ပြင်ဆင်ခြင်း
echo "⚙️ System ပြင်ဆင်နေပါသည်..."
sudo apt update && sudo apt install -y python3-flask curl jq ufw python3-pip
pip3 install flask-cors --break-system-packages || true

sudo mkdir -p /etc/zivpn
sudo chmod 777 /etc/zivpn

# ၂။ Admin အကောင့် သတ်မှတ်ခြင်း
echo -e "\e[1;33m--- Admin Setup (Panel အတွက်) ---\e[0m"
read -p "Admin Name: " ADMIN_U
read -p "Admin Password: " ADMIN_P
echo "WEB_ADMIN_USER=$ADMIN_U" > /etc/zivpn/web.env
echo "WEB_ADMIN_PASSWORD=$ADMIN_P" >> /etc/zivpn/web.env
echo "WEB_SECRET=$(openssl rand -hex 16)" >> /etc/zivpn/web.env

# ၃။ ZIVPN Core (Binary) ဒေါင်းလုဒ်ဆွဲခြင်း
echo "📥 Downloading ZIVPN Core..."
curl -fsSL -o "/usr/local/bin/zivpn" "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
chmod +x "/usr/local/bin/zivpn"

# ၄။ Web UI & Management Script (web.py)
cat >/etc/zivpn/web.py <<'PY'
import os, json, subprocess, datetime
from flask import Flask, render_template_string, request, redirect, session

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET")
USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"

HTML = """
<!doctype html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <style>
        body { font-family: 'Segoe UI', sans-serif; background: #f0f2f5; padding: 15px; }
        .card { background: #fff; border-radius: 12px; padding: 20px; max-width: 500px; margin: auto; box-shadow: 0 4px 15px rgba(0,0,0,0.1); }
        h2 { color: #007bff; }
        input, select { width: 100%; padding: 12px; margin: 8px 0; border: 1px solid #ddd; border-radius: 8px; box-sizing: border-box; }
        .btn { padding: 10px 15px; border-radius: 8px; border: none; cursor: pointer; color: #fff; font-weight: bold; }
        .btn-blue { background: #007bff; width: 100%; margin-bottom: 20px; }
        .btn-renew { background: #28a745; font-size: 12px; }
        .btn-del { background: #dc3545; font-size: 12px; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; font-size: 14px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #eee; }
        th { background: #f8f9fa; color: #555; }
        .status { color: #28a745; font-weight: bold; }
    </style>
</head>
<body>
<div class="card">
    <h2 align="center">KSO ZIVPN PANEL</h2>
    {% if not session.get('auth') %}
        <form method="POST" action="/login">
            <input name="u" placeholder="Admin Name" required>
            <input type="password" name="p" placeholder="Password" required>
            <button class="btn btn-blue">LOGIN</button>
        </form>
    {% else %}
        <form method="POST" action="/add">
            <input name="user" placeholder="User Name" required>
            <input name="pass" placeholder="VPN Password (Config)" required>
            <select name="days">
                <option value="30">30 Days (၁ လ)</option>
                <option value="60">60 Days (၂ လ)</option>
                <option value="90">90 Days (၃ လ)</option>
                <option value="365">1 Year (၁ နှစ်)</option>
            </select>
            <button class="btn btn-blue">Add New User</button>
        </form>

        <h3>အကောင့်စာရင်း (User List)</h3>
        <table>
            <tr><th>Name</th><th>Pass</th><th>Expiry</th><th>Action</th></tr>
            {% for u in users %}
            <tr>
                <td>{{u.user}}</td>
                <td><code>{{u.password}}</code></td>
                <td>{{u.expiry}}</td>
                <td>
                    <form method="POST" action="/renew" style="display:inline;"><input type="hidden" name="user" value="{{u.user}}"><button class="btn btn-renew">တိုး</button></form>
                    <form method="POST" action="/del" style="display:inline;"><input type="hidden" name="user" value="{{u.user}}"><button class="btn btn-del">ဖျက်</button></form>
                </td>
            </tr>
            {% endfor %}
        </table>
        <br><center><a href="/logout" style="color:#999; text-decoration:none; font-size:12px;">Logout</a></center>
    {% endif %}
</div>
</body></html>"""

def sync_vpn(users):
    pwds = [u['password'] for u in users]
    cfg = {"auth": {"mode": "passwords", "config": pwds}, "listen": ":5667", "obfs": "zivpn"}
    with open(CONFIG_FILE, 'w') as f: json.dump(cfg, f)
    subprocess.run(["sudo", "systemctl", "restart", "zivpn"])

@app.route('/')
def index():
    users = json.load(open(USERS_FILE)) if os.path.exists(USERS_FILE) else []
    return render_template_string(HTML, users=users)

@app.route('/login', methods=['POST'])
def login():
    if request.form.get('u') == os.environ.get("WEB_ADMIN_USER") and request.form.get('p') == os.environ.get("WEB_ADMIN_PASSWORD"):
        session['auth'] = True
    return redirect('/')

@app.route('/add', methods=['POST'])
def add():
    u, p, d = request.form.get('user'), request.form.get('pass'), int(request.form.get('days'))
    e = (datetime.datetime.now() + datetime.timedelta(days=d)).strftime("%Y-%m-%d")
    users = json.load(open(USERS_FILE)) if os.path.exists(USERS_FILE) else []
    users.append({"user":u, "password":p, "expiry":e})
    with open(USERS_FILE, 'w') as f: json.dump(users, f)
    sync_vpn(users)
    return redirect('/')

@app.route('/renew', methods=['POST'])
def renew():
    name = request.form.get('user')
    users = json.load(open(USERS_FILE))
    for u in users:
        if u['user'] == name:
            u['expiry'] = (datetime.datetime.now() + datetime.timedelta(days=30)).strftime("%Y-%m-%d")
            break
    with open(USERS_FILE, 'w') as f: json.dump(users, f)
    return redirect('/')

@app.route('/del', methods=['POST'])
def delete():
    name = request.form.get('user')
    users = [u for u in json.load(open(USERS_FILE)) if u['user'] != name]
    with open(USERS_FILE, 'w') as f: json.dump(users, f)
    sync_vpn(users)
    return redirect('/')

@app.route('/logout')
def logout(): session.clear(); return redirect('/')

if __name__ == "__main__": app.run(host="0.0.0.0", port=8080)
PY

# ၅။ Config နှင့် Systemd Service ဖန်တီးခြင်း
echo '[]' > /etc/zivpn/users.json
echo '{"auth":{"mode":"passwords","config":[]},"listen":":5667","obfs":"zivpn"}' > /etc/zivpn/config.json

cat >/etc/systemd/system/zivpn.service <<EOF
[Unit]
After=network.target
[Service]
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
[Install]
WantedBy=multi-user.target
EOF

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

# ၆။ Firewall ဖွင့်ခြင်း (UDP Zip အတွက် Port များအပါအဝင်)
echo "🛡️ Configuring Firewall..."
sudo ufw allow 22/tcp
sudo ufw allow 8080/tcp
sudo ufw allow 5667/udp
sudo ufw allow 6000:19999/udp
sudo ufw --force enable

# ၇။ Service များ စတင်ခြင်း
sudo systemctl daemon-reload
sudo systemctl enable --now zivpn zivpn-web

IP=$(hostname -I | awk '{print $1}')
echo -e "\n✅ အားလုံး အောင်မြင်စွာ တပ်ဆင်ပြီးပါပြီ။"
echo -e "🌐 Web Panel: http://$IP:8080"
echo -e "🔑 Port for Zip: 5667 (UDP)"
