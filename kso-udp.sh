#!/bin/bash
# ZIVPN UDP Server + 3D Web UI (Myanmar)
# Author: U PHOE KAUNT (UI Redesign)
set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

clear
echo -e "\n$LINE\n${G}🌟 ZIVPN 3D UI EDITION BY U PHOE KAUNT${Z}\n$LINE"

# ===== Root check =====
if [ "$(id -u)" -ne 0 ]; then
  say "${R}❌ ဤ script ကို root အဖြစ် run ရပါမယ် (sudo -i)${Z}"; exit 1
fi

# ===== apt guards =====
say "${Y}⏳ လိုအပ်သော package များ စစ်ဆေးနေသည်...${Z}"
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

# ===== Web UI (Python) With 3D Design =====
cat > /etc/zivpn/web.py << 'PY'
import os, json, subprocess, hmac, re
from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "upk-secret")
USERS_FILE, CONFIG_FILE = "/etc/zivpn/users.json", "/etc/zivpn/config.json"
LOGO_URL = "https://raw.githubusercontent.com/Upk123/upkvip-ziscript/refs/heads/main/20251018_231111.png"

HTML = """<!doctype html><html lang="my"><head><meta charset="utf-8">
<title>ZIVPN 3D DASHBOARD</title><meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/all.min.css">
<style>
 :root{--primary:#6366f1; --secondary:#a855f7; --bg:#0f172a; --card:rgba(30, 41, 59, 0.7);}
 body{background: radial-gradient(circle at top left, #1e293b, #0f172a); color:#fff; font-family:'Segoe UI',sans-serif; margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center; overflow-x:hidden;}
 .container{width:100%; max-width:1000px; padding:20px; box-sizing:border-box;}
 .card{background:var(--card); backdrop-filter:blur(15px); border:1px solid rgba(255,255,255,0.1); padding:30px; border-radius:24px; box-shadow:0 25px 50px -12px rgba(0,0,0,0.5); position:relative; overflow:hidden;}
 .card::before{content:''; position:absolute; top:0; left:-100%; width:100%; height:100%; background:linear-gradient(90deg, transparent, rgba(255,255,255,0.05), transparent); transition:0.5s;}
 .card:hover::before{left:100%;}
 .login-card{max-width:400px; margin:auto; text-align:center; transform: perspective(1000px) rotateX(2deg);}
 input{width:100%; padding:14px; margin:10px 0; border:1px solid rgba(255,255,255,0.1); border-radius:12px; background:rgba(0,0,0,0.3); color:#fff; box-sizing:border-box; font-size:15px;}
 input:focus{border-color:var(--primary); outline:none; box-shadow:0 0 15px rgba(99,102,241,0.4);}
 .btn{width:100%; padding:14px; border-radius:12px; border:none; cursor:pointer; font-weight:bold; color:#fff; background:linear-gradient(135deg, var(--primary), var(--secondary)); transition:0.3s; text-transform:uppercase; letter-spacing:1px; box-shadow: 0 4px 15px rgba(99,102,241,0.3);}
 .btn:hover{transform:translateY(-3px); box-shadow:0 10px 25px rgba(99,102,241,0.5);}
 .btn:active{transform:translateY(0);}
 table{width:100%; border-collapse:separate; border-spacing:0 10px; margin-top:20px;}
 th{padding:15px; text-align:left; color:#94a3b8; font-size:13px; text-transform:uppercase;}
 td{padding:15px; background:rgba(255,255,255,0.03); border-top:1px solid rgba(255,255,255,0.05); border-bottom:1px solid rgba(255,255,255,0.05);}
 td:first-child{border-left:1px solid rgba(255,255,255,0.05); border-radius:12px 0 0 12px;}
 td:last-child{border-right:1px solid rgba(255,255,255,0.05); border-radius:0 12px 12px 0;}
 .status-badge{background:rgba(34,197,94,0.15); color:#4ade80; padding:5px 12px; border-radius:20px; font-size:11px; font-weight:bold; border:1px solid rgba(34,197,94,0.2);}
 .logo{height:80px; border-radius:20px; margin-bottom:15px; border:2px solid var(--primary); padding:2px; background:#fff;}
 .header-flex{display:flex; align-items:center; gap:20px; margin-bottom:30px; border-bottom:1px solid rgba(255,255,255,0.1); padding-bottom:20px;}
 .action-btn{color:#ef4444; background:rgba(239,68,68,0.1); border:none; cursor:pointer; width:35px; height:35px; border-radius:10px; transition:0.3s;}
 .action-btn:hover{background:#ef4444; color:#fff; transform:rotate(90deg);}
 code{background:rgba(0,0,0,0.3); padding:4px 8px; border-radius:6px; color:#a855f7;}
 @media (max-width: 600px) { .header-flex{flex-direction:column; text-align:center;} .header-flex a{margin:0 auto;} }
</style></head><body>
<div class="container">
{% if not authed %}
 <div class="card login-card">
  <img src="{{logo}}" class="logo">
  <h2 style="margin:10px 0 5px 0;">Admin Panel</h2>
  <p style="color:#94a3b8; font-size:14px; margin-bottom:25px;">Please verify your identity</p>
  <form method="POST" action="/login">
   <input name="u" placeholder="Username" required>
   <input name="p" type="password" placeholder="Password" required>
   <button class="btn" style="margin-top:15px;">Secure Login</button>
  </form>
 </div>
{% else %}
 <div class="card">
  <div class="header-flex">
   <img src="{{logo}}" style="height:60px; border-radius:15px; border:2px solid var(--primary);">
   <div>
    <h2 style="margin:0; font-weight:800; background:linear-gradient(to right, #fff, #6366f1); -webkit-background-clip:text; -webkit-text-fill-color:transparent;">DEV-U PHOE KAUNT</h2>
    <small style="color:#94a3b8; letter-spacing:1px;"><i class="fas fa-shield-alt"></i> ZIVPN UDP MANAGEMENT</small>
   </div>
   <a href="/logout" style="margin-left:auto; color:#ef4444; text-decoration:none; font-weight:bold; font-size:14px; background:rgba(239,68,68,0.1); padding:8px 15px; border-radius:10px;"><i class="fas fa-power-off"></i> LOGOUT</a>
  </div>
  
  <form method="POST" action="/add" style="display:grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap:15px; margin-bottom:30px; background:rgba(0,0,0,0.2); padding:20px; border-radius:18px; border:1px solid rgba(255,255,255,0.05);">
   <div><label style="font-size:12px; color:#94a3b8; margin-left:5px;">User Name</label><input name="user" placeholder="e.g. upk_user" required></div>
   <div><label style="font-size:12px; color:#94a3b8; margin-left:5px;">Password</label><input name="password" placeholder="e.g. 123456" required></div>
   <div><label style="font-size:12px; color:#94a3b8; margin-left:5px;">Validity (Days)</label><input name="expires" placeholder="30"></div>
   <div style="display:flex; align-items:flex-end;"><button class="btn" style="margin-bottom:10px;"><i class="fas fa-plus-circle"></i> Sync Server</button></div>
  </form>

  <div style="overflow-x:auto;">
  <table>
   <thead><tr><th>User Detail</th><th>Credentials</th><th>Expiry Date</th><th>Status</th><th>Actions</th></tr></thead>
   <tbody>
   {% for u in users %}
   <tr>
    <td style="font-weight:600;"><i class="fas fa-user-circle" style="color:var(--primary); margin-right:10px;"></i>{{u.user}}</td>
    <td><code>{{u.password}}</code></td>
    <td><span style="color:#94a3b8; font-size:13px;"><i class="far fa-clock"></i> {{u.expires}}</span></td>
    <td><span class="status-badge">ACTIVE</span></td>
    <td>
     <form method="POST" action="/delete" style="display:inline;">
      <input type="hidden" name="user" value="{{u.user}}">
      <button class="action-btn" onclick="return confirm('ဖျက်ထုတ်ရန် သေချာပါသလား?')"><i class="fas fa-trash"></i></button>
     </form>
    </td>
   </tr>
   {% endfor %}
   </tbody>
  </table>
  {% if not users %}<p style="text-align:center; color:#64748b; padding:20px;">No users found. Create one above.</p>{% endif %}
  </div>
 </div>
{% endif %}
</div>
</body></html>"""

def sync():
    try:
        with open(USERS_FILE, "r") as f: users = json.load(f)
        pws = [u['password'] for u in users]
        with open(CONFIG_FILE, "r") as f: cfg = json.load(f)
        cfg['auth']['config'] = pws
        with open(CONFIG_FILE, "w") as f: json.dump(cfg, f, indent=2)
        subprocess.run(["systemctl", "restart", "zivpn"])
    except: pass

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
    if not u or not p: return redirect("/")
    if e.isdigit(): e = (datetime.now() + timedelta(days=int(e))).strftime("%Y-%m-%d")
    elif not e: e = (datetime.now() + timedelta(days=30)).strftime("%Y-%m-%d")
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

say "\n$LINE\n${G}✅ ZIVPN 3D Panel တပ်ဆင်မှု ပြီးဆုံးပါပြီ${Z}"
say "${C}Web Panel Link: ${Y}http://$(hostname -I | awk '{print $1}'):8080${Z}\n$LINE"
