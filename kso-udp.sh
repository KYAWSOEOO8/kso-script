#!/bin/bash
# ZIVPN UDP Server + Web UI (KSO Version)
# Modified by: KSO
# Features: No Key Gate, Auto-refresh Web UI, Port Forwarding (6000-19999)

set -euo pipefail

# ===== Pretty Colors =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; M="\e[1;35m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP Server + Web UI (KSO Edition) စတင်နေပြီ${Z}\n$LINE"

# ===== Root check =====
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}Error: root အဖြစ် run ပေးပါ (sudo -i)${Z}"; exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ===== apt guards =====
wait_for_apt() {
  echo -e "${Y}⏳ apt ပိတ်မချင်း စောင့်နေပါတယ်...${Z}"
  for _ in $(seq 1 60); do
    if pgrep -x apt-get >/dev/null || pgrep -x apt >/dev/null || pgrep -f 'apt.systemd.daily' >/dev/null; then
      sleep 5
    else
      return 0
    fi
  done
}

# ===== Packages =====
say "${Y}📦 လိုအပ်သော Packages များ တင်နေပါတယ်...${Z}"
wait_for_apt
apt-get update -y >/dev/null
apt-get install -y curl ufw jq python3 python3-flask python3-apt iproute2 conntrack ca-certificates openssl >/dev/null

# stop old services
systemctl stop zivpn.service 2>/dev/null || true
systemctl stop zivpn-web.service 2>/dev/null || true

# ===== Paths =====
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"
mkdir -p /etc/zivpn

# ===== Download ZIVPN binary =====
say "${Y}⬇️ ZIVPN binary ကို ဒေါင်းလုဒ်ဆွဲနေပါတယ်...${Z}"
PRIMARY_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
TMP_BIN="$(mktemp)"
if ! curl -fsSL -o "$TMP_BIN" "$PRIMARY_URL"; then
  echo -e "${R}❌ Binary ဒေါင်းမရပါ။ Network စစ်ပေးပါ။${Z}"
  exit 1
fi
install -m 0755 "$TMP_BIN" "$BIN"
rm -f "$TMP_BIN"

# ===== SSL Certs =====
say "${Y}🔐 SSL စနစ် ပြင်ဆင်နေပါတယ်...${Z}"
openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
  -subj "/C=MM/ST=Yangon/L=Yangon/O=KSO/OU=Net/CN=zivpn" \
  -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1

# ===== Web Admin Setup =====
say "${G}👤 Web Panel အတွက် Admin အချက်အလက် သတ်မှတ်ပါ${Z}"
read -r -p "Admin Username: " WEB_USER
read -r -s -p "Admin Password: " WEB_PASS; echo
WEB_SECRET=$(openssl rand -hex 16)

{
  echo "WEB_ADMIN_USER=${WEB_USER}"
  echo "WEB_ADMIN_PASSWORD=${WEB_PASS}"
  echo "WEB_SECRET=${WEB_SECRET}"
} > "$ENVF"
chmod 600 "$ENVF"

# ===== VPN Passwords =====
read -r -p "Initial VPN Passwords (eg: kso,vip): " input_pw
if [ -z "${input_pw:-}" ]; then PW_LIST='["kso"]'; else
  PW_LIST=$(echo "$input_pw" | awk -F',' '{
    printf("["); for(i=1;i<=NF;i++){gsub(/^ *| *$/,"",$i); printf("%s\"%s\"", (i>1?",":""), $i)}; printf("]")
  }')
fi

# ===== Create config.json =====
cat > "$CFG" <<EOF
{
  "auth": {
    "mode": "passwords",
    "config": $PW_LIST
  },
  "listen": ":5667",
  "cert": "/etc/zivpn/zivpn.crt",
  "key": "/etc/zivpn/zivpn.key",
  "obfs": "zivpn"
}
EOF
[ -f "$USERS" ] || echo "[]" > "$USERS"

# ===== systemd: ZIVPN =====
cat >/etc/systemd/system/zivpn.service <<EOF
[Unit]
Description=KSO ZIVPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=$BIN server -c $CFG
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# ===== Web Panel (Python/Flask) =====
# Note: UI titles are changed to KSO
cat >/etc/zivpn/web.py <<'PY'
import os, json, subprocess, hmac
from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "kso-secret")

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"

# Web UI Header & Logo Settings
TITLE = "KSO ZIVPN PANEL"
LOGO_URL = "https://raw.githubusercontent.com/Upk123/upkvip-ziscript/refs/heads/main/20251018_231111.png"

