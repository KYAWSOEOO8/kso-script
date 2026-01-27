#!/bin/bash
# ZIVPN UDP Server + Web UI (NO KEY VERSION)
# Clean & Stable by U PHOE KAUNT

set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}──────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP Server + Web UI Installer${Z}\n$LINE"

# ===== Root check =====
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}❌ root အဖြစ် run လုပ်ပါ (sudo -i)${Z}"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ===== Packages =====
say "${Y}📦 Packages install လုပ်နေပါတယ်...${Z}"
apt-get update -y >/dev/null
apt-get install -y \
  curl jq ufw \
  python3 python3-flask \
  iproute2 conntrack \
  ca-certificates openssl >/dev/null

# ===== Stop old services =====
systemctl stop zivpn.service zivpn-web.service 2>/dev/null || true

# ===== Paths =====
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"
mkdir -p /etc/zivpn

# ===== Download ZIVPN binary =====
say "${Y}⬇️ ZIVPN binary download...${Z}"
URL="https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
curl -fsSL -o "$BIN" "$URL"
chmod +x "$BIN"

# ===== Base config =====
if [ ! -f "$CFG" ]; then
  cat >"$CFG" <<EOF
{
  "listen": ":5667",
  "obfs": "zivpn",
  "auth": {
    "mode": "passwords",
    "config": ["zi"]
  }
}
EOF
fi

# ===== SSL Cert =====
if [ ! -f /etc/zivpn/zivpn.crt ]; then
  say "${Y}🔐 SSL cert ဖန်တီးနေပါတယ်...${Z}"
  openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
    -subj "/C=MM/O=UPK/CN=zivpn" \
    -keyout /etc/zivpn/zivpn.key \
    -out /etc/zivpn/zivpn.crt >/dev/null 2>&1
fi

# ===== Web Admin Login =====
say "${Y}🔒 Web Admin Login ဖွင့်မလား? (Enter = မဖွင့်)${Z}"
read -r -p "Admin Username: " WEB_USER
if [ -n "${WEB_USER:-}" ]; then
  read -r -s -p "Admin Password: " WEB_PASS; echo
  WEB_SECRET=$(openssl rand -hex 32)
  cat >"$ENVF" <<EOF
WEB_ADMIN_USER=$WEB_USER
WEB_ADMIN_PASSWORD=$WEB_PASS
WEB_SECRET=$WEB_SECRET
EOF
  chmod 600 "$ENVF"
  say "${G}✅ Web Login ဖွင့်ပြီးပါပြီ${Z}"
else
  rm -f "$ENVF"
  say "${Y}ℹ️ Web Login မဖွင့်ပါ (Open mode)${Z}"
fi

# ===== Users file =====
[ -f "$USERS" ] || echo "[]" > "$USERS"

# ===== systemd: zivpn =====
cat >/etc/systemd/system/zivpn.service <<EOF
[Unit]
Description=ZIVPN UDP Server
After=network.target

[Service]
ExecStart=$BIN server -c $CFG
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

# ===== Web Panel =====
cat >/etc/zivpn/web.py <<'PY'
from flask import Flask, request, redirect, session, render_template_string
import json, os, subprocess, tempfile, hmac
from datetime import datetime, timedelta

USERS="/etc/zivpn/users.json"
CFG="/etc/zivpn/config.json"

app=Flask(__name__)
app.secret_key=os.environ.get("WEB_SECRET","dev")

ADMIN_U=os.environ.get("WEB_ADMIN_USER","")
ADMIN_P=os.environ.get("WEB_ADMIN_PASSWORD","")

HTML="""
<!doctype html><html><head><meta charset=utf-8>
<title>ZIVPN Panel</title>
<meta name=viewport content="width=device-width">
<style>
body{font-family:sans-serif;background:#f6f6f6;padding:20px}
.box{background:#fff;padding:16px;border-radius:12px;max-width:600px;margin:auto}
table{width:100%;border-collapse:collapse}
td,th{border:1px solid #ddd;padding:8px}
.btn{padding:6px 12px}
</style></head><body>
{% if not authed %}
<div class=box>
<h3>Login</h3>
<form method=post action=/login>
<input name=u placeholder=Username required><br><br>
<input name=p type=password placeholder=Password required><br><br>
<button class=btn>Login</button>
</form>
</div>
{% else %}
<div class=box>
<h3>ZIVPN Users</h3>
<form method=post action=/add>
<input name=user placeholder=User required>
<input name=password placeholder=Password required>
<input name=expires placeholder="YYYY-MM-DD or days">
<button class=btn>Add</button>
</form>
<br>
<table>
<tr><th>User</th><th>Password</th><th>Expires</th><th>Del</th></tr>
{% for u in users %}
<tr>
<td>{{u.user}}</td><td>{{u.password}}</td><td>{{u.expires}}</td>
<td>
<form method=post action=/del>
<input type=hidden name=user value="{{u.user}}">
<button class=btn>Del</button>
</form>
</td>
</tr>
{% endfor %}
</table>
<a href=/logout>Logout</a>
</div>
{% endif %}
</body></html>
"""

def load():
  try: return json.load(open(USERS))
  except: return []

def save(d):
  with open(USERS,"w") as f: json.dump(d,f,indent=2)

def sync():
  users=load()
  pw=[u["password"] for u in users]
  cfg=json.load(open(CFG))
  cfg["auth"]["config"]=pw
  json.dump(cfg,open(CFG,"w"),indent=2)
  subprocess.run("systemctl restart zivpn",shell=True)

@app.route("/",methods=["GET"])
def index():
  if ADMIN_U and not session.get("ok"):
    return redirect("/login")
  users=load()
  return render_template_string(HTML,authed=True,users=users)

@app.route("/login",methods=["GET","POST"])
def login():
  if request.method=="POST":
    if hmac.compare_digest(request.form["u"],ADMIN_U) and hmac.compare_digest(request.form["p"],ADMIN_P):
      session["ok"]=True
      return redirect("/")
  return render_template_string(HTML,authed=False)

@app.route("/logout")
def lo(): session.clear(); return redirect("/")

@app.route("/add",methods=["POST"])
def add():
  u=request.form["user"]
  p=request.form["password"]
  e=request.form.get("expires","")
  if e.isdigit():
    e=(datetime.now()+timedelta(days=int(e))).strftime("%Y-%m-%d")
  d=load()
  d.append({"user":u,"password":p,"expires":e})
  save(d); sync()
  return redirect("/")

@app.route("/del",methods=["POST"])
def dele():
  u=request.form["user"]
  d=[x for x in load() if x["user"]!=u]
  save(d); sync()
  return redirect("/")

app.run("0.0.0.0",8080)
PY

# ===== Web systemd =====
cat >/etc/systemd/system/zivpn-web.service <<EOF
[Unit]
Description=ZIVPN Web Panel
After=network.target

[Service]
EnvironmentFile=-/etc/zivpn/web.env
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# ===== Network =====
say "${Y}🌐 Networking setup...${Z}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
IFACE=$(ip route | awk '/default/ {print $5}')
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to :5667
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
ufw allow 5667/udp
ufw allow 6000:19999/udp
ufw allow 8080/tcp
ufw reload

# ===== Enable =====
systemctl daemon-reload
systemctl enable --now zivpn zivpn-web

IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ DONE${Z}"
echo -e "${C}Web Panel:${Z} http://$IP:8080"
echo -e "$LINE"
