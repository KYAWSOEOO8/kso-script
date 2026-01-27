#!/bin/bash
# KSO ZIVPN - ULTRA 3D NEUMORPHIC EDITION

# Colors
G="\e[1;32m"; B="\e[1;34m"; Z="\e[0m"

echo -e "${G}🚀 3D UI Version ကို တင်ပေးနေပါပြီ...${Z}"

cat >/etc/zivpn/web.py <<'PY'
from flask import Flask, render_template_string, request, redirect, url_for
import json, os, subprocess
from datetime import datetime, timedelta

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LOGO_URL = "https://raw.githubusercontent.com/KYAWSOEOO8/kso-script/blob/main/icon.png"

app = Flask(__name__)

def read_db():
    try:
        with open(USERS_FILE, 'r') as f: return json.load(f)
    except: return []

def write_db(data):
    with open(USERS_FILE, 'w') as f: json.dump(data, f, indent=2)

def sync_vpn():
    users = read_db()
    active_pws = [u['password'] for u in users if u.get('status', 'active') == 'active']
    try:
        with open(CONFIG_FILE, 'r') as f: cfg = json.load(f)
        cfg['auth']['config'] = active_pws
        with open(CONFIG_FILE, 'w') as f: json.dump(cfg, f, indent=2)
        subprocess.run(["systemctl", "restart", "zivpn"], stderr=subprocess.DEVNULL)
    except: pass

HTML = """<!doctype html>
<html>
<head>
    <meta charset="utf-8">
    <title>KSO ZIVPN 3D PREMIUM</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;600;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg: #1e293b;
            --top-shadow: rgba(255, 255, 255, 0.05);
            --bottom-shadow: rgba(0, 0, 0, 0.5);
            --accent: #3b82f6;
            --text: #e2e8f0;
        }
        body { 
            background-color: var(--bg); 
            color: var(--text); 
            font-family: 'Poppins', sans-serif; 
            margin: 0; padding: 20px; 
            display: flex; justify-content: center;
        }
        .container { max-width: 1000px; width: 100%; }
        
        /* 3D Glass Header */
        .header {
            text-align: center; margin-bottom: 40px;
            padding: 20px; border-radius: 30px;
            background: linear-gradient(145deg, #222e42, #1b2535);
            box-shadow: 10px 10px 20px var(--bottom-shadow), -10px -10px 20px var(--top-shadow);
        }
        .header img {
            height: 100px; border-radius: 50%;
            border: 4px solid var(--bg);
            box-shadow: 0 0 20px var(--accent), inset 0 0 10px var(--accent);
            margin-bottom: 15px;
        }

        /* Neumorphic 3D Card */
        .card-3d {
            background: #1e293b;
            border-radius: 25px;
            padding: 30px;
            margin-bottom: 30px;
            box-shadow: 12px 12px 24px var(--bottom-shadow), -12px -12px 24px var(--top-shadow);
        }

        /* Input Styling */
        input {
            background: #1e293b;
            border: none;
            padding: 15px; border-radius: 12px;
            color: white; margin-bottom: 10px;
            box-shadow: inset 6px 6px 12px var(--bottom-shadow), inset -6px -6px 12px var(--top-shadow);
            outline: none; width: 100%; box-sizing: border-box;
        }

        /* 3D Button */
        .btn-3d {
            padding: 12px 24px; border-radius: 12px;
            border: none; cursor: pointer; font-weight: 700;
            background: var(--accent); color: white;
            box-shadow: 4px 4px 8px var(--bottom-shadow), -4px -4px 8px var(--top-shadow);
            transition: all 0.2s; text-decoration: none; display: inline-block;
        }
        .btn-3d:active {
            box-shadow: inset 4px 4px 8px var(--bottom-shadow), inset -4px -4px 8px var(--top-shadow);
            transform: translateY(2px);
        }

        /* Table 3D Style */
        table { width: 100%; border-collapse: separate; border-spacing: 0 15px; }
        tr { 
            background: #1e293b;
            box-shadow: 6px 6px 12px var(--bottom-shadow), -6px -6px 12px var(--top-shadow);
            border-radius: 15px;
        }
        td { padding: 20px; border: none; }
        td:first-child { border-radius: 15px 0 0 15px; }
        td:last-child { border-radius: 0 15px 15px 0; }

        /* 3D Progress Bar */
        .progress-3d-wrap {
            height: 12px; background: #151d29;
            border-radius: 10px; overflow: hidden;
            box-shadow: inset 2px 2px 4px black; margin-top: 10px;
        }
        .progress-3d-bar {
            height: 100%; border-radius: 10px;
            box-shadow: 0 0 15px rgba(59, 130, 246, 0.5);
        }

        .status-dot {
            height: 10px; width: 10px; border-radius: 50%; display: inline-block;
            margin-right: 5px; box-shadow: 0 0 8px currentColor;
        }
    </style>
</head>
<body>
<div class="container">
    <div class="header">
        <img src="{{ logo }}">
        <h1 style="margin:0; text-shadow: 2px 2px 4px black;">KSO ZIVPN</h1>
        <p style="color:var(--accent); font-weight:600; letter-spacing:2px; margin-top:5px;">3D PREMIUM DASHBOARD</p>
    </div>

    <div class="card-3d">
        <h3 style="margin-top:0; color:var(--accent);">CREATE NEW USER</h3>
        <form method="POST" action="/add" style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px;">
            <input name="user" placeholder="User Name" required>
            <input name="password" placeholder="Password" required>
            <input name="days" placeholder="Validity (Days)" required>
            <button class="btn-3d" type="submit">ACTIVATE NOW</button>
        </form>
    </div>

    <table>
        {% for u in users %}
        {% set remaining = u.rem %}
        {% set p_color = '#10b981' if remaining > 10 else ('#f59e0b' if remaining > 3 else '#f43f5e') %}
        {% set p_width = (remaining / 30 * 100) if remaining < 30 else 100 %}
        <tr style="{{ 'opacity: 0.6;' if u.status == 'disabled' else '' }}">
            <td>
                <div style="font-weight:700; font-size: 1.1rem; color:var(--accent);">{{u.user}}</div>
                <div style="font-size: 0.75rem; color:#94a3b8; margin-top:5px;">Expires: {{u.expires}}</div>
                <div class="progress-3d-wrap">
                    <div class="progress-3d-bar" style="width: {{ p_width }}%; background: {{ p_color }};"></div>
                </div>
            </td>
            <td>
                <div style="font-size:0.8rem; color:#94a3b8;">PASSWORD</div>
                <div style="font-family:monospace;">{{u.password}}</div>
            </td>
            <td>
                <div style="font-size:0.8rem; color:#94a3b8;">PORT</div>
                <div style="font-family:monospace; color:var(--accent);">{{u.port}}</div>
            </td>
            <td style="text-align:right;">
                <div style="display: flex; gap: 10px; justify-content: flex-end;">
                    <button onclick="renewUser('{{u.user}}')" class="btn-3d" style="background:#10b981; font-size:0.7rem;">RENEW</button>
                    <a href="/toggle/{{u.user}}" class="btn-3d" style="background:{{ '#3b82f6' if u.status == 'disabled' else '#f59e0b' }}; font-size:0.7rem;">
                        {{ 'ENABLE' if u.status == 'disabled' else 'DISABLE' }}
                    </a>
                    <a href="/delete/{{u.user}}" onclick="return confirm('Delete?')" class="btn-3d" style="background:#f43f5e; font-size:0.7rem;">DEL</a>
                </div>
            </td>
        </tr>
        {% endfor %}
    </table>
</div>

<script>
function renewUser(user) {
    let days = prompt("ရက်ပေါင်းမည်မျှ တိုးမည်နည်း?", "30");
    if (days) window.location.href = "/extend/" + user + "/" + days;
}
</script>
</body>
</html>"""

