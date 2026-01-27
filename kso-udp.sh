#!/bin/bash
# ZIVPN UDP Server + Web UI (No API Key Version)
set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP Server + Web UI (API KEY ဖျက်ပြီးသား)${Z}\n$LINE"

# ===== Root check =====
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}ဤ script ကို root အဖြစ် run ပါ (sudo -i)${Z}"; exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ===== Packages Install =====
say "${Y}📦 Packages များ တင်နေပါတယ်...${Z}"
apt-get update -y >/dev/null
apt-get install -y curl ufw jq python3 python3-flask iproute2 conntrack ca-certificates openssl >/dev/null

# Stop old services
systemctl stop zivpn.service 2>/dev/null || true
systemctl stop zivpn-web.service 2>/dev/null || true

# Paths
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"
mkdir -p /etc/zivpn

# ===== Download ZIVPN binary =====
say "${Y}⬇️ ZIVPN binary ကို ဒေါင်းနေပါတယ်...${Z}"
curl -fsSL -o "$BIN" "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
chmod +x "$BIN"

# ===== Web Admin Setup (ဒီနေရာမှာ Username နဲ့ Password သတ်မှတ်ပါ) =====
say "${Y}🔐 Web Panel အတွက် Login အချက်အလက်များ သတ်မှတ်ပါ${Z}"
read -r -p "အသုံးပြုမည့် နာမည် (Username): " WEB_USER
read -r -p "အသုံးပြုမည့် စကားဝှက် (Password): " WEB_PASS

if [ -n "${WEB_USER}" ] && [ -n "${WEB_PASS}" ]; then
  WEB_SECRET=$(openssl rand -hex 32)
  cat > "$ENVF" <<EOF
WEB_ADMIN_USER=${WEB_USER}
WEB_ADMIN_PASSWORD=${WEB_PASS}
WEB_SECRET=${WEB_SECRET}
EOF
  chmod 600 "$ENVF"
  say "${G}✅ Login စနစ်ကို ဖွင့်လိုက်ပါပြီ။${Z}"
else
  echo -e "${R}⚠️ Username/Password မထည့်ပါက Login UI အလုပ်လုပ်မည်မဟုတ်ပါ။${Z}"
fi

# ===== VPN Config & SSL =====
openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
  -subj "/C=MM/ST=Yangon/L=Yangon/O=UPK/CN=zivpn" \
  -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1

echo '{"auth":{"mode":"passwords","config":["zi"]},"listen":":5667","cert":"/etc/zivpn/zivpn.crt","key":"/etc/zivpn/zivpn.key","obfs":"zivpn"}' > "$CFG"
[ -f "$USERS" ] || echo "[]" > "$USERS"

# ===== Web UI Script (Strict Session Check ပါဝင်သည်) =====
cat > /etc/zivpn/web.py <<'PY'
import os, json, hmac, subprocess
from flask import Flask, render_template_string, request, redirect, session, url_for
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "default_secret")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER")
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD")

# Login Check Function
def is_logged_in():
    return session.get("auth") == True

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        u, p = request.form.get("u"), request.form.get("p")
        if ADMIN_USER and hmac.compare_digest(u, ADMIN_USER) and hmac.compare_digest(p, ADMIN_PASS):
            session["auth"] = True
            return redirect(url_for('index'))
        return "Login Failed! မမှန်ကန်ပါ။"
    return '''<body style="background:#0f172a;color:white;text-align:center;padding-top:100px;font-family:sans-serif;">
              <form method="post"><h2>ZIVPN LOGIN</h2>
              <input name="u" placeholder="Username" required><br><br>
              <input name="p" type="password" placeholder="Password" required><br><br>
              <button type="submit">LOGIN</button></form></body>'''

@app.route('/')
def index():
    if not is_logged_in(): return redirect(url_for('login'))
    return f"<h1>Welcome {ADMIN_USER}</h1><p>Dashboard is here.</p><a href='/logout'>Logout</a>"

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY

# ===== Service & Firewall =====
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

echo -e "$LINE\n${G}✅ API KEY Gate ကို ဖျက်ပြီးပါပြီ။${Z}"
echo -e "${C}URL: http://$(hostname -I | awk '{print $1}'):8080${Z}\n$LINE"