HTML_TEMPLATE = """
<!doctype html>
<html>
<head>
    <title>{{ title }}</title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <style>
        body { font-family: sans-serif; background: #f4f4f4; padding: 20px; }
        .card { background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); max-width: 800px; margin: auto; }
        h1 { color: #333; }
        .btn { padding: 10px 20px; background: #007bff; color: white; border: none; border-radius: 5px; cursor: pointer; text-decoration: none; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: left; }
        th { background: #f8f9fa; }
    </style>
</head>
<body>
    <div class="card">
        <center><img src="{{ logo }}" width="80" style="border-radius:10px;"></center>
        <h1 align="center">{{ title }}</h1>
        <hr>
        {% if not session.get('auth') %}
            <form method="POST" action="/login">
                <input type="text" name="u" placeholder="Username" required style="width:100%; padding:10px; margin-bottom:10px;">
                <input type="password" name="p" placeholder="Password" required style="width:100%; padding:10px; margin-bottom:10px;">
                <button type="submit" class="btn">Login</button>
            </form>
        {% else %}
            <p>Welcome, Admin! | <a href="/logout">Logout</a></p>
            <form method="POST" action="/add">
                <input type="text" name="user" placeholder="User Name" required>
                <input type="text" name="password" placeholder="Pass" required>
                <button type="submit" class="btn">Add User</button>
            </form>
            <table>
                <tr><th>User</th><th>Password</th><th>Action</th></tr>
                {% for u in users %}
                <tr>
                    <td>{{ u.user }}</td>
                    <td>{{ u.password }}</td>
                    <td><form method="POST" action="/delete"><input type="hidden" name="user" value="{{ u.user }}"><button type="submit" style="color:red; border:none; background:none; cursor:pointer;">Delete</button></form></td>
                </tr>
                {% endfor %}
            </table>
        {% endif %}
    </div>
</body>
</html>
"""

@app.route('/')
def index():
    users = []
    if os.path.exists(USERS_FILE):
        with open(USERS_FILE, 'r') as f: users = json.load(f)
    return render_template_string(HTML_TEMPLATE, title=TITLE, logo=LOGO_URL, users=users)

@app.route('/login', methods=['POST'])
def login():
    u, p = request.form.get('u'), request.form.get('p')
    if hmac.compare_digest(u, os.environ.get("WEB_ADMIN_USER", "")) and hmac.compare_digest(p, os.environ.get("WEB_ADMIN_PASSWORD", "")):
        session['auth'] = True
    return redirect(url_for('index'))

@app.route('/logout')
def logout():
    session.pop('auth', None)
    return redirect(url_for('index'))

@app.route('/add', methods=['POST'])
def add():
    if not session.get('auth'): return redirect('/')
    name, pw = request.form.get('user'), request.form.get('password')
    users = []
    if os.path.exists(USERS_FILE):
        with open(USERS_FILE, 'r') as f: users = json.load(f)
    users.append({"user": name, "password": pw})
    with open(USERS_FILE, 'w') as f: json.dump(users, f, indent=2)
    # Sync with config.json
    with open(CONFIG_FILE, 'r') as f: cfg = json.load(f)
    cfg['auth']['config'] = [u['password'] for u in users]
    with open(CONFIG_FILE, 'w') as f: json.dump(cfg, f, indent=2)
    subprocess.run(["systemctl", "restart", "zivpn"])
    return redirect('/')

@app.route('/delete', methods=['POST'])
def delete():
    if not session.get('auth'): return redirect('/')
    name = request.form.get('user')
    with open(USERS_FILE, 'r') as f: users = json.load(f)
    users = [u for u in users if u['user'] != name]
    with open(USERS_FILE, 'w') as f: json.dump(users, f, indent=2)
    with open(CONFIG_FILE, 'r') as f: cfg = json.load(f)
    cfg['auth']['config'] = [u['password'] for u in users]
    with open(CONFIG_FILE, 'w') as f: json.dump(cfg, f, indent=2)
    subprocess.run(["systemctl", "restart", "zivpn"])
    return redirect('/')

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY

# ===== Web systemd =====
cat >/etc/systemd/system/zivpn-web.service <<EOF
[Unit]
Description=KSO Web Panel
After=network.target

[Service]
Type=simple
User=root
EnvironmentFile=$ENVF
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# ===== Networking =====
say "${Y}🌐 Network Rules များ ပြင်ဆင်နေပါတယ်...${Z}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
ufw allow 5667/udp && ufw allow 6000:19999/udp && ufw allow 8080/tcp

# ===== Finalize =====
systemctl daemon-reload
systemctl enable --now zivpn zivpn-web
IP=$(hostname -I | awk '{print $1}')

echo -e "\n$LINE\n${G}✅ KSO ZIVPN အောင်မြင်စွာ Install လုပ်ပြီးပါပြီ${Z}"
echo -e "${C}Web Panel: ${Y}http://$IP:8080${Z}\n$LINE"
