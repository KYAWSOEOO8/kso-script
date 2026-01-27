#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar)
# Author: U PHOE KAUNT
set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

clear
echo -e "\n$LINE\n${G}🌟 ZIVPN UDP Server + Web UI BY U PHOE KAUNT${Z}\n$LINE"

# ===== Root check =====
if [ "$(id -u)" -ne 0 ]; then
  say "${R}❌ ဤ script ကို root အဖြစ် run ရပါမယ် (sudo -i)${Z}"; exit 1
fi

# ===== apt guards =====
say "${Y}⏳ apt packages များ စစ်ဆေးနေသည်...${Z}"
apt-get update -y >/dev/null 2>&1
apt-get install -y curl ufw jq python3 python3-flask iproute2 conntrack ca-certificates openssl >/dev/null 2>&1

# ===== Paths =====
mkdir -p /etc/zivpn
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"

# ===== Download Binary =====
say "${Y}⬇️ ZIVPN binary ဒေါင်းလုဒ်ဆွဲနေသည်...${Z}"
URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
curl -fsSL -o "$BIN" "$URL" || curl -fSL -o "$BIN" "https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
chmod +x "$BIN"

# ===== SSL Certs =====
if [ ! -f /etc/zivpn/zivpn.crt ]; then
  say "${Y}🔐 SSL Certificates ထုတ်ယူနေသည်...${Z}"
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/O=UPK/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# ===== Admin Setup =====
say "${G}🔐 Web Admin Login သတ်မှတ်ပါ (Enter နှိပ်ပါက admin/admin ဖြစ်မည်)${Z}"
read -p "Username: " WEB_USER; WEB_USER=${WEB_USER:-admin}
read -s -p "Password: " WEB_PASS; echo; WEB_PASS=${WEB_PASS:-admin}
echo "WEB_ADMIN_USER=$WEB_USER" > "$ENVF"
echo "WEB_ADMIN_PASSWORD=$WEB_PASS" >> "$ENVF"
echo "WEB_SECRET=$(openssl rand -hex 16)" >> "$ENVF"

# ===== Initial Config =====
echo '{"listen":":5667","auth":{"mode":"passwords","config":["zi"]},"cert":"/etc/zivpn/zivpn.crt","key":"/etc/zivpn/zivpn.key","obfs":"zivpn"}' > "$CFG"
[ -f "$USERS" ] || echo "[]" > "$USERS"

# ===== Web UI (Python) =====
cat > /etc/zivpn/web.py << 'PY'
import os, json, subprocess, hmac, re
from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "upk-secret")
USERS_FILE, CONFIG_FILE = "/etc/zivpn/users.json", "/etc/zivpn/config.json"
LOGO_URL = "https://raw.githubusercontent.com/Upk123/upkvip-ziscript/refs/heads/main/20251018_231111.png"

HTML = """<!doctype html><html lang="my"><head><meta charset="utf-8">
<title>ZIVPN UI</title><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
 :root{--bg:#f8f9fa; --primary:#1877f2; --card:#fff;}
 body{background:var(--bg); font-family:sans-serif; padding:20px;}
 .card{background:var(--card); padding:20px; border-radius:15px; box-shadow:0 4px 10px rgba(0,0,0,0.1); max-width:900px; margin:auto;}
 input, select{width:100%; padding:10px; margin:10px 0; border:1px solid #ddd; border-radius:8px;}
 .btn{padding:10px 20px; border-radius:8px; border:none; cursor:pointer; font-weight:bold; color:#fff; background:var(--primary);}
 table{width:100%; border-collapse:collapse; margin-top:20px;}
 th, td{padding:12px; border-bottom:1px solid #eee; text-align:left;}
 .status-on{color:green; font-weight:bold;}
 .logo{height:60px; border-radius:10px; display:block; margin:0 auto 10px;}
</style></head><body>
{% if not authed %}
 <div class="card" style="max-width:350px; margin-top:100px; text-align:center;">
  <img src="{{logo}}" class="logo"><h3>Admin Login</h3>
  <form method="POST" action="/login"><input name="u" placeholder="User"><input name="p" type="password" placeholder="Pass"><button class="btn" style="width:100%">Login</button></form>
 </div>
{% else %}
 <div class="card">
  <div style="display:flex; align-items:center; gap:15px; margin-bottom:20px;">
   <img src="{{logo}}" style="height:50px; border-radius:8px;">
   <div><h2 style="margin:0">DEV-U PHOE KAUNT</h2><small>ZIVPN Management</small></div>
   <a href="/logout" style="margin-left:auto; color:red;">Logout</a>
  </div>
  <form method="POST" action="/add" style="display:grid; grid-template-columns: 1fr 1fr; gap:10px;">
   <input name="user" placeholder="User" required><input name="password" placeholder="Pass" required>
   <input name="expires" placeholder="Days (eg: 30) or YYYY-MM-DD"><button class="btn">Add / Sync</button>
  </form>
  <table>
   <tr><th>User</th><th>Pass</th><th>Expiry</th><th>Status</th><th>Action</th></tr>
   {% for u in users %}
   <tr>
    <td>{{u.user}}</td><td>{{u.password}}</td><td>{{u.expires}}</td>
    <td class="status-on">Active</td>
    <td><form method="POST" action="/delete"><input type="hidden" name="user" value="{{u.user}}"><button style="color:red; background:none; border:none; cursor:pointer;">Delete</button></form></td>
   </tr>
   {% endfor %}
  </table>
 </div>
{% endif %}
</body></html>"""

