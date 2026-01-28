 
#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - Improved UI Version
# Author mix: Zahid Islam + KSO tweaks + U PHOE KAUNT polish

set -euo pipefail

# ===== Pretty Colors =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP Server + Web UI ကို U PHOE KAUNT မှ ပြုပြင်ထားသည်${Z}\n$LINE"

# ===== Root check =====
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}ဤ script ကို root အဖြစ် run ရပါမယ် (sudo -i)${Z}"; exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ===== apt guards =====
wait_for_apt() {
  echo -e "${Y}⏳ apt process ပြီးအောင် စောင့်နေပါတယ်...${Z}"
  systemctl stop --now unattended-upgrades.service 2>/dev/null || true
}

# ===== Packages Installation =====
echo -e "${Y}📦 လိုအပ်သော Packages များ တင်နေပါတယ်...${Z}"
wait_for_apt
apt-get update -y >/dev/null
apt-get install -y curl ufw jq python3 python3-flask python3-apt iproute2 conntrack ca-certificates openssl >/dev/null

# Stop old services
systemctl stop zivpn.service 2>/dev/null || true
systemctl stop zivpn-web.service 2>/dev/null || true

# ===== Paths & Folders =====
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"
mkdir -p /etc/zivpn

# ===== Download ZIVPN Binary =====
echo -e "${Y}⬇️ ZIVPN binary ကို ဒေါင်းလုဒ်ဆွဲနေပါတယ်...${Z}"
curl -fsSL -o "$BIN" "https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
chmod +x "$BIN"

# ===== SSL Certs =====
if [ ! -f /etc/zivpn/zivpn.crt ]; then
  openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=UPK/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# ===== Web Admin Credentials =====
echo -e "${Y}🔒 Web Panel အတွက် Login အချက်အလက်များ သတ်မှတ်ပါ${Z}"
read -r -p "Admin Username: " WEB_USER
read -r -s -p "Admin Password: " WEB_PASS; echo
WEB_SECRET=$(openssl rand -hex 16)

{
  echo "WEB_ADMIN_USER=${WEB_USER}"
  echo "WEB_ADMIN_PASSWORD=${WEB_PASS}"
  echo "WEB_SECRET=${WEB_SECRET}"
} > "$ENVF"
chmod 600 "$ENVF"

# ===== Default config.json =====
if [ ! -f "$CFG" ]; then
  echo '{"auth":{"mode":"passwords","config":["zi"]},"listen":":5667","obfs":"zivpn"}' > "$CFG"
fi
[ -f "$USERS" ] || echo "[]" > "$USERS"

# ===== Python Web Panel Script =====
cat > /etc/zivpn/web.py << 'PY'
import os, json, subprocess, hmac, re, tempfile
from flask import Flask, render_template_string, request, redirect, url_for, session, jsonify, make_response
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "change-me-secret")
USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"

