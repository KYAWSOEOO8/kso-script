#!/bin/bash
# ZIVPN Full Panel (Username/Password Login)
# Author: DEV-U PHOE KAUNT (Updated Edition)

set -euo pipefail

# ===== Pretty Colors & UI =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
say(){ echo -e "$1"; }

clear
echo -e "${B}────────────────────────────────────────────────────────${Z}"
echo -e "${G}🌟 ZIVPN FULL PANEL (EDIT + CALENDAR + PAUSE SYSTEM) 🌟${Z}"
echo -e "${C}          DEVELOPED BY: DEV-U PHOE KAUNT${Z}"
echo -e "${B}────────────────────────────────────────────────────────${Z}"

# ===== Root Check =====
if [ "$(id -u)" -ne 0 ]; then
  say "${R}❌ ဤ script ကို root အဖြစ် run ရပါမယ် (sudo -i)${Z}"; exit 1
fi

# ===== Install Packages =====
say "${Y}📦 လိုအပ်သော Packages များ တင်နေပါတယ်...${Z}"
apt-get update -y >/dev/null 2>&1
apt-get install -y curl ufw jq python3 python3-flask iproute2 conntrack openssl >/dev/null 2>&1

# ===== Paths & Folders =====
mkdir -p /etc/zivpn
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"

# ===== Download Binary =====
say "${Y}⬇️ ZIVPN Binary ဒေါင်းလုဒ်ဆွဲနေပါတယ်...${Z}"
curl -fsSL -o "$BIN" "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
chmod +x "$BIN"

# ===== SSL Certificates =====
if [ ! -f /etc/zivpn/zivpn.crt ]; then
  say "${Y}🔐 SSL Certificates များ ထုတ်ပေးနေပါတယ်...${Z}"
  openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
    -subj "/C=MM/O=UPK/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# ===== Default Data =====
[ -f "$USERS" ] || echo "[]" > "$USERS"
if [ ! -f "$CFG" ]; then
  echo '{"listen":":5667","auth":{"mode":"passwords","config":["zi"]},"cert":"/etc/zivpn/zivpn.crt","key":"/etc/zivpn/zivpn.key","obfs":"zivpn"}' > "$CFG"
fi

# ===== Admin Login Setup =====
say "${G}🔐 Web Panel အတွက် Login အချက်အလက်များ သတ်မှတ်ပါ${Z}"
read -p "အသုံးပြုမည့် နာမည် (Username): " WEB_USER
WEB_USER=${WEB_USER:-admin}
read -s -p "အသုံးပြုမည့် စကားဝှက် (Password): " WEB_PASS; echo
WEB_SECRET=$(openssl rand -hex 16)

echo "WEB_ADMIN_USER=$WEB_USER" > "$ENVF"
echo "WEB_ADMIN_PASSWORD=$WEB_PASS" >> "$ENVF"
echo "WEB_SECRET=$WEB_SECRET" >> "$ENVF"
chmod 600 "$ENVF"

