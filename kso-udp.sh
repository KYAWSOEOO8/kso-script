#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - Full Login UI Version
set -euo pipefail

# ===== Pretty =====
G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="\e[1;34m────────────────────────────────────────────────────────${Z}"

echo -e "\n$LINE\n${G}🌟 ZIVPN Web UI (Username/Password Login System)${Z}\n$LINE"

# Root check
if [ "$(id -u)" -ne 0 ]; then echo -e "${R}sudo -i ဖြင့် run ပါ${Z}"; exit 1; fi

# Install packages
apt-get update -y && apt-get install -y curl jq python3 python3-flask conntrack openssl >/dev/null

# Directories
mkdir -p /etc/zivpn
ENVF="/etc/zivpn/web.env"

# ===== Admin Login သတ်မှတ်ခြင်း =====
echo -e "${Y}🔐 Web Panel အတွက် Login အချက်အလက်များ သတ်မှတ်ပါ${Z}"
read -r -p "အသုံးပြုမည့် နာမည် (Username): " WEB_USER
read -r -p "အသုံးပြုမည့် စကားဝှက် (Password): " WEB_PASS
WEB_SECRET=$(openssl rand -hex 32)

cat > "$ENVF" <<EOF
WEB_ADMIN_USER=${WEB_USER}
WEB_ADMIN_PASSWORD=${WEB_PASS}
WEB_SECRET=${WEB_SECRET}
EOF
chmod 600 "$ENVF"

# ===== Web UI Python Script (Login UI ပါဝင်သည်) =====
cat > /etc/zivpn/web.py <<'PY'
import os, json, hmac
from flask import Flask, render_template_string, request, redirect, session, url_for

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "default_secret")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER", "admin")
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD", "admin")

LOGIN_HTML = """
<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: Arial, sans-serif; background: #f0f2f5; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .login-card { background: white; padding: 2rem; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); width: 300px; }
        h2 { text-align: center; color: #1a73e8; }
        input { width: 100%; padding: 10px; margin: 10px 0; border: 1px solid #ddd; border-radius: 6px; box-sizing: border-box; }
        button { width: 100%; padding: 10px; background: #1a73e8; color: white; border: none; border-radius: 6px; cursor: pointer; font-weight: bold; }
        button:hover { background: #1557b0; }
        .error { color: red; font-size: 14px; text-align: center; }
    </style>
</head>
<body>
    <div class="login-card">
        <h2>ZIVPN LOGIN</h2>
        {% if error %}<p class="error">{{ error }}</p>{% endif %}
        <form method="post">
            <input type="text" name="u" placeholder="Username" required autofocus>
            <input type="password" name="p" placeholder="Password" required>
            <button type="submit">အကောင့်ဝင်ရန်</button>
        </form>
    </div>
</body>
</html>
"""

@app.route('/login', methods=['GET', 'POST'])
def login():
    error = None
    if request.method == 'POST':
        u = request.form.get('u')
        p = request.form.get('p')
        if hmac.compare_digest(u, ADMIN_USER) and hmac.compare_digest(p, ADMIN_PASS):
            session['logged_in'] = True
            return redirect(url_for('index'))
        else:
            error = "နာမည် သို့မဟုတ် စကားဝှက် မှားနေပါသည်။"
    return render_template_string(LOGIN_HTML, error=error)

@app.route('/')
def index():
    if not session.get('logged_in'):
        return redirect(url_for('login'))
    return "<h1>Welcome to ZIVPN Dashboard</h1><p>You are logged in!</p><a href='/logout'>Logout</a>"

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY

# Service restart
cat > /etc/systemd/system/zivpn-web.service <<EOF
[Unit]
Description=ZIVPN Web Panel
After=network.target

[Service]
Type=simple
EnvironmentFile=$ENVF
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now zivpn-web.service

echo -e "$LINE\n${G}✅ အောင်မြင်စွာ ပြင်ဆင်ပြီးပါပြီ!${Z}"
echo -e "${C}Web UI ဝင်ရန်: http://147.50.253.235:8080/login${Z}\n$LINE"
