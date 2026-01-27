#!/bin/bash
# ZIVPN - Strict Login Security Version
set -euo pipefail

# Pretty
G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"

# Root check
[[ $(id -u) -ne 0 ]] && { echo -e "${R}sudo -i ဖြင့် run ပါ${Z}"; exit 1; }

# Install packages
apt-get update -y && apt-get install -y python3 python3-flask openssl >/dev/null

mkdir -p /etc/zivpn
ENVF="/etc/zivpn/web.env"

# Login Setup
echo -e "${Y}🔐 Web Panel အတွက် Login အချက်အလက်သစ် သတ်မှတ်ပါ${Z}"
read -r -p "အသုံးပြုမည့် နာမည် (Username): " WEB_USER
read -r -p "အသုံးပြုမည့် စကားဝှက် (Password): " WEB_PASS
WEB_SECRET=$(openssl rand -hex 32)

cat > "$ENVF" <<EOF
WEB_ADMIN_USER=${WEB_USER}
WEB_ADMIN_PASSWORD=${WEB_PASS}
WEB_SECRET=${WEB_SECRET}
EOF
chmod 600 "$ENVF"

# Web UI Python Script (Strict Login Logic)
cat > /etc/zivpn/web.py <<'PY'
import os, json, hmac
from flask import Flask, render_template_string, request, redirect, session, url_for

app = Flask(__name__)
# Secret key ကို အသစ်ပြောင်းလိုက်တာကြောင့် အရင် session တွေ အကုန်ပျက်သွားပါလိမ့်မယ်
app.secret_key = os.environ.get("WEB_SECRET")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER")
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD")

LOGIN_HTML = """
<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>ZIVPN LOGIN</title>
    <style>
        body { font-family: sans-serif; background: #0f172a; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; color: white; }
        .card { background: #1e293b; padding: 30px; border-radius: 15px; width: 300px; text-align: center; border: 1px solid #334155; }
        input { width: 100%; padding: 12px; margin: 10px 0; border-radius: 8px; border: none; background: #334155; color: white; box-sizing: border-box; }
        button { width: 100%; padding: 12px; background: #3b82f6; color: white; border: none; border-radius: 8px; cursor: pointer; font-weight: bold; }
        .error { color: #f87171; font-size: 14px; margin-top: 10px; }
    </style>
</head>
<body>
    <div class="card">
        <h2>ZIVPN LOGIN</h2>
        <form method="post">
            <input type="text" name="u" placeholder="Username" required>
            <input type="password" name="p" placeholder="Password" required>
            <button type="submit">LOGIN</button>
        </form>
        {% if error %}<p class="error">{{ error }}</p>{% endif %}
    </div>
</body>
</html>
"""

DASHBOARD_HTML = """
<!DOCTYPE html>
<html>
<head><meta name="viewport" content="width=device-width, initial-scale=1"><title>Dashboard</title></head>
<body style="background:#0f172a; color:white; font-family:sans-serif; text-align:center; padding-top:50px;">
    <h1>🎉 LOGIN SUCCESS!</h1>
    <p>အကောင့်ဝင်ခြင်း အောင်မြင်ပါသည်။</p>
    <p>သင့် Dashboard အပြည့်အစုံကို ဤနေရာတွင် မြင်တွေ့ရပါမည်။</p>
    <br>
    <a href="/logout" style="color:#f87171; text-decoration:none; border:1px solid #f87171; padding:10px 20px; border-radius:5px;">LOGOUT</a>
</body>
</html>
"""

@app.route('/', methods=['GET', 'POST'])
def login():
    # Session မရှိရင် Login Page ပဲပြမယ်
    if request.method == 'POST':
        u = request.form.get('u')
        p = request.form.get('p')
        if hmac.compare_digest(u, ADMIN_USER) and hmac.compare_digest(p, ADMIN_PASS):
            session['is_admin'] = True
            return redirect(url_for('dashboard'))
        return render_template_string(LOGIN_HTML, error="Username သို့မဟုတ် Password မှားနေပါသည်။")
    
    if session.get('is_admin'):
        return redirect(url_for('dashboard'))
    return render_template_string(LOGIN_HTML)

@app.route('/dashboard')
def dashboard():
    # Login မဝင်ထားရင် Login Page ကို ပြန်မောင်းထုတ်မယ်
    if not session.get('is_admin'):
        return redirect(url_for('login'))
    return render_template_string(DASHBOARD_HTML)

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY

# Create Service
cat > /etc/systemd/system/zivpn-web.service <<EOF
[Unit]
Description=ZIVPN Web Panel
After=network.target
[Service]
EnvironmentFile=$ENVF
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now zivpn-web.service
systemctl restart zivpn-web

echo -e "\n\e[1;32m✅ အောင်မြင်စွာ ပြင်ဆင်ပြီးပါပြီ။\e[0m"
echo -e "\e[1;36mURL: http://$(hostname -I | awk '{print $1}'):8080\e[0m"
