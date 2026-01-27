#!/bin/bash
# ZIVPN UDP Server + Web UI (Ultimate Edition)
# Features: Calendar, Edit System, Disable/Enable Button, Monthly Menu

set -euo pipefail

# ===== Pretty Colors =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; Z="\e[0m"
say(){ echo -e "$1"; }

# ===== Root check =====
if [ "$(id -u)" -ne 0 ]; then
  say "${R}ဤ script ကို root အဖြစ် run ရပါမယ် (sudo -i)${Z}"; exit 1
fi

# ===== Packages =====
say "${Y}📦 လိုအပ်သော Packages များ တင်နေပါတယ်...${Z}"
apt-get update -y >/dev/null
apt-get install -y curl ufw jq python3 python3-flask iproute2 conntrack openssl >/dev/null

# ===== Paths & Files =====
mkdir -p /etc/zivpn
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"

# ===== Download Binary =====
say "${Y}⬇️ ZIVPN Core ကို ဒေါင်းလုဒ်ဆွဲနေပါတယ်...${Z}"
curl -fsSL -o "$BIN" "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
chmod +x "$BIN"

# ===== SSL Certs =====
if [ ! -f /etc/zivpn/zivpn.crt ]; then
  openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
    -subj "/C=MM/O=UPK/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# ===== Default Files =====
[ -f "$USERS" ] || echo "[]" > "$USERS"
if [ ! -f "$CFG" ]; then
  echo '{"listen":":5667","auth":{"mode":"passwords","config":["zi"]},"cert":"/etc/zivpn/zivpn.crt","key":"/etc/zivpn/zivpn.key","obfs":"zivpn"}' > "$CFG"
fi

# ===== Web Admin Setup =====
say "${G}🔐 Web UI အတွက် Login Password သတ်မှတ်ပါ${Z}"
read -p "Username (Default: admin): " WEB_USER
WEB_USER=${WEB_USER:-admin}
read -s -p "Password: " WEB_PASS; echo
WEB_SECRET=$(openssl rand -hex 16)
echo "WEB_ADMIN_USER=$WEB_USER" > "$ENVF"
echo "WEB_ADMIN_PASSWORD=$WEB_PASS" >> "$ENVF"
echo "WEB_SECRET=$WEB_SECRET" >> "$ENVF"