# ===== Create Web UI (Python) =====
cat >/etc/zivpn/web.py <<'PY'
import os, json, subprocess, hmac, re
from flask import Flask, render_template_string, request, redirect, url_for, session
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "upk-7788-secret")

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LOGO_URL = "https://raw.githubusercontent.com/Upk123/upkvip-ziscript/refs/heads/main/20251018_231111.png"

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="my">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>UPK ZIVPN Panel</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        :root { --bg: #f0f2f5; --card: #ffffff; --primary: #1877f2; --danger: #f02849; --success: #42b72a; --warning: #f7b924; }
        body { font-family: 'Segoe UI', sans-serif; background: var(--bg); margin: 0; padding: 15px; }
        .container { max-width: 950px; margin: auto; }
        header { background: var(--card); padding: 15px; border-radius: 12px; display: flex; align-items: center; gap: 15px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .logo { height: 55px; border-radius: 10px; }
        .box { background: var(--card); padding: 20px; border-radius: 12px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); margin-bottom: 20px; }
        input, select { width: 100%; padding: 12px; margin: 8px 0; border: 1px solid #ddd; border-radius: 8px; box-sizing: border-box; }
        .btn { padding: 10px 18px; border-radius: 8px; border: none; cursor: pointer; font-weight: bold; color: white; text-decoration: none; display: inline-flex; align-items: center; gap: 8px; }
        .btn-save { background: var(--primary); width: 100%; justify-content: center; }
        .btn-edit { background: var(--warning); color: #000; }
        .btn-del { background: var(--danger); }
        .btn-toggle { background: #606770; }
        table { width: 100%; border-collapse: collapse; background: white; border-radius: 12px; overflow: hidden; }
        th, td { padding: 14px; text-align: left; border-bottom: 1px solid #eee; }
        th { background: #f8f9fa; color: #666; font-size: 13px; }
        .status-on { color: var(--success); font-weight: bold; }
        .status-off { color: var(--danger); }
        .row-disabled { opacity: 0.5; background: #f9f9f9; }
    </style>
</head>
<body>
    <div class="container">
        {% if not authed %}
            <div class="box" style="max-width:380px; margin: 80px auto; text-align:center;">
                <img src="{{logo}}" class="logo" style="height:80px;"><br>
                <h2>Panel Login</h2>
                <form method="POST" action="/login">
                    <input name="u" placeholder="Username" required>
                    <input name="p" type="password" placeholder="Password" required>
                    <button class="btn btn-save" type="submit">LOGIN</button>
                </form>
            </div>
        {% else %}
            <header>
                <img src="{{logo}}" class="logo">
                <div style="flex-grow:1">
                    <h3 style="margin:0">UPK ZIVPN Panel</h3>
                    <small style="color:var(--primary)">ZIVPN Multi-Management</small>
                </div>
                <a href="/logout" class="btn btn-del"><i class="fas fa-sign-out-alt"></i></a>
            </header>

            <div class="box">
                <h4><i class="fas fa-user-edit"></i> {{ 'Edit User' if edit_data else 'Add New User' }}</h4>
                <form method="POST" action="/add">
                    <div style="display:grid; grid-template-columns: 1fr 1fr; gap:12px;">
                        <input name="user" placeholder="Username" value="{{edit_data.user if edit_data else ''}}" required>
                        <input name="password" placeholder="Password" value="{{edit_data.password if edit_data else ''}}" required>
                        <select onchange="if(this.value!='') document.getElementById('exp_date').value=this.value">
                            <option value="">-- ရက်ရွေးရန် --</option>
                            <option value="30">၁ လစာ (ရက် ၃၀)</option>
                            <option value="60">၂ လစာ (ရက် ၆၀)</option>
                            <option value="90">၃ လစာ (ရက် ၉၀)</option>
                        </select>
                        <input type="date" name="expires" id="exp_date" value="{{edit_data.expires if edit_data else ''}}">
                    </div>
                    <button class="btn btn-save" type="submit"><i class="fas fa-save"></i> SAVE & SYNC</button>
                </form>
            </div>

            <table>
                <tr>
                    <th>User/Pass</th>
                    <th>Expires</th>
                    <th>Status</th>
                    <th>Actions</th>
                </tr>
                {% for u in users %}
                <tr class="{{ 'row-disabled' if u.disabled else '' }}">
                    <td><strong>{{u.user}}</strong><br><small>{{u.password}}</small></td>
                    <td>{{u.expires if u.expires else 'Unlimited'}}</td>
                    <td>
                        {% if u.disabled %}<span style="color:gray">Paused</span>
                        {% elif u.status == 'Online' %}<span class="status-on">● Online</span>
                        {% else %}<span class="status-off">○ Offline</span>{% endif %}
                    </td>
                    <td>
                        <div style="display:flex; gap:8px;">
                            <a href="/edit?user={{u.user}}" class="btn btn-edit"><i class="fas fa-edit"></i></a>
                            <a href="/toggle?user={{u.user}}" class="btn btn-toggle"><i class="fas {{ 'fa-eye' if u.disabled else 'fa-eye-slash' }}"></i></a>
                            <form method="POST" action="/delete" style="display:inline">
                                <input type="hidden" name="user" value="{{u.user}}">
                                <button class="btn btn-del" onclick="return confirm('ဖျက်မှာလား?')"><i class="fas fa-trash"></i></button>
                            </form>
                        </div>
                    </td>
                </tr>
                {% endfor %}
            </table>
        {% endif %}
    </div>
</body>
</html>
"""

def read_json(path):
    try:
        with open(path, "r") as f: return json.load(f)
    except: return []

def write_json(path, data):
    with open(path, "w") as f: json.dump(data, f, indent=4)

def sync_to_server():
    users = read_json(USERS_FILE)
    active_pws = [u['password'] for u in users if not u.get('disabled', False)]
    with open(CONFIG_FILE, "r") as f:
        cfg = json.load(f)
    cfg['auth']['config'] = active_pws
    write_json(CONFIG_FILE, cfg)
    subprocess.run(["systemctl", "restart", "zivpn"])

@app.route("/")
def index():
    if not session.get("authed"): return render_template_string(HTML_TEMPLATE, authed=False, logo=LOGO_URL)
    users = read_json(USERS_FILE)
    return render_template_string(HTML_TEMPLATE, authed=True, users=users, logo=LOGO_URL, edit_data=None)

@app.route("/login", methods=["POST"])
def login():
    u, p = request.form.get("u"), request.form.get("p")
    if hmac.compare_digest(u, os.environ.get("WEB_ADMIN_USER")) and hmac.compare_digest(p, os.environ.get("WEB_ADMIN_PASSWORD")):
        session["authed"] = True
    return redirect(url_for("index"))

@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("index"))

@app.route("/edit")
def edit():
    name = request.args.get("user")
    users = read_json(USERS_FILE)
    target = next((u for u in users if u['user'] == name), None)
    return render_template_string(HTML_TEMPLATE, authed=True, users=users, logo=LOGO_URL, edit_data=target)

@app.route("/add", methods=["POST"])
def add():
    user, pw, exp = request.form.get("user"), request.form.get("password"), request.form.get("expires")
    if exp and exp.isdigit():
        exp = (datetime.now() + timedelta(days=int(exp))).strftime("%Y-%m-%d")
    users = read_json(USERS_FILE)
    for u in users:
        if u['user'] == user:
            u['password'], u['expires'] = pw, exp
            break
    else:
        users.append({"user": user, "password": pw, "expires": exp, "disabled": False})
    write_json(USERS_FILE, users)
    sync_to_server()
    return redirect(url_for("index"))

@app.route("/toggle")
def toggle():
    name = request.args.get("user")
    users = read_json(USERS_FILE)
    for u in users:
        if u['user'] == name:
            u['disabled'] = not u.get('disabled', False)
    write_json(USERS_FILE, users)
    sync_to_server()
    return redirect(url_for("index"))

@app.route("/delete", methods=["POST"])
def delete():
    name = request.form.get("user")
    users = [u for u in read_json(USERS_FILE) if u['user'] != name]
    write_json(USERS_FILE, users)
    sync_to_server()
    return redirect(url_for("index"))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY

# ===== Systemd Services =====
say "${Y}⚙️ System Services များ သတ်မှတ်နေပါတယ်...${Z}"
cat >/etc/systemd/system/zivpn.service <<EOF
[Unit]
Description=ZIVPN UDP Server
After=network.target

[Service]
ExecStart=$BIN server -c $CFG
Restart=always
WorkingDirectory=/etc/zivpn

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/zivpn-web.service <<EOF
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

# ===== Networking & Firewall =====
say "${Y}🌐 Networking & Firewall ပြင်ဆင်နေပါတယ်...${Z}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
ufw allow 5667/udp >/dev/null 2>&1
ufw allow 6000:19999/udp >/dev/null 2>&1
ufw allow 8080/tcp >/dev/null 2>&1

# ===== Enable & Start =====
systemctl daemon-reload
systemctl enable --now zivpn zivpn-web

IP=$(hostname -I | awk '{print $1}')
say "\n${G}✅ အားလုံး အဆင်ပြေစွာ ပြီးဆုံးသွားပါပြီ!${Z}"
say "${B}🌐 Web Panel Link :${Z} ${Y}http://$IP:8080${Z}"
say "${B}👤 Admin Username :${Z} ${Y}$WEB_USER${Z}"
say "${B}🔑 Admin Password :${Z} ${Y}$WEB_PASS${Z}"
echo -e "${B}────────────────────────────────────────────────────────${Z}"