def sync():
    with open(USERS_FILE, "r") as f: users = json.load(f)
    pws = [u['password'] for u in users]
    with open(CONFIG_FILE, "r") as f: cfg = json.load(f)
    cfg['auth']['config'] = pws
    with open(CONFIG_FILE, "w") as f: json.dump(cfg, f, indent=2)
    subprocess.run(["systemctl", "restart", "zivpn"])

@app.route("/")
def index():
    if not session.get("auth"): return render_template_string(HTML, authed=False, logo=LOGO_URL)
    with open(USERS_FILE, "r") as f: users = json.load(f)
    return render_template_string(HTML, authed=True, users=users, logo=LOGO_URL)

@app.route("/login", methods=["POST"])
def login():
    if hmac.compare_digest(request.form.get("u"), os.environ.get("WEB_ADMIN_USER")) and \
       hmac.compare_digest(request.form.get("p"), os.environ.get("WEB_ADMIN_PASSWORD")):
        session["auth"] = True
    return redirect("/")

@app.route("/logout")
def logout(): session.clear(); return redirect("/")

@app.route("/add", methods=["POST"])
def add():
    u, p, e = request.form.get("user"), request.form.get("password"), request.form.get("expires")
    if e.isdigit(): e = (datetime.now() + timedelta(days=int(e))).strftime("%Y-%m-%d")
    with open(USERS_FILE, "r") as f: users = json.load(f)
    users = [usr for usr in users if usr['user'] != u]
    users.append({"user":u, "password":p, "expires":e})
    with open(USERS_FILE, "w") as f: json.dump(users, f, indent=2)
    sync(); return redirect("/")

@app.route("/delete", methods=["POST"])
def delete():
    u = request.form.get("user")
    with open(USERS_FILE, "r") as f: users = json.load(f)
    users = [usr for usr in users if usr['user'] != u]
    with open(USERS_FILE, "w") as f: json.dump(users, f, indent=2)
    sync(); return redirect("/")

if __name__ == "__main__": app.run(host="0.0.0.0", port=8080)
PY

# ===== Service Files =====
cat >/etc/systemd/system/zivpn.service <<EOF
[Unit]
Description=ZIVPN Server
After=network.target
[Service]
ExecStart=$BIN server -c $CFG
Restart=always
[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/zivpn-web.service <<EOF
[Unit]
Description=ZIVPN Web
After=network.target
[Service]
EnvironmentFile=$ENVF
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# ===== Networking =====
sysctl -w net.ipv4.ip_forward=1 >/dev/null
IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
ufw allow 8080/tcp >/dev/null 2>&1
ufw allow 6000:19999/udp >/dev/null 2>&1

# ===== Start =====
systemctl daemon-reload
systemctl enable --now zivpn zivpn-web

say "\n$LINE\n${G}✅ အားလုံး အောင်မြင်စွာ တပ်ဆင်ပြီးပါပြီ${Z}"
say "${C}Web Panel: ${Y}http://$(hostname -I | awk '{print $1}'):8080${Z}\n$LINE"