# ===== Web UI (Python Code) =====
cat >/etc/zivpn/web.py <<'PY'
import os, json, subprocess, hmac
from flask import Flask, render_template_string, request, redirect, url_for, session
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "upk-secret")
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
        :root { --bg: #f4f7f6; --card: #ffffff; --primary: #007bff; --danger: #dc3545; --success: #28a745; }
        body { font-family: 'Segoe UI', Tahoma, sans-serif; background: var(--bg); margin: 0; padding: 20px; }
        .container { max-width: 900px; margin: auto; }
        header { background: var(--card); padding: 20px; border-radius: 15px; display: flex; align-items: center; gap: 20px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .logo { height: 60px; border-radius: 10px; }
        .box { background: var(--card); padding: 20px; border-radius: 15px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); margin-bottom: 20px; }
        input, select { width: 100%; padding: 12px; margin: 10px 0; border: 1px solid #ddd; border-radius: 8px; box-sizing: border-box; }
        .btn { padding: 10px 20px; border-radius: 8px; border: none; cursor: pointer; font-weight: bold; transition: 0.3s; color: white; text-decoration: none; }
        .btn-add { background: var(--success); width: 100%; }
        .btn-edit { background: #ffc107; color: black; }
        .btn-del { background: var(--danger); }
        .btn-toggle { background: #6c757d; }
        table { width: 100%; border-collapse: collapse; background: white; border-radius: 15px; overflow: hidden; }
        th, td { padding: 15px; text-align: left; border-bottom: 1px solid #eee; }
        th { background: #f8f9fa; }
        .status-on { color: var(--success); font-weight: bold; }
        .status-off { color: var(--danger); }
        .disabled { opacity: 0.5; background: #fdfdfe; }
    </style>
</head>
<body>
    <div class="container">
        {% if not authed %}
            <div class="box" style="max-width:400px; margin: 100px auto; text-align:center;">
                <img src="{{logo}}" class="logo"><br>
                <h3>Login Panel</h3>
                <form method="POST" action="/login">
                    <input name="u" placeholder="Username" required>
                    <input name="p" type="password" placeholder="Password" required>
                    <button class="btn btn-add" type="submit">Login</button>
                </form>
            </div>
        {% else %}
            <header>
                <img src="{{logo}}" class="logo">
                <div style="flex-grow:1">
                    <h2 style="margin:0">UPK ZIVPN Panel</h2>
                    <small>Control Center</small>
                </div>
                <a href="/logout" class="btn btn-del">Logout</a>
            </header>

            <div class="box">
                <h3><i class="fas fa-user-plus"></i> User {{ 'ပြင်ဆင်ရန်' if edit_data else 'အသစ်ထည့်ရန်' }}</h3>
                <form method="POST" action="/add">
                    <div style="display:grid; grid-template-columns: 1fr 1fr; gap:10px;">
                        <input name="user" placeholder="Username" value="{{edit_data.user if edit_data else ''}}" required>
                        <input name="password" placeholder="Password" value="{{edit_data.password if edit_data else ''}}" required>
                        <select onchange="if(this.value!='') document.getElementById('exp').value=this.value">
                            <option value="">-- သက်တမ်းရွေးရန် --</option>
                            <option value="30">၁ လ (ရက် ၃၀)</option>
                            <option value="60">၂ လ (ရက် ၆၀)</option>
                            <option value="90">၃ လ (ရက် ၉၀)</option>
                        </select>
                        <input type="date" name="expires" id="exp" value="{{edit_data.expires if edit_data else ''}}">
                    </div>
                    <button class="btn btn-add" type="submit"><i class="fas fa-save"></i> Save & Sync</button>
                </form>
            </div>

            <table>
                <tr>
                    <th>Username</th>
                    <th>Password</th>
                    <th>Expires</th>
                    <th>Status</th>
                    <th>Actions</th>
                </tr>
                {% for u in users %}
                <tr class="{{ 'disabled' if u.disabled else '' }}">
                    <td><b>{{u.user}}</b></td>
                    <td><code>{{u.password}}</code></td>
                    <td>{{u.expires}}</td>
                    <td>
                        {% if u.disabled %}<span style="color:gray">Paused</span>
                        {% elif u.status == 'Online' %}<span class="status-on">● Online</span>
                        {% else %}<span class="status-off">○ Offline</span>{% endif %}
                    </td>
                    <td>
                        <div style="display:flex; gap:5px;">
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
    with open(path, "r") as f: return json.load(f)

def write_json(path, data):
    with open(path, "w") as f: json.dump(data, f, indent=2)

def sync():
    users = read_json(USERS_FILE)
    passwords = [u['password'] for u in users if not u.get('disabled', False)]
    cfg = read_json(CONFIG_FILE)
    cfg['auth']['config'] = passwords
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
    sync()
    return redirect(url_for("index"))

@app.route("/toggle")
def toggle():
    name = request.args.get("user")
    users = read_json(USERS_FILE)
    for u in users:
        if u['user'] == name:
            u['disabled'] = not u.get('disabled', False)
    write_json(USERS_FILE, users)
    sync()
    return redirect(url_for("index"))

@app.route("/delete", methods=["POST"])
def delete():
    name = request.form.get("user")
    users = [u for u in read_json(USERS_FILE) if u['user'] != name]
    write_json(USERS_FILE, users)
    sync()
    return redirect(url_for("index"))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY

# ===== Systemd Services =====
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

# ===== Networking =====
sysctl -w net.ipv4.ip_forward=1 >/dev/null
IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
ufw allow 5667/udp >/dev/null
ufw allow 6000:19999/udp >/dev/null
ufw allow 8080/tcp >/dev/null

# ===== Start =====
systemctl daemon-reload
systemctl enable --now zivpn zivpn-web
IP=$(hostname -I | awk '{print $1}')

say "\n$G✅ အားလုံး အောင်မြင်စွာ တပ်ဆင်ပြီးပါပြီ!$Z"
say "$B🌐 Web Panel:$Z $Y http://$IP:8080 $Z"
say "$B👤 User/Pass:$Z $Y $WEB_USER / $WEB_PASS $Z"
