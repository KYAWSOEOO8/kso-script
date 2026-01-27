#!/bin/bash
# KSO ZIVPN UDP Server + Web UI (Premium UI Version)
# Version: 3.5 (Renew + 30-Day + Beautiful UI)
# Author: KSO (Kyaw Soe Oo)

set -euo pipefail

# ===== Paths =====
mkdir -p /etc/zivpn
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"

# Root check
[ "$(id -u)" -ne 0 ] && echo "Root အဖြစ် run ပေးပါ" && exit 1

# Installation of Requirements
apt-get update -y && apt-get install -y curl ufw jq python3 python3-flask openssl >/dev/null

# ===== Web Panel (Python/Flask) Premium UI =====
cat >/etc/zivpn/web.py <<'PY'
import os, json, subprocess, hmac, datetime
from flask import Flask, render_template_string, request, redirect, url_for, session

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "kso-billing-premium-sec")

USERS_FILE, CONFIG_FILE = "/etc/zivpn/users.json", "/etc/zivpn/config.json"

HTML = """
<!doctype html>
<html lang="my">
<head>
    <meta charset="utf-8">
    <title>KSO ZIVPN PREMIUM</title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <style>
        :root { --primary: #0084ff; --success: #28a745; --warning: #ffc107; --danger: #dc3545; --dark: #1c1e21; }
        body{ font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f0f2f5; margin: 0; padding: 15px; color: #333; }
        .card{ background: #fff; padding: 25px; border-radius: 20px; max-width: 800px; margin: 20px auto; box-shadow: 0 10px 25px rgba(0,0,0,0.05); border: 1px solid #e1e4e8; }
        .header{ text-align: center; margin-bottom: 30px; }
        .header img { width: 90px; height: 90px; border-radius: 50%; border: 4px solid var(--primary); padding: 5px; margin-bottom: 10px; }
        h2 { margin: 10px 0; color: var(--dark); letter-spacing: 1px; }
        
        .input-group { position: relative; margin-bottom: 15px; }
        input { width: 100%; padding: 12px 15px; border: 2px solid #eee; border-radius: 12px; outline: none; transition: 0.3s; font-size: 15px; box-sizing: border-box; }
        input:focus { border-color: var(--primary); }
        
        .btn { padding: 12px 20px; color: #fff; border: none; border-radius: 12px; cursor: pointer; font-weight: 600; transition: 0.3s; display: inline-flex; align-items: center; justify-content: center; gap: 8px; text-decoration: none; }
        .btn-add { background: var(--primary); width: 100%; margin-top: 10px; font-size: 16px; }
        .btn-add:hover { background: #0073e6; transform: translateY(-2px); }
        .btn-renew { background: var(--warning); color: #000; padding: 8px 15px; font-size: 13px; }
        .btn-del { background: var(--danger); padding: 8px 15px; font-size: 13px; }
        .btn:active { transform: scale(0.98); }

        table { width: 100%; margin-top: 25px; border-collapse: separate; border-spacing: 0 10px; }
        th { padding: 15px; text-align: left; color: #666; font-weight: 500; font-size: 14px; }
        td { padding: 15px; background: #f8f9fa; border: none; font-size: 15px; }
        td:first-child { border-radius: 12px 0 0 12px; font-weight: bold; }
        td:last-child { border-radius: 0 12px 12px 0; }
        
        .badge { padding: 5px 10px; border-radius: 8px; font-size: 12px; font-weight: bold; }
        .badge-date { background: #e7f3ff; color: var(--primary); }
        code { background: #eee; padding: 4px 8px; border-radius: 6px; font-family: monospace; }
        
        .logout { display: block; text-align: center; margin-top: 25px; color: #999; text-decoration: none; font-size: 14px; }
        .logout:hover { color: var(--danger); }
    </style>
</head>
<body>
<div class="card">
    <div class="header">
        <img src="https://raw.githubusercontent.com/Upk123/upkvip-ziscript/refs/heads/main/20251018_231111.png" alt="Logo">
        <h2>KSO ZIVPN PANEL</h2>
        <p style="color: #888;">Modern User Management System</p>
    </div>

    {% if not session.get('auth') %}
        <form method="POST" action="/login">
            <div class="input-group"><input type="text" name="u" placeholder="Admin Username" required></div>
            <div class="input-group"><input type="password" name="p" placeholder="Admin Password" required></div>
            <button type="submit" class="btn btn-add"><i class="fas fa-sign-in-alt"></i> Login to Dashboard</button>
        </form>
    {% else %}
        <form method="POST" action="/add" style="background: #f8f9fa; padding: 20px; border-radius: 15px;">
            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 15px;">
                <div class="input-group"><input type="text" name="user" placeholder="User Name" required></div>
                <div class="input-group"><input type="text" name="pass" placeholder="VPN Password" required></div>
            </div>
            <button type="submit" class="btn btn-add"><i class="fas fa-user-plus"></i> Create 30 Days Account</button>
        </form>

        <table>
            <thead>
                <tr>
                    <th>NAME</th>
                    <th>PASSWORD</th>
                    <th>EXPIRY DATE</th>
                    <th>ACTIONS</th>
                </tr>
            </thead>
            <tbody>
                {% for u in users %}
                <tr>
                    <td>{{u.user}}</td>
                    <td><code>{{u.password}}</code></td>
                    <td><span class="badge badge-date"><i class="far fa-calendar-alt"></i> {{u.expiry}}</span></td>
                    <td>
                        <div style="display:flex; gap: 8px;">
                            <form method="POST" action="/renew">
                                <input type="hidden" name="user" value="{{u.user}}">
                                <button type="submit" class="btn btn-renew" title="Renew 30 Days"><i class="fas fa-sync-alt"></i></button>
                            </form>
                            <form method="POST" action="/del" onsubmit="return confirm('ဖျက်မှာ သေချာပါသလား?')">
                                <input type="hidden" name="user" value="{{u.user}}">
                                <button type="submit" class="btn btn-del" title="Delete User"><i class="fas fa-trash-alt"></i></button>
                            </form>
                        </div>
                    </td>
                </tr>
                {% endfor %}
            </tbody>
        </table>
        <a href="/logout" class="logout"><i class="fas fa-power-off"></i> Logout Session</a>
    {% endif %}
</div>
</body></html>"""