LOGO_URL = "https://raw.githubusercontent.com/Upk123/upkvip-ziscript/refs/heads/main/20251018_231111.png"

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="my">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>KSO ZIVPN Panel</title>
    <style>
        :root { --primary: #2563eb; --bg: #f8fafc; --card: #ffffff; --text: #1e293b; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: var(--bg); color: var(--text); margin: 0; padding: 20px; }
        .container { max-width: 900px; margin: auto; }
        .header { display: flex; align-items: center; gap: 15px; background: var(--card); padding: 20px; border-radius: 15px; box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1); margin-bottom: 20px; }
        .logo { width: 60px; height: 60px; border-radius: 12px; }
        .card { background: var(--card); padding: 20px; border-radius: 15px; box-shadow: 0 4px 6px -1px rgb(0 0 0 / 0.1); margin-bottom: 20px; }
        input, button { padding: 12px; border-radius: 8px; border: 1px solid #ddd; margin-bottom: 10px; }
        .btn { background: var(--primary); color: white; border: none; cursor: pointer; font-weight: bold; }
        .btn-red { background: #ef4444; }
        .btn-outline { background: transparent; border: 1px solid var(--primary); color: var(--primary); }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { text-align: left; padding: 12px; border-bottom: 1px solid #eee; }
        .status-on { color: #10b981; font-weight: bold; }
        .status-off { color: #ef4444; }
        .expired { background: #fff1f2; }
        @media (max-width: 600px) { th:nth-child(3), td:nth-child(3) { display: none; } }
    </style>
    <script>
        function setDays(days) {
            let d = new Date();
            d.setDate(d.getDate() + days);
            document.getElementById('exp_date').value = d.toISOString().split('T')[0];
        }
    </script>
</head>
<body>
    <div class="container">
        {% if not session.get('auth') %}
        <div class="card" style="max-width: 400px; margin: 100px auto; text-align: center;">
            <img src="{{ logo }}" class="logo">
            <h2>Admin Login</h2>
            <form method="POST" action="/login">
                <input type="text" name="u" placeholder="Username" style="width:90%" required><br>
                <input type="password" name="p" placeholder="Password" style="width:90%" required><br>
                <button type="submit" class="btn" style="width:95%">Login</button>
            </form>
        </div>
        {% else %}
        <div class="header">
            <img src="{{ logo }}" class="logo">
            <div style="flex-grow:1">
                <h2 style="margin:0">DEV-U PHOE KAUNT</h2>
                <span style="color:gray; font-size: 0.9em;">ZIVPN Management Panel</span>
            </div>
            <a href="/logout" style="text-decoration:none; color:red; font-weight:bold;">Logout</a>
        </div>

        <div class="card">
            <h3>➕ အသုံးပြုသူအသစ်ထည့်ရန်</h3>
            <form method="POST" action="/add" style="display: flex; flex-direction: column;">
                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px;">
                    <input type="text" name="user" placeholder="နာမည် (User)" required>
                    <input type="text" name="password" placeholder="စကားဝှက် (Pass)" required>
                </div>
                <div style="display: flex; gap: 10px; align-items: center; flex-wrap: wrap;">
                    <input type="date" name="expires" id="exp_date" style="flex-grow: 1;">
                    <button type="button" class="btn-outline" onclick="setDays(30)">၁ လစာ</button>
                    <button type="button" class="btn-outline" onclick="setDays(60)">၂ လစာ</button>
                </div>
                <button type="submit" class="btn">သိမ်းဆည်းမည်</button>
            </form>
        </div>

        <div class="card">
            <h3>👥 အသုံးပြုသူစာရင်း</h3>
            <table>
                <thead>
                    <tr>
                        <th>User</th>
                        <th>Status</th>
                        <th>Expires</th>
                        <th>Action</th>
                    </tr>
                </thead>
                <tbody>
                    {% for u in users %}
                    <tr class="{{ 'expired' if u.is_expired }}">
                        <td><b>{{ u.user }}</b><br><small style="color:gray">PW: {{ u.password }}</small></td>
                        <td><span class="{{ 'status-on' if u.status == 'Online' else 'status-off' }}">● {{ u.status }}</span></td>
                        <td>{{ u.expires }}</td>
                        <td>
                            <form method="POST" action="/delete" style="margin:0;">
                                <input type="hidden" name="user" value="{{ u.user }}">
                                <button type="submit" class="btn-red" style="padding: 5px 10px; font-size: 0.8em;" onclick="return confirm('ဖျက်မှာ သေချာပါသလား?')">ဖျက်မည်</button>
                            </form>
                        </td>
                    </tr>
                    {% endfor %}
                </tbody>
            </table>
        </div>
        {% endif %}
    </div>
</body>
</html>
"""

def load_data():
    try:
        with open(USERS_FILE, "r") as f: return json.load(f)
    except: return []

def save_data(data):
    with open(USERS_FILE, "w") as f: json.dump(data, f, indent=2)
    # Sync to config.json
    try:
        with open(CONFIG_FILE, "r") as f: cfg = json.load(f)
        cfg["auth"]["config"] = [u["password"] for u in data]
        with open(CONFIG_FILE, "w") as f: json.dump(cfg, f, indent=2)
        subprocess.run(["systemctl", "restart", "zivpn.service"])
    except: pass

@app.route("/")
def index():
    if not session.get("auth"): return render_template_string(HTML_TEMPLATE, logo=LOGO_URL)
    users = load_data()
    today = datetime.now().strftime("%Y-%m-%d")
    # Check online status using conntrack (simplified)
    for u in users:
        u["is_expired"] = u["expires"] < today if u["expires"] else False
        u["status"] = "Offline" # Placeholder - you can implement real check here
    return render_template_string(HTML_TEMPLATE, users=users, logo=LOGO_URL)

@app.route("/login", methods=["POST"])
def login():
    u, p = request.form.get("u"), request.form.get("p")
    if u == os.environ.get("WEB_ADMIN_USER") and p == os.environ.get("WEB_ADMIN_PASSWORD"):
        session["auth"] = True
    return redirect(url_for("index"))

@app.route("/logout")
def logout():
    session.pop("auth", None)
    return redirect(url_for("index"))

@app.route("/add", methods=["POST"])
def add():
    user = request.form.get("user")
    pw = request.form.get("password")
    exp = request.form.get("expires")
    if user and pw:
        data = load_data()
        data = [u for u in data if u["user"] != user]
        data.append({"user": user, "password": pw, "expires": exp})
        save_data(data)
    return redirect(url_for("index"))

@app.route("/delete", methods=["POST"])
def delete():
    user = request.form.get("user")
    data = load_data()
    data = [u for u in data if u["user"] != user]
    save_data(data)
    return redirect(url_for("index"))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY

# ===== Systemd Services =====
cat > /etc/systemd/system/zivpn.service << EOF
[Unit]
Description=ZIVPN UDP Server
After=network.target
[Service]
ExecStart=$BIN server -c $CFG
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/zivpn-web.service << EOF
[Unit]
Description=ZIVPN Web Panel
After=network.target
[Service]
EnvironmentFile=$ENVF
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
User=root
[Install]
WantedBy=multi-user.target
EOF

# ===== Networking =====
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A PREROUTING -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A POSTROUTING -j MASQUERADE
ufw allow 5667/udp
ufw allow 6000:19999/udp
ufw allow 8080/tcp

# ===== Start Services =====
systemctl daemon-reload
systemctl enable --now zivpn zivpn-web

MY_IP=$(hostname -I | awk '{print $1}')
echo -e "$LINE"
echo -e "${G}✅ တပ်ဆင်မှု အောင်မြင်ပါသည်။${Z}"
echo -e "${C}Web Panel URL :${Z} ${Y}http://$MY_IP:8080${Z}"
echo -e "$LINE"
