#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar)
# Modified: Removed API Key Gate
set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; M="\e[1;35m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP Server + Web UI (No Key Version)${Z}\n$LINE"

# ===== Root check =====
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}ဤ script ကို root အဖြစ် chạy ရပါမယ် (sudo -i)${Z}"; exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# =====================================================================
#                   KEY GATE BYPASSED
# =====================================================================
echo -e "${G}✅ Key မလိုဘဲ တိုက်ရိုက် Install လုပ်နေပါပြီ...${Z}"

# ===== apt guards =====
wait_for_apt() {
  echo -e "${Y}⏳ apt ပိတ်မချင်း စောင့်နေပါတယ်...${Z}"
  for _ in $(seq 1 60); do
    if pgrep -x apt-get >/dev/null || pgrep -x apt >/dev/null || pgrep -f 'apt.systemd.daily' >/dev/null || pgrep -x unattended-upgrade >/dev/null; then
      sleep 5
    else
      return 0
    fi
  done
}
apt_guard_start(){
  wait_for_apt
  CNF_CONF="/etc/apt/apt.conf.d/50command-not-found"
  if [ -f "$CNF_CONF" ]; then mv "$CNF_CONF" "${CNF_CONF}.disabled"; CNF_DISABLED=1; else CNF_DISABLED=0; fi
}
apt_guard_end(){
  dpkg --configure -a >/dev/null 2>&1 || true
  apt-get -f install -y >/dev/null 2>&1 || true
  if [ "${CNF_DISABLED:-0}" = "1" ] && [ -f "${CNF_CONF}.disabled" ]; then mv "${CNF_CONF}.disabled" "$CNF_CONF"; fi
}

# ===== Packages =====
say "${Y}📦 Packages တင်နေပါတယ်...${Z}"
apt_guard_start
apt-get update -y >/dev/null
apt-get install -y curl ufw jq python3 python3-flask python3-apt iproute2 conntrack ca-certificates openssl >/dev/null
apt_guard_end

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
say "${Y}⬇️ ZIVPN binary ကို ဒေါင်းနေပါတယ်...${Z}"
PRIMARY_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
curl -fsSL -o "$BIN" "$PRIMARY_URL"
chmod +x "$BIN"

# ===== Base config =====
if [ ! -f "$CFG" ]; then
  say "${Y}🧩 config.json ဖန်တီးနေပါတယ်...${Z}"
  curl -fsSL -o "$CFG" "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json" || echo '{}' > "$CFG"
fi

# ===== Certs =====
if [ ! -f /etc/zivpn/zivpn.crt ] || [ ! -f /etc/zivpn/zivpn.key ]; then
  say "${Y}🔐 SSL Certificate ဖန်တီးနေပါတယ်...${Z}"
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=UPK/OU=Net/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# ===== Web Admin Credentials =====
say "${Y}🔒 Web Admin Login သတ်မှတ်ပါ${Z}"
read -r -p "Username: " WEB_USER
read -r -s -p "Password: " WEB_PASS; echo
WEB_SECRET="$(openssl rand -hex 32)"
{
  echo "WEB_ADMIN_USER=${WEB_USER}"
  echo "WEB_ADMIN_PASSWORD=${WEB_PASS}"
  echo "WEB_SECRET=${WEB_SECRET}"
} > "$ENVF"
chmod 600 "$ENVF"

# ===== VPN Passwords =====
say "${G}🔏 VPN Default Password (eg: zi)${Z}"
read -r -p "Password: " input_pw
PW_LIST="[\"${input_pw:-zi}\"]"

# Update config.json
TMP=$(mktemp)
jq --argjson pw "$PW_LIST" '.auth.mode = "passwords" | .auth.config = $pw | .listen = ":5667" | .cert = "/etc/zivpn/zivpn.crt" | .key = "/etc/zivpn/zivpn.key" | .obfs = "zivpn"' "$CFG" > "$TMP" && mv "$TMP" "$CFG"
[ -f "$USERS" ] || echo "[]" > "$USERS"

# ===== systemd: ZIVPN =====
cat >/etc/systemd/system/zivpn.service <<'EOF'
[Unit]
Description=ZIVPN UDP Server
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
Environment=ZIVPN_LOG_LEVEL=info
[Install]
WantedBy=multi-user.target
EOF

