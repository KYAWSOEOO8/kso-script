cat > zivpn.sh << 'EOF'
#!/bin/bash
# ZIVPN COMPACT PRO - FULL VERSION BY U PHOE KAUNT
set -euo pipefail

# Pretty Setup
G="\e[1;32m"; Y="\e[1;33m"; C="\e[1;36m"; Z="\e[0m"

# 1. Stop Services to prevent "Text file busy"
systemctl stop zivpn zivpn-web >/dev/null 2>&1 || true

clear
echo -e "${C}==========================================${Z}"
echo -e "${G}    🌟 ZIVPN COMPACT PRO INSTALLER 🌟     ${Z}"
echo -e "${C}==========================================${Z}"

# 2. Setup Admin Login
echo -e "\n${Y}[1] Web Panel အတွက် Login အချက်အလက် သတ်မှတ်ပါ${Z}"
read -p "Admin Username ပေးပါ: " ADMIN_U
read -p "Admin Password ပေးပါ: " ADMIN_P
ADMIN_U=${ADMIN_U:-admin}
ADMIN_P=${ADMIN_P:-admin}

# 3. Installation
echo -e "\n${G}[*] လိုအပ်သော Package များ သွင်းနေသည်...${Z}"
apt update -y && apt install -y curl python3-flask openssl ufw >/dev/null 2>&1

mkdir -p /etc/zivpn
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"

[ -f "$USERS" ] || echo "[]" > "$USERS"
echo "WEB_ADMIN_USER=$ADMIN_U" > "$ENVF"
echo "WEB_ADMIN_PASSWORD=$ADMIN_P" >> "$ENVF"
echo "WEB_SECRET=$(openssl rand -hex 16)" >> "$ENVF"

echo -e "${G}[*] Binary ဒေါင်းလုဒ်ဆွဲနေသည်...${Z}"
URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
curl -fsSL -o "$BIN" "$URL" && chmod +x "$BIN"

# SSL & Config
openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
  -subj "/C=MM/O=UPK/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
echo '{"listen":":5667","auth":{"mode":"passwords","config":[]},"cert":"/etc/zivpn/zivpn.crt","key":"/etc/zivpn/zivpn.key","obfs":"zivpn"}' > "$CFG"

# 4. Web UI Code
cat > /etc/zivpn/web.py << 'PY'
import os, json, subprocess, hmac
from flask import Flask, render_template_string, request, redirect, session
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET")
U_FILE, C_FILE = "/etc/zivpn/users.json", "/etc/zivpn/config.json"

HTML = """<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<style>
 :root{--bg:#0f172a; --card:#1e293b; --accent:#38bdf8; --text:#f1f5f9;}
 body{background:var(--bg); color:var(--text); font-family:sans-serif; margin:0; padding:10px;}
 .card{background:var(--card); padding:20px; border-radius:12px; max-width:800px; margin:auto;}
 input{background:#334155; border:1px solid #475569; color:#fff; padding:10px; border-radius:8px; width:100%; box-sizing:border-box; margin-bottom:10px;}
 .btn{padding:12px; border-radius:8px; border:none; cursor:pointer; font-weight:bold; width:100%; background:var(--accent); color:#0f172a;}
 table{width:100%; border-collapse:collapse; margin-top:15px; font-size:13px;}
 th, td{text-align:left; padding:10px; border-bottom:1px solid #334155;}
 .badge{padding:3px 8px; border-radius:5px; font-size:10px;}
 .active{background:#064e3b; color:#34d399;} .suspend{background:#451a03; color:#fbbf24;}
</style></head><body>
<div class="card">
 {% if not session.get('auth') %}
  <form method="POST" action="/login" style="max-width:300px; margin:auto;">
   <h2 style="text-align:center; color:var(--accent);">LOGIN</h2>
   <input name="u" placeholder="Admin Username"><input name="p" type="password" placeholder="Admin Password">
   <button class="btn">LOGIN</button>
  </form>
 {% else %}
  <h3 style="margin-top:0;">Create User</h3>
  <form method="POST" action="/add" style="display:grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap:10px;">
   <input name="user" placeholder="နာမည်"> <input name="pass" placeholder="စကားဝှက်"> <input name="exp" value="30">
   <button class="btn" style="height:42px;">ADD</button>
  </form>
  <div style="overflow-x:auto;">
   <table>
    <tr><th>USER</th><th>EXPIRY</th><th>STATUS</th><th>ACTIONS</th></tr>
    {% for u in users %}
    <tr>
     <td><b>{{u.user}}</b></td>
     <td>{{u.expires}}</td>
     <td><span class="badge {{ 'active' if u.status=='active' else 'suspend' }}">{{u.status.upper()}}</span></td>
     <td style="display:flex; gap:10px;">
      <form method="POST" action="/toggle"><input type="hidden" name="user" value="{{u.user}}"><button style="background:none; border:none; color:#94a3b8; cursor:pointer; font-size:16px;"><i class="fas fa-{{ 'pause-circle' if u.status=='active' else 'play-circle' }}"></i></button></form>
      <form method="POST" action="/del"><input type="hidden" name="user" value="{{u.user}}"><button style="background:none; border:none; color:#f87171; cursor:pointer; font-size:16px;" onclick="return confirm('Delete?')"><i class="fas fa-trash"></i></button></form>
     </td>
    </tr>
    {% endfor %}
   </table>
  </div>
 {% endif %}
</div>
</body></html>"""

