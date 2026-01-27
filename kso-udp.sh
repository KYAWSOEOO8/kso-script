#!/bin/bash
# KSO ZIVPN - NEUMORPHIC 3D VERSION (FIXED DOWNLOAD & LOGO)

cat > /etc/zivpn/web.py << 'PY'
from flask import Flask, render_template_string, request, redirect
import json, os, subprocess
from datetime import datetime, timedelta

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LOGO_URL = "https://raw.githubusercontent.com/KYAWSOEOO8/kso-script/blob/main/icon.png"

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

app = Flask(__name__)

HTML = """<!doctype html>
<html>
<head>
    <meta charset="utf-8"><title>KSO ZIVPN 3D</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
    <style>
        :root { --bg: #1a222d; --accent: #3b82f6; --neu-out: 10px 10px 20px #131921, -10px -10px 20px #212b39; --neu-in: inset 6px 6px 12px #131921, inset -6px -6px 12px #212b39; }
        body { background: var(--bg); color: #e2e8f0; font-family: 'Segoe UI', sans-serif; margin: 0; padding: 15px; text-align: center; }
        .logo-box { width: 70px; height: 70px; border-radius: 20px; background: var(--bg); box-shadow: var(--neu-out); margin: 0 auto 10px; padding: 10px; }
        .logo-box img { width: 100%; height: 100%; border-radius: 15px; }
        .card { background: var(--bg); border-radius: 25px; box-shadow: var(--neu-out); padding: 25px; margin: 20px auto; max-width: 400px; }
        .input-box { background: var(--bg); border: none; padding: 15px; border-radius: 15px; color: #fff; width: 85%; margin: 10px 0; outline: none; box-shadow: var(--neu-in); }
        .btn-main { background: var(--accent); color: white; border: none; padding: 15px; border-radius: 15px; width: 93%; font-weight: bold; cursor: pointer; margin-top: 10px; box-shadow: var(--neu-out); }
        .btn-main:active { box-shadow: var(--neu-in); transform: scale(0.98); }
        .u-item { background: var(--bg); padding: 20px; border-radius: 20px; margin: 20px auto; max-width: 420px; box-shadow: var(--neu-out); text-align: left; display: flex; justify-content: space-between; align-items: center; }
        .u-info b { color: var(--accent); font-size: 1.2rem; }
        .u-info div { font-size: 0.8rem; color: #94a3b8; margin-top: 5px; }
        .prog { height: 8px; width: 100px; background: var(--bg); border-radius: 10px; margin-top: 8px; box-shadow: var(--neu-in); overflow: hidden; }
        .prog-f { height: 100%; border-radius: 10px; }
        .btn-group { display: flex; flex-direction: column; gap: 8px; }
        .icon-btn { width: 75px; height: 32px; border-radius: 10px; display: flex; align-items: center; justify-content: center; color: white; text-decoration: none; border: none; cursor: pointer; font-size: 0.7rem; font-weight: bold; box-shadow: var(--neu-out); }
        .icon-btn:active { box-shadow: var(--neu-in); }
        #slip-ui { background: var(--bg); padding: 30px; border-radius: 20px; position: fixed; left: -9999px; width: 300px; text-align: center; }
    </style>
</head>
<body>
    <div class="logo-box"><img src="{{ logo }}"></div>
    <h2 style="margin:0; text-shadow: 2px 2px #000;">KSO ZIVPN</h2>
    <p style="color:var(--accent); font-size:0.75rem; font-weight:bold; letter-spacing:2px;">PREMIUM SERVICE BY UPK</p>

    <div class="card">
        <form id="u-form" method="POST" action="/add">
            <input type="hidden" name="old_user" id="old_user">
            <input name="user" id="i_user" class="input-box" placeholder="User Name" required>
            <input name="password" id="i_pass" class="input-box" placeholder="Password" required>
            <input name="days" id="i_days" class="input-box" placeholder="Days" required style="width: 40%; display: inline-block;">
            <button class="btn-main" type="submit" onclick="saveSlip()"><i class="fa-solid fa-download"></i> CREATE & SAVE</button>
        </form>
    </div>

    <div id="slip-ui">
        <div class="logo-box" style="box-shadow: none;"><img src="{{ logo }}"></div>
        <h3 style="color:var(--accent);">KSO ZIVPN SLIP</h3>
        <div style="background: var(--bg); box-shadow: var(--neu-in); padding: 15px; border-radius: 15px; text-align: left;">
            <p>User: <b id="s_u"></b></p>
            <p>Pass: <b id="s_p"></b></p>
            <p>Days: <b id="s_d"></b></p>
        </div>
        <p style="font-size: 10px; margin-top: 15px;">Thank you for using UPK Service</p>
    </div>

    {% for u in users %}
    <div class="u-item" style="{{ 'opacity: 0.5;' if u.status == 'disabled' else '' }}">
        <div class="u-info">
            <b>{{u.user}}</b>
            <div>Exp: {{u.expires}} ({{u.rem}} days)</div>
            <div>Port: {{u.port}} | Pass: {{u.password}}</div>
            <div class="prog">
                <div class="prog-f" style="width:{{ (u.rem/30)*100 if u.rem < 30 else 100 }}%; background:{{ '#10b981' if u.rem > 10 else '#f43f5e' }};"></div>
            </div>
        </div>
        <div class="btn-group">
            <button onclick="editU('{{u.user}}','{{u.password}}','{{u.rem}}')" class="icon-btn" style="background:#10b981;">RENEW</button>
            <a href="/toggle/{{u.user}}" class="icon-btn" style="background:#f59e0b;">{{ 'ENABLE' if u.status == 'disabled' else 'DISABLE' }}</a>
            <a href="/delete/{{u.user}}" class="icon-btn" style="background:#f43f5e;">DEL</a>
        </div>
    </div>
    {% endfor %}

    <script>
    function editU(n, p, d) {
        document.getElementById('old_user').value = n;
        document.getElementById('i_user').value = n;
        document.getElementById('i_pass').value = p;
        document.getElementById('i_days').value = d;
        window.scrollTo({top: 0, behavior: 'smooth'});
    }

    function saveSlip() {
        const n = document.getElementById('i_user').value;
        const p = document.getElementById('i_pass').value;
        const d = document.getElementById('i_days').value;
        if(!n || !p) return;
        document.getElementById('s_u').innerText = n;
        document.getElementById('s_p').innerText = p;
        document.getElementById('s_d').innerText = d;
        const slip = document.getElementById('slip-ui');
        html2canvas(slip, {backgroundColor: "#1a222d"}).then(canvas => {
            const link = document.createElement('a');
            link.download = n + '_slip.png';
            link.href = canvas.toDataURL();
            link.click();
        });
    }
    </script>
</body>
</html>"""

