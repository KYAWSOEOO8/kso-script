#!/bin/bash
# KSO ZIVPN - User Management Version
# Version: 11.5

set -euo pipefail

# ၁။ လိုအပ်သော Folder နှင့် ဖိုင်များ ရှင်းလင်းခြင်း
sudo mkdir -p /etc/zivpn && sudo chmod 777 /etc/zivpn
sudo apt update && sudo apt install -y python3-flask curl jq

# ၂။ Admin အကောင့် သတ်မှတ်ခြင်း
echo -e "\e[1;33m--- Admin Setup ---\e[0m"
read -p "Admin Name: " ADMIN_U
read -p "Admin Password: " ADMIN_P
echo "WEB_ADMIN_USER=$ADMIN_U" > /etc/zivpn/web.env
echo "WEB_ADMIN_PASSWORD=$ADMIN_P" >> /etc/zivpn/web.env
echo "WEB_SECRET=$(openssl rand -hex 16)" >> /etc/zivpn/web.env

# ၃။ Web UI Script (web.py)
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
        body { font-family: sans-serif; background: #f8f9fa; padding: 15px; }
        .card { background: #fff; border-radius: 12px; padding: 20px; max-width: 500px; margin: auto; box-shadow: 0 4px 10px rgba(0,0,0,0.1); }
        h2 { color: #333; text-align: center; }
        input, select { width: 100%; padding: 10px; margin: 8px 0; border: 1px solid #ddd; border-radius: 6px; box-sizing: border-box; }
        .btn { padding: 8px 12px; border-radius: 6px; border: none; cursor: pointer; color: #fff; font-weight: bold; }
        .btn-blue { background: #007bff; width: 100%; margin-bottom: 20px; }
        .btn-renew { background: #28a745; margin-right: 5px; }
        .btn-del { background: #dc3545; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #eee; font-size: 14px; }
        th { background: #f1f1f1; }
        .expiry { color: #d9534f; font-weight: bold; }
    </style>
</head>
<body>
<div class="card">
    <h2>KSO VPN PANEL</h2>
    {% if not session.get('auth') %}
        <form method="POST" action="/login"><input name="u" placeholder="Admin User"><input type="password" name="p" placeholder="Password"><button class="btn btn-blue">LOGIN</button></form>
    {% else %}
        <form method="POST" action="/add">
            <input name="user" placeholder="နာမည်ပေးပါ" required>
            <input name="pass" placeholder="စကားဝှက်ပေးပါ" required>
            <select name="days">
                <option value="30">ရက် ၃၀ (၁ လ)</option>
                <option value="60">ရက် ၆၀ (၂ လ)</option>
                <option value="365">၃၆၅ ရက် (၁ နှစ်)</option>
            </select>
            <button class="btn btn-blue">အကောင့်ဖွင့်မည်</button>
        </form>

        <h3 style="border-bottom: 2px solid #007bff; padding-bottom: 5px;">ဖွင့်ထားသော အကောင့်စာရင်း</h3>
        <table>
            <tr><th>နာမည်</th><th>ကုန်ဆုံးရက်</th><th>လုပ်ဆောင်ချက်</th></tr>
            {% for u in users %}
            <tr>
                <td><b>{{u.user}}</b><br><small>Pass: {{u.password}}</small></td>
                <td class="expiry">{{u.expiry}}</td>
                <td>
                    <div style="display:flex;">
                        <form method="POST" action="/renew"><input type="hidden" name="user" value="{{u.user}}"><button class="btn btn-renew">တိုး</button></form>
                        <form method="POST" action="/del"><input type="hidden" name="user" value="{{u.user}}"><button class="btn btn-del">ဖျက်</button></form>
                    </div>
                </td>
            </tr>
            {% endfor %}
        </table>
        <br><center><a href="/logout" style="color:#666; font-size:12px;">Logout ထွက်မည်</a></center>
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
            old_date = datetime.datetime.strptime(u['expiry'], "%Y-%m-%d")
            u['expiry'] = (old_date + datetime.timedelta(days=30)).strftime("%Y-%m-%d")
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

# ၄။ Service နှင့် Firewall သတ်မှတ်ချက်များ
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
sudo ufw allow 5667/udp

echo -e "\n✅ တပ်ဆင်မှု အောင်မြင်ပါသည်။"
echo -e "🌐 Web Link: http://$(hostname -I | awk '{print $1}'):8080"

