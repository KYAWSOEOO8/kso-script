#!/bin/bash
# ZIVPN Full Panel (Fixed Login Logic)
set -euo pipefail

# Pretty
G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="\e[1;34m────────────────────────────────────────────────────────${Z}"

# Root check
[[ $(id -u) -ne 0 ]] && { echo -e "${R}sudo -i ဖြင့် run ပါ${Z}"; exit 1; }

# Install packages
apt-get update -y && apt-get install -y curl jq python3 python3-flask conntrack openssl >/dev/null

mkdir -p /etc/zivpn
ENVF="/etc/zivpn/web.env"

# Login Setup
echo -e "${Y}🔐 Web Panel Login အချက်အလက်အသစ် သတ်မှတ်ပါ${Z}"
read -r -p "Username: " WEB_USER
read -r -p "Password: " WEB_PASS
WEB_SECRET=$(openssl rand -hex 32)

cat > "$ENVF" <<EOF
WEB_ADMIN_USER=${WEB_USER}
WEB_ADMIN_PASSWORD=${WEB_PASS}
WEB_SECRET=${WEB_SECRET}
EOF
chmod 600 "$ENVF"

# Web UI Python Script
cat > /etc/zivpn/web.py <<'PY'
import os, json, hmac, subprocess
from flask import Flask, render_template_string, request, redirect, session, url_for
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER")
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD")

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LOGO_URL = "https://raw.githubusercontent.com/Upk123/upkvip-ziscript/refs/heads/main/20251018_231111.png"

# --- HTML Design ---
LOGIN_HTML = """
<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: sans-serif; background: #0f172a; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; color: white; }
        .card { background: #1e293b; padding: 30px; border-radius: 15px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); width: 320px; text-align: center; }
        input { width: 100%; padding: 12px; margin: 10px 0; border-radius: 8px; border: none; background: #334155; color: white; box-sizing: border-box; }
        button { width: 100%; padding: 12px; background: #3b82f6; color: white; border: none; border-radius: 8px; cursor: pointer; font-weight: bold; }
        .logo { height: 70px; border-radius: 12px; margin-bottom: 20px; }
    </style>
</head>
<body>
    <div class="card">
        <img src="{{ logo }}" class="logo">
        <h2>ZIVPN LOGIN</h2>
        <form method="post">
            <input type="text" name="u" placeholder="Username" required>
            <input type="password" name="p" placeholder="Password" required>
            <button type="submit">LOGIN</button>
        </form>
    </div>
</body>
</html>
"""

DASHBOARD_HTML = """
<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: sans-serif; background: #0f172a; color: white; padding: 20px; }
        .container { max-width: 600px; margin: auto; }
        .header { display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #334155; padding-bottom: 10px; }
        .user-box { background: #1e293b; padding: 15px; border-radius: 10px; margin-top: 15px; display: flex; justify-content: space-between; align-items: center; }
        .btn-del { background: #ef4444; color: white; border: none; padding: 5px 10px; border-radius: 5px; cursor: pointer; }
        .form-add { background: #1e293b; padding: 20px; border-radius: 10px; margin-top: 20px; }
        input { padding: 8px; border-radius: 5px; border: none; background: #334155; color: white; margin-bottom: 10px; width: 100%; box-sizing: border-box; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h3>DASHBOARD</h3>
            <a href="/logout" style="color: #94a3b8;">Logout</a>
        </div>
        
        <div class="form-add">
            <h4>Add New VPN User</h4>
            <form method="post" action="/add">
                <input type="text" name="user" placeholder="User Name" required>
                <input type="text" name="pass" placeholder="Password" required>
                <input type="text" name="days" placeholder="Days (e.g. 30)" required>
                <button type="submit" style="width:100%; padding:10px; background:#3b82f6; color:white; border:none; border-radius:5px;">CREATE</button>
            </form>
        </div>

        {% for u in users %}
        <div class="user-box">
            <div>
                <strong>{{ u.user }}</strong><br>
                <small>Expires: {{ u.expires }}</small>
            </div>
            <form method="post" action="/delete">
                <input type="hidden" name="user" value="{{ u.user }}">
                <button type="submit" class="btn-del">DEL</button>
            </form>
        </div>
        {% endfor %}
    </div>
</body>
</html>
"""

def load_users():
    try:
        with open(USERS_FILE, "r") as f: return json.load(f)
    except: return []

@app.route('/', methods=['GET', 'POST'])
def login():
    # Login လုပ်ပြီးသားဆိုရင် Dashboard ကို ပို့မယ်
    if session.get('auth'):
        return redirect(url_for('dashboard'))
    
    if request.method == 'POST':
        u = request.form.get('u')
        p = request.form.get('p')
        if hmac.compare_digest(u, ADMIN_USER) and hmac.compare_digest(p, ADMIN_PASS):
            session['auth'] = True
            return redirect(url_for('dashboard'))
    return render_template_string(LOGIN_HTML, logo=LOGO_URL)

@app.route('/dashboard')
def dashboard():
    # Login မလုပ်ရသေးရင် Dashboard ပေးမဝင်ဘူး
    if not session.get('auth'):
        return redirect(url_for('login'))
    return render_template_string(DASHBOARD_HTML, users=load_users())

@app.route('/add', methods=['POST'])
def add():
    if not session.get('auth'): return redirect('/')
    user, pw, days = request.form.get('user'), request.form.get('pass'), request.form.get('days')
    data = load_users()
    exp = (datetime.now() + timedelta(days=int(days))).strftime("%Y-%m-%d")
    data.append({"user": user, "password": pw, "expires": exp})
    with open(USERS_FILE, "w") as f: json.dump(data, f, indent=2)
    return redirect('/dashboard')

@app.route('/delete', methods=['POST'])
def delete():
    if not session.get('auth'): return redirect('/')
    user = request.form.get('user')
    data = [u for u in load_users() if u["user"] != user]
    with open(USERS_FILE, "w") as f: json.dump(data, f, indent=2)
    return redirect('/dashboard')

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY

# Restart Service
systemctl daemon-reload
systemctl enable --now zivpn-web.service
systemctl restart zivpn-web

echo -e "$LINE\n${G}✅ ပြင်ဆင်ပြီးပါပြီ။ အခု Login အရင်ဝင်ရပါမယ်။${Z}"
echo -e "${C}Login URL: http://$(hostname -I | awk '{print $1}'):8080${Z}\n$LINE"
