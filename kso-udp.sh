#!/bin/bash
# ZIVPN UDP Server + Full Web UI (Bypass Key Version)
# Features: No Key Gate, Full Login UI, User Management, Auto-Refresh
set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN Full Panel (Username/Password Login)${Z}\n$LINE"

# Root check
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}ဤ script ကို root အဖြစ် run ပါ (sudo -i)${Z}"; exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ===== 1. Admin Login Setup =====
say "${Y}🔐 Web Panel အတွက် Login အချက်အလက်များ သတ်မှတ်ပါ${Z}"
read -r -p "အသုံးပြုမည့် နာမည် (Username): " WEB_USER
read -r -p "အသုံးပြုမည့် စကားဝှက် (Password): " WEB_PASS
if [ -z "$WEB_USER" ] || [ -z "$WEB_PASS" ]; then
  echo -e "${R}Username နှင့် Password မထည့်ဘဲ ရှေ့ဆက်၍မရပါ${Z}"; exit 1
fi

# ===== 2. Packages Install =====
say "${Y}📦 လိုအပ်သော Packages များ တင်နေပါတယ်...${Z}"
apt-get update -y >/dev/null
apt-get install -y curl ufw jq python3 python3-flask iproute2 conntrack ca-certificates openssl >/dev/null

# Stop old services
systemctl stop zivpn.service 2>/dev/null || true
systemctl stop zivpn-web.service 2>/dev/null || true

# Directories
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"
mkdir -p /etc/zivpn

# ===== 3. ZIVPN Binary & Config =====
say "${Y}⬇️ ZIVPN Binary ဒေါင်းလုဒ်ဆွဲနေပါတယ်...${Z}"
curl -fsSL -o "$BIN" "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
chmod +x "$BIN"

# Generate SSL
openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
  -subj "/C=MM/ST=Yangon/L=Yangon/O=UPK/CN=zivpn" \
  -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1

# Initial Config
echo '{"auth":{"mode":"passwords","config":["zi"]},"listen":":5667","cert":"/etc/zivpn/zivpn.crt","key":"/etc/zivpn/zivpn.key","obfs":"zivpn"}' > "$CFG"
[ -f "$USERS" ] || echo "[]" > "$USERS"

# Save Admin Credentials
WEB_SECRET=$(openssl rand -hex 32)
cat > "$ENVF" <<EOF
WEB_ADMIN_USER=${WEB_USER}
WEB_ADMIN_PASSWORD=${WEB_PASS}
WEB_SECRET=${WEB_SECRET}
EOF
chmod 600 "$ENVF"

# ===== 4. Web UI Python Script (Full Management) =====
cat > /etc/zivpn/web.py <<'PY'
import os, json, subprocess, hmac, tempfile
from flask import Flask, render_template_string, request, redirect, session, url_for, jsonify
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER")
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD")

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LOGO_URL = "https://raw.githubusercontent.com/Upk123/upkvip-ziscript/refs/heads/main/20251018_231111.png"

