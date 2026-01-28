#!/bin/bash
# ZIVPN PRO UI - BY U PHOE KAUNT
set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
say(){ echo -e "$1"; }

# Service Stop to fix "Text file busy"
systemctl stop zivpn zivpn-web >/dev/null 2>&1 || true

clear
say "${G}🚀 ZIVPN Compact Pro UI တပ်ဆင်နေသည်...${Z}"

# ===== Paths & Env =====
mkdir -p /etc/zivpn
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"

# ===== Binary & SSL =====
URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
curl -fsSL -o "$BIN" "$URL" && chmod +x "$BIN"

if [ ! -f /etc/zivpn/zivpn.crt ]; then
  openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
    -subj "/C=MM/O=UPK/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# ===== Admin Env =====
[ -f "$ENVF" ] || {
  echo "WEB_ADMIN_USER=admin" > "$ENVF"
  echo "WEB_ADMIN_PASSWORD=admin" >> "$ENVF"
  echo "WEB_SECRET=$(openssl rand -hex 16)" >> "$ENVF"
}

# ===== Web UI (Compact Design) =====
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
 :root{--bg:#111827; --card:#1f2937; --accent:#3b82f6; --text:#f3f4f6;}
 body{background:var(--bg); color:var(--text); font-family:sans-serif; margin:0; padding:15px;}
 .card{background:var(--card); padding:20px; border-radius:12px; box-shadow:0 4px 6px rgba(0,0,0,0.3); max-width:900px; margin:auto;}
 .grid-form{display:grid; grid-template-columns:repeat(auto-fit, minmax(150px, 1fr)); gap:10px; margin:20px 0;}
 input{background:#374151; border:1px solid #4b5563; color:#fff; padding:10px; border-radius:6px; outline:none;}
 .btn{padding:10px; border-radius:6px; border:none; color:#fff; cursor:pointer; font-weight:bold; display:flex; align-items:center; justify-content:center; gap:5px;}
 .btn-add{background:var(--accent);}
 table{width:100%; border-collapse:collapse; margin-top:15px; font-size:14px;}
 th{text-align:left; color:#9ca3af; padding:10px; border-bottom:1px solid #374151;}
 td{padding:12px 10px; border-bottom:1px solid #374151;}
 .badge{padding:3px 8px; border-radius:4px; font-size:11px; font-weight:bold;}
 .bg-green{background:#065f46; color:#34d399;}
 .bg-red{background:#7f1d1d; color:#f87171;}
 .action-box{display:flex; gap:8px;}
 .icon-btn{background:none; border:none; cursor:pointer; font-size:16px; padding:4px;}
 .t-edit{color:#fbbf24;} .t-stop{color:#9ca3af;} .t-del{color:#ef4444;}
</style></head><body>
<div class="card">
 {% if not session.get('auth') %}
  <form method="POST" action="/login" style="max-width:300px; margin:auto; text-align:center;">
   <h3><i class="fas fa-lock"></i> Admin Login</h3>
   <input name="u" placeholder="User" style="width:100%"><br><br>
   <input name="p" type="password" placeholder="Pass" style="width:100%"><br><br>
   <button class="btn btn-add" style="width:100%">Login</button>
  </form>
 {% else %}
  <div style="display:flex; justify-content:space-between; align-items:center;">
   <h3 style="margin:0;"><i class="fas fa-bolt text-accent"></i> UPK - ZIVPN</h3>
   <a href="/logout" style="color:#9ca3af; text-decoration:none; font-size:13px;"><i class="fas fa-sign-out-alt"></i></a>
  </div>
  <form method="POST" action="/add" class="grid-form">
   <input name="user" placeholder="Username" required>
   <input name="pass" placeholder="Password" required>
   <input name="exp" placeholder="Days" value="30">
   <button class="btn btn-add"><i class="fas fa-plus"></i> Add User</button>
  </form>
  <div style="overflow-x:auto;">
   <table>
    <tr><th>User</th><th>Expiry</th><th>Status</th><th>Actions</th></tr>
    {% for u in users %}
    <tr>
     <td><i class="fas fa-user-circle"></i> {{u.user}}</td>
     <td>{{u.expires}}</td>
     <td><span class="badge {{ 'bg-green' if u.status=='active' else 'bg-red' }}">{{u.status.upper()}}</span></td>
     <td class="action-box">
      <form method="POST" action="/toggle"><input type="hidden" name="user" value="{{u.user}}"><button class="icon-btn t-stop" title="Pause/Play"><i class="fas fa-{{ 'pause-circle' if u.status=='active' else 'play-circle' }}"></i></button></form>
      <form method="POST" action="/edit_ui"><input type="hidden" name="user" value="{{u.user}}"><button class="icon-btn t-edit" title="Edit/Extend"><i class="fas fa-edit"></i></button></form>
      <form method="POST" action="/del"><input type="hidden" name="user" value="{{u.user}}"><button class="icon-btn t-del" onclick="return confirm('Delete?')" title="Delete"><i class="fas fa-trash"></i></button></form>
     </td>
    </tr>
    {% endfor %}
   </table>
  </div>
 {% endif %}
</div>
</body></html>"""

def save_and_sync(users):
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

@app.route("/logout")
def logout(): session.clear(); return redirect("/")

@app.route("/add", methods=["POST"])
def add():
    u, p, d = request.form.get("user"), request.form.get("pass"), request.form.get("exp")
    exp_date = (datetime.now() + timedelta(days=int(d))).strftime("%Y-%m-%d")
    with open(U_FILE, "r") as f: users = json.load(f)
    users.append({"user":u, "password":p, "expires":exp_date, "status":"active"})
    save_and_sync(users); return redirect("/")

@app.route("/toggle", methods=["POST"])
def toggle():
    u = request.form.get("user")
    with open(U_FILE, "r") as f: users = json.load(f)
    for usr in users:
        if usr['user'] == u: usr['status'] = 'suspended' if usr.get('status','active') == 'active' else 'active'
    save_and_sync(users); return redirect("/")

@app.route("/del", methods=["POST"])
def delete():
    u = request.form.get("user")
    with open(U_FILE, "r") as f: users = json.load(f)
    users = [usr for usr in users if usr['user'] != u]
    save_and_sync(users); return redirect("/")

@app.route("/edit_ui", methods=["POST"])
def edit_ui():
    u_name = request.form.get("user")
    with open(U_FILE, "r") as f: users = json.load(f)
    curr = next(i for i in users if i['user'] == u_name)
    return f'''<body style="background:#111827;color:#fff;font-family:sans-serif;padding:50px;">
    <form method="POST" action="/edit_save" style="max-width:300px;margin:auto;background:#1f2937;padding:20px;border-radius:10px;">
    <h3>Edit: {u_name}</h3>
    <input type="hidden" name="old_user" value="{u_name}">
    Pass: <input name="pass" value="{curr['password']}" style="width:100%;margin-bottom:10px;background:#374151;color:#fff;border:none;padding:8px;"><br>
    Expiry: <input name="exp" value="{curr['expires']}" style="width:100%;margin-bottom:20px;background:#374151;color:#fff;border:none;padding:8px;"><br>
    <button type="submit" style="background:#3b82f6;color:#fff;width:100%;padding:10px;border:none;border-radius:5px;">Save Changes</button>
    </form></body>'''

@app.route("/edit_save", methods=["POST"])
def edit_save():
    ou, p, e = request.form.get("old_user"), request.form.get("pass"), request.form.get("exp")
    with open(U_FILE, "r") as f: users = json.load(f)
    for usr in users:
        if usr['user'] == ou:
            usr['password'] = p
            usr['expires'] = e
    save_and_sync(users); return redirect("/")

if __name__ == "__main__": app.run(host="0.0.0.0", port=8080)
PY

# ===== Services & Start =====
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

systemctl daemon-reload
systemctl enable --now zivpn zivpn-web
say "\n${G}✅ UI အသစ် တပ်ဆင်ပြီးပါပြီ။ Port 8080 ကို ဝင်ကြည့်ပါ။${Z}"