def sync(users):
    with open(U_FILE, "w") as f: json.dump(users, f, indent=2)
    pws = [u['password'] for u in users if u.get('status','active') == 'active']
    with open(C_FILE, "r") as f: cfg = json.load(f)
    cfg['auth']['config'] = pws
    with open(C_FILE, "w") as f: json.dump(cfg, f, indent=2)
    subprocess.run(["systemctl", "restart", "zivpn"])

@app.route("/")
def index():
    if not session.get('auth'): return render_template_string(HTML)
    with open(U_FILE, "r") as f: users = json.load(f)
    return render_template_string(HTML, users=users)

@app.route("/login", methods=["POST"])
def login():
    if hmac.compare_digest(request.form.get("u"), os.environ.get("WEB_ADMIN_USER")) and hmac.compare_digest(request.form.get("p"), os.environ.get("WEB_ADMIN_PASSWORD")):
        session["auth"] = True
    return redirect("/")

@app.route("/add", methods=["POST"])
def add():
    u, p, d = request.form.get("user"), request.form.get("pass"), request.form.get("exp")
    exp_date = (datetime.now() + timedelta(days=int(d))).strftime("%Y-%m-%d")
    with open(U_FILE, "r") as f: users = json.load(f)
    users.append({"user":u, "password":p, "expires":exp_date, "status":"active"})
    sync(users); return redirect("/")

@app.route("/toggle", methods=["POST"])
def toggle():
    u = request.form.get("user")
    with open(U_FILE, "r") as f: users = json.load(f)
    for usr in users:
        if usr['user'] == u: usr['status'] = 'suspended' if usr.get('status','active') == 'active' else 'active'
    sync(users); return redirect("/")

@app.route("/del", methods=["POST"])
def delete():
    u = request.form.get("user")
    with open(U_FILE, "r") as f: users = json.load(f)
    users = [usr for usr in users if usr['user'] != u]
    sync(users); return redirect("/")

if __name__ == "__main__": app.run(host="0.0.0.0", port=8080)
PY

# 5. Service Files
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

# 6. Start
ufw allow 8080/tcp >/dev/null 2>&1
systemctl daemon-reload
systemctl enable --now zivpn zivpn-web

MYIP=$(curl -s4 icanhazip.com || hostname -I | awk '{print $1}')
echo -e "\n${G}✅ အောင်မြင်စွာ တပ်ဆင်ပြီးပါပြီ။${Z}"
echo -e "${C}🌐 Panel Link: ${Y}http://$MYIP:8080${Z}"
echo -e "${C}🔑 Login Name: ${Y}$ADMIN_U${Z}"
echo -e "${C}🔑 Login Pass: ${Y}$ADMIN_P${Z}\n"
EOF
bash zivpn.sh