def get_expiry():
    return (datetime.datetime.now() + datetime.timedelta(days=30)).strftime("%Y-%m-%d")

@app.route('/')
def index():
    users = json.load(open(USERS_FILE)) if os.path.exists(USERS_FILE) else []
    return render_template_string(HTML, users=users)

@app.route('/login', methods=['POST'])
def login():
    if hmac.compare_digest(request.form.get('u'), os.environ.get("WEB_ADMIN_USER", "admin")) and hmac.compare_digest(request.form.get('p'), os.environ.get("WEB_ADMIN_PASSWORD", "admin")):
        session['auth'] = True
    return redirect('/')

@app.route('/logout')
def logout(): session.pop('auth', None); return redirect('/')

@app.route('/add', methods=['POST'])
def add():
    if not session.get('auth'): return redirect('/')
    u, p = request.form.get('user'), request.form.get('pass')
    users = json.load(open(USERS_FILE)) if os.path.exists(USERS_FILE) else []
    users.append({"user":u, "password":p, "expiry": get_expiry()})
    json.dump(users, open(USERS_FILE,'w'), indent=2)
    sync_config(users)
    return redirect('/')

@app.route('/renew', methods=['POST'])
def renew():
    if not session.get('auth'): return redirect('/')
    name = request.form.get('user')
    users = json.load(open(USERS_FILE))
    for u in users:
        if u['user'] == name:
            u['expiry'] = get_expiry()
            break
    json.dump(users, open(USERS_FILE,'w'), indent=2)
    return redirect('/')

@app.route('/del', methods=['POST'])
def delete():
    if not session.get('auth'): return redirect('/')
    name = request.form.get('user')
    users = [u for u in json.load(open(USERS_FILE)) if u['user'] != name]
    json.dump(users, open(USERS_FILE,'w'), indent=2)
    sync_config(users)
    return redirect('/')

def sync_config(users):
    if os.path.exists(CONFIG_FILE):
        cfg = json.load(open(CONFIG_FILE))
        cfg['auth']['config'] = [x['password'] for x in users]
        json.dump(cfg, open(CONFIG_FILE,'w'), indent=2)
        subprocess.run(["systemctl", "restart", "zivpn"])

if __name__ == "__main__": app.run(host="0.0.0.0", port=8080)
PY

# Update Systemd and Permissions
systemctl restart zivpn-web
echo "Update အောင်မြင်ပါသည်။ UI အသစ်ကို Browser မှာ Refresh လုပ်ကြည့်ပါ။"