@app.route("/")
def index():
    users = read_db()
    for u in users:
        try:
            delta = (datetime.strptime(u['expires'], "%Y-%m-%d") - datetime.now()).days + 1
            u['rem'] = delta if delta > 0 else 0
        except: u['rem'] = 0
    return render_template_string(HTML, logo=LOGO_URL, users=users)

@app.route("/add", methods=["POST"])
def add():
    old_user = request.form.get("old_user")
    user, pw, days = request.form.get("user"), request.form.get("password"), int(request.form.get("days"))
    db = read_db()
    if old_user: db = [u for u in db if u['user'] != old_user]
    exp = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
    db.append({"user": user, "password": pw, "expires": exp, "port": 6000+len(db), "status": "active"})
    write_db(db); sync_vpn(); return redirect("/")

@app.route("/toggle/<name>")
def toggle(name):
    db = read_db()
    for u in db:
        if u['user'] == name: u['status'] = 'disabled' if u.get('status','active') == 'active' else 'active'
    write_db(db); sync_vpn(); return redirect("/")

@app.route("/delete/<name>")
def delete(name):
    db = [u for u in read_db() if u['user'] != name]
    write_db(db); sync_vpn(); return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY

pkill -f web.py
nohup python3 /etc/zivpn/web.py > /dev/null 2>&1 &
echo "✅ Neumorphic UI Version အဆင်သင့်ဖြစ်ပါပြီ။ Refresh လုပ်ကြည့်ပါ။"