# --- HTML Template ---
HTML_LAYOUT = """
<!DOCTYPE html>
<html lang="my">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>ZIVPN Management</title>
    <style>
        body { font-family: sans-serif; background: #f4f7f6; margin: 0; padding: 20px; }
        .container { max-width: 900px; margin: auto; background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { display: flex; align-items: center; justify-content: space-between; border-bottom: 2px solid #eee; padding-bottom: 10px; }
        .logo { height: 50px; border-radius: 8px; }
        .form-box { background: #fafafa; padding: 15px; border-radius: 8px; margin: 20px 0; border: 1px solid #ddd; }
        input, button { padding: 10px; margin: 5px; border-radius: 5px; border: 1px solid #ccc; }
        button { background: #1a73e8; color: white; cursor: pointer; border: none; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { padding: 12px; border: 1px solid #eee; text-align: left; }
        th { background: #f8f9fa; }
        .btn-del { background: #d93025; }
        .login-box { width: 300px; margin: 100px auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); text-align: center; }
    </style>
</head>
<body>
    <div class="container">
        {% if not session.get('auth') %}
            <div class="login-box">
                <img src="{{ logo }}" class="logo"><br>
                <h2>ZIVPN LOGIN</h2>
                <form method="post" action="/login">
                    <input type="text" name="u" placeholder="Username" required style="width:90%"><br>
                    <input type="password" name="p" placeholder="Password" required style="width:90%"><br>
                    <button type="submit" style="width:96%">Login</button>
                </form>
            </div>
        {% else %}
            <div class="header">
                <img src="{{ logo }}" class="logo">
                <h2>ZIVPN DASHBOARD</h2>
                <a href="/logout" style="color:red; text-decoration:none;">Logout</a>
            </div>

            <div class="form-box">
                <h3>➕ Add New User</h3>
                <form method="post" action="/add">
                    <input type="text" name="user" placeholder="Username" required>
                    <input type="text" name="password" placeholder="Password" required>
                    <input type="text" name="expires" placeholder="Days (e.g. 30)">
                    <button type="submit">Save & Sync</button>
                </form>
            </div>

            <table>
                <tr><th>User</th><th>Password</th><th>Expires</th><th>Delete</th></tr>
                {% for u in users %}
                <tr>
                    <td>{{ u.user }}</td>
                    <td>{{ u.password }}</td>
                    <td>{{ u.expires }}</td>
                    <td>
                        <form method="post" action="/delete" style="display:inline;">
                            <input type="hidden" name="user" value="{{ u.user }}">
                            <button type="submit" class="btn-del">Delete</button>
                        </form>
                    </td>
                </tr>
                {% endfor %}
            </table>
        {% endif %}
    </div>
</body>
</html>
"""

def load_data():
    try:
        with open(USERS_FILE, "r") as f: return json.load(f)
    except: return []

def save_and_sync(data):
    with open(USERS_FILE, "w") as f: json.dump(data, f, indent=2)
    pws = [u["password"] for u in data if "password" in u]
    try:
        with open(CONFIG_FILE, "r") as f: cfg = json.load(f)
        cfg["auth"]["config"] = pws
        with open(CONFIG_FILE, "w") as f: json.dump(cfg, f, indent=2)
        subprocess.run(["systemctl", "restart", "zivpn"], check=False)
    except: pass

@app.route("/")
def index():
    if not session.get('auth'): return render_template_string(HTML_LAYOUT, logo=LOGO_URL)
    return render_template_string(HTML_LAYOUT, users=load_data(), logo=LOGO_URL)

@app.route("/login", methods=["POST"])
def login():
    u, p = request.form.get("u"), request.form.get("p")
    if hmac.compare_digest(u, ADMIN_USER) and hmac.compare_digest(p, ADMIN_PASS):
        session['auth'] = True
    return redirect(url_for("index"))

@app.route("/logout")
def logout(): session.clear(); return redirect(url_for("index"))

@app.route("/add", methods=["POST"])
def add():
    if not session.get('auth'): return redirect("/")
    user, pw, exp = request.form.get("user"), request.form.get("password"), request.form.get("expires")
    data = load_data()
    if exp.isdigit():
        exp = (datetime.now() + timedelta(days=int(exp))).strftime("%Y-%m-%d")
    data.append({"user": user, "password": pw, "expires": exp})
    save_and_sync(data)
    return redirect("/")

@app.route("/delete", methods=["POST"])
def delete():
    if not session.get('auth'): return redirect("/")
    user = request.form.get("user")
    data = [u for u in load_data() if u["user"] != user]
    save_and_sync(data)
    return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY

# ===== 5. Services & Firewall =====
cat > /etc/systemd/system/zivpn.service <<EOF
[Unit]
Description=ZIVPN UDP Server
After=network.target
[Service]
ExecStart=$BIN server -c $CFG
Restart=always
[Install]
WantedBy=multi-user.target
EOF

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

# Networking
sysctl -w net.ipv4.ip_forward=1 >/dev/null
IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE

# UFW
ufw allow 5667/udp && ufw allow 6000:19999/udp && ufw allow 8080/tcp

# Start
systemctl daemon-reload
systemctl enable --now zivpn.service zivpn-web.service

IP=$(hostname -I | awk '{print $1}')
echo -e "$LINE\n${G}✅ အကုန်လုံး အဆင်သင့်ဖြစ်ပါပြီ!${Z}"
echo -e "${C}Web Panel: http://$IP:8080${Z}"
echo -e "${Y}Username : $WEB_USER${Z}"
echo -e "${Y}Password : $WEB_PASS${Z}\n$LINE"