# ===== Web Panel (Python Script) =====
# (ဒီနေရာမှာ အရှေ့က web.py ကုဒ်တစ်ခုလုံး အပြည့်အစုံ ပြန်ထည့်ပေးထားပါတယ်)
cat >/etc/zivpn/web.py <<'PY'
from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session, make_response
import json, re, subprocess, os, tempfile, hmac
from datetime import datetime, timedelta

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LISTEN_FALLBACK = "5667"
LOGO_URL = "https://raw.githubusercontent.com/Upk123/upkvip-ziscript/refs/heads/main/20251018_231111.png"

HTML = """<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<title>ZIVPN User Panel</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
 :root{ --bg:#ffffff; --fg:#111; --card:#fafafa; --bd:#e5e5e5; --ok:#0a8a0a; --bad:#c0392b; --btn:#fff; }
 body{font-family:system-ui,Arial;margin:24px;background:var(--bg);color:var(--fg)}
 .btn{padding:8px 14px;border-radius:999px;border:1px solid #ccc;background:var(--btn);cursor:pointer;text-decoration:none}
 table{width:100%;border-collapse:collapse;margin-top:20px}
 th,td{border:1px solid var(--bd);padding:10px;text-align:left}
 .box{padding:15px;border:1px solid var(--bd);background:var(--card);border-radius:10px}
 .logo{height:60px;border-radius:10px}
</style></head><body>
<header style="display:flex;align-items:center;gap:15px">
 <img src="{{ logo }}" class="logo">
 <h1>ZIVPN Panel</h1>
 <a href="/logout" class="btn">Logout</a>
</header>
<form method="post" action="/add" class="box">
 <h3>➕ Add User</h3>
 <input name="user" placeholder="Username" required>
 <input name="password" placeholder="Password" required>
 <input name="expires" placeholder="Days (eg: 30)">
 <button type="submit" class="btn">Save</button>
</form>
<table>
 <tr><th>User</th><th>Password</th><th>Expires</th><th>Port</th><th>Delete</th></tr>
 {% for u in users %}
 <tr>
  <td>{{u.user}}</td><td>{{u.password}}</td><td>{{u.expires}}</td><td>{{u.port}}</td>
  <td><form method="post" action="/delete"><input type="hidden" name="user" value="{{u.user}}"><button type="submit">❌</button></form></td>
 </tr>
 {% endfor %}
</table>
</body></html>"""

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER")
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD")

def load_users():
    try:
        with open(USERS_FILE,"r") as f: return json.load(f)
    except: return []

def save_users(u):
    with open(USERS_FILE,"w") as f: json.dump(u, f, indent=2)

@app.route("/")
def index():
    if not session.get("auth"): return redirect("/login")
    return render_template_string(HTML, users=load_users(), logo=LOGO_URL)

@app.route("/login", methods=["GET","POST"])
def login():
    if request.method=="POST":
        if request.form.get("u")==ADMIN_USER and request.form.get("p")==ADMIN_PASS:
            session["auth"]=True; return redirect("/")
    return 'User: <form method="post"><input name="u"><input name="p" type="password"><button>Login</button></form>'

@app.route("/logout")
def logout(): session.clear(); return redirect("/login")

@app.route("/add", methods=["POST"])
def add():
    u=load_users()
    new={"user":request.form["user"],"password":request.form["password"],"expires":request.form["expires"],"port":"5667"}
    u.append(new); save_users(u); return redirect("/")

@app.route("/delete", methods=["POST"])
def delete():
    u=[x for x in load_users() if x["user"]!=request.form["user"]]
    save_users(u); return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY

# ===== Web systemd =====
cat >/etc/systemd/system/zivpn-web.service <<'EOF'
[Unit]
Description=ZIVPN Web Panel
After=network.target
[Service]
EnvironmentFile=/etc/zivpn/web.env
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
ufw allow 5667/udp && ufw allow 6000:19999/udp && ufw allow 8080/tcp

# ===== Finalize =====
systemctl daemon-reload
systemctl enable --now zivpn.service zivpn-web.service

IP=$(hostname -I | awk '{print $1}')
echo -e "$LINE\n${G}✅ Installation Complete!${Z}\n${C}Web Panel: http://$IP:8080${Z}\n$LINE"