@app.route("/")
def index():
    users = read_db()
    today = datetime.now()
    for u in users:
        try:
            exp_date = datetime.strptime(u['expires'], "%Y-%m-%d")
            delta = (exp_date - today).days + 1
            u['rem'] = delta if delta > 0 else 0
        except: u['rem'] = 0
    return render_template_string(HTML, logo=LOGO_URL, users=users)

@app.route("/add", methods=["POST"])
def add():
    user, pw, days = request.form.get("user"), request.form.get("password"), int(request.form.get("days", 30))
    exp = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
    db = read_db()
    db.append({"user": user, "password": pw, "expires": exp, "port": 6000+len(db), "status": "active"})
    write_db(db); sync_vpn()
    return redirect("/")

@app.route("/toggle/<name>")
def toggle(name):
    db = read_db()
    for u in db:
        if u['user'] == name: u['status'] = 'disabled' if u.get('status', 'active') == 'active' else 'active'
    write_db(db); sync_vpn()
    return redirect("/")

@app.route("/delete/<name>")
def delete(name):
    db = [u for u in read_db() if u['user'] != name]
    write_db(db); sync_vpn()
    return redirect("/")

@app.route("/extend/<name>/<int:days>")
def extend(name, days):
    db = read_db()
    today = datetime.now()
    for u in db:
        if u['user'] == name:
            try:
                curr_exp = datetime.strptime(u['expires'], "%Y-%m-%d")
                start_date = max(curr_exp, today)
            except: start_date = today
            u['expires'] = (start_date + timedelta(days=days)).strftime("%Y-%m-%d")
    write_db(db); sync_vpn()
    return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY

systemctl restart zivpn-web
echo -e "${G}✅ ULTRA 3D UI တပ်ဆင်ပြီးပါပြီ။ Refresh နှိပ်ကြည့်ပါ။${Z}"
