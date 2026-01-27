#!/bin/bash
# KSO ZIVPN - Premium Image Save Version
# Version: 4.5 (All Info in Screenshot)
# Author: KSO (Kyaw Soe Oo)

set -euo pipefail

# ===== Web Panel (Python/Flask) =====
cat >/etc/zivpn/web.py <<'PY'
import os, json, subprocess, hmac, datetime
from flask import Flask, render_template_string, request, redirect, url_for, session

app = Flask(__name__)
app.secret_key = os.environ.get("WEB_SECRET", "kso-screenshot-pro")

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"

HTML = """
<!doctype html>
<html lang="my">
<head>
    <meta charset="utf-8">
    <title>KSO ZIVPN PANEL</title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
    <style>
        :root { --main: #0084ff; --dark: #1a1a1a; --success: #28a745; }
        body { font-family: 'Segoe UI', sans-serif; background: #f0f2f5; margin: 0; padding: 10px; }
        .card { background: #fff; border-radius: 20px; padding: 20px; max-width: 500px; margin: auto; box-shadow: 0 5px 20px rgba(0,0,0,0.1); }
        
        /* Screenshot Area - ပုံထဲမှာပေါ်မယ့်အပိုင်း */
        #capture-area { background: var(--dark); color: #fff; padding: 25px; border-radius: 15px; margin-bottom: 20px; border: 2px solid var(--main); }
        .info-title { color: var(--main); font-weight: bold; margin-bottom: 15px; text-align: center; border-bottom: 1px solid #333; padding-bottom: 10px; }
        .info-row { display: flex; justify-content: space-between; margin: 10px 0; font-size: 15px; border-bottom: 1px dashed #444; padding-bottom: 5px; }
        .info-value { color: #00ff00; font-weight: bold; }
        
        .btn { border: none; padding: 12px; border-radius: 10px; cursor: pointer; font-weight: bold; width: 100%; transition: 0.3s; margin-top: 10px; }
        .btn-save { background: #6f42c1; color: #fff; }
        .btn-add { background: var(--main); color: #fff; }
        .btn-renew { background: #ffc107; color: #000; width: auto; padding: 8px 12px; }
        .btn-del { background: #dc3545; color: #fff; width: auto; padding: 8px 12px; }
        
        input { width: 100%; padding: 12px; margin: 5px 0; border: 1px solid #ddd; border-radius: 8px; box-sizing: border-box; }
        table { width: 100%; margin-top: 15px; border-collapse: collapse; }
        td { padding: 10px; border-bottom: 1px solid #eee; font-size: 14px; }
    </style>
</head>
<body>
<div class="card">
    <div align="center" style="margin-bottom:15px;">
        <img src="https://raw.githubusercontent.com/Upk123/upkvip-ziscript/refs/heads/main/20251018_231111.png" width="70" style="border-radius:50%;">
        <h2 style="margin:5px;">KSO ZIVPN</h2>
    </div>

    {% if not session.get('auth') %}
        <form method="POST" action="/login">
            <input type="text" name="u" placeholder="Admin Name" required>
            <input type="password" name="p" placeholder="Admin Pass" required>
            <button type="submit" class="btn btn-add">LOGIN</button>
        </form>
    {% else %}
        <div id="capture-area">
            <div class="info-title"><i class="fas fa-shield-alt"></i> VPN PREMIUM ACCOUNT</div>
            <div class="info-row"><span>1. VSP IP:</span> <span class="info-value">{{vps_ip}}</span></div>
            <div class="info-row"><span>2. Name:</span> <span class="info-value">{{sel_u or '---'}}</span></div>
            <div class="info-row"><span>3. Password:</span> <span class="info-value">{{sel_p or '---'}}</span></div>
            <div class="info-row"><span>Expiry:</span> <span style="color:yellow;">{{sel_e or '---'}}</span></div>
        </div>

        <button onclick="takeScreenshot()" class="btn btn-save"><i class="fas fa-download"></i> Save အပုံဒေါင်းရန်</button>

        <form method="POST" action="/add" style="margin-top:15px;">
            <input type="text" name="user" placeholder="နာမည် (Name)" required>
            <input type="text" name="pass" placeholder="စကားဝှက် (Pass)" required>
            <button type="submit" class="btn btn-add">+ Create Account</button>
        </form>

        <table>
            {% for u in users %}
            <tr>
                <td><b>{{u.user}}</b><br><small>{{u.expiry}}</small></td>
                <td><code>{{u.password}}</code></td>
                <td align="right">
                    <form method="POST" action="/renew" style="display:inline;">
                        <input type="hidden" name="user" value="{{u.user}}">
                        <button type="submit" class="btn btn-renew"><i class="fas fa-sync"></i></button>
                    </form>
                    <form method="POST" action="/del" style="display:inline;">
                        <input type="hidden" name="user" value="{{u.user}}">
                        <button type="submit" class="btn btn-del"><i class="fas fa-trash"></i></button>
                    </form>
                </td>
            </tr>
            {% endfor %}
        </table>
        <br><center><a href="/logout" style="color:#999;font-size:12px;">Logout Session</a></center>
    {% endif %}
</div>

<script>
function takeScreenshot() {
    const area = document.getElementById('capture-area');
    html2canvas(area).then(canvas => {
        const link = document.createElement('a');
        link.download = 'KSO-VPN-Info.png';
        link.href = canvas.toDataURL("image/png");
        link.click();
    });
}
</script>
</body></html>"""

def get_expiry():
    return (datetime.datetime.now() + datetime.timedelta(days=30)).strftime("%Y-%m-%d")

@app.route('/')
def index():
    users = json.load(open(USERS_FILE)) if os.path.exists(USERS_FILE) else []
    try:
        vps_ip = subprocess.check_output(["hostname", "-I"]).decode().split()[0]
    except:
        vps_ip = "138.68.243.84"
    return render_template_string(HTML, users=users, vps_ip=vps_ip, 
                                sel_u=session.get('u'), sel_p=session.get('p'), sel_e=session.get('e'))

@app.route('/login', methods=['POST'])
def login():
    if hmac.compare_digest(request.form.get('u'), os.environ.get("WEB_ADMIN_USER", "admin")) and hmac.compare_digest(request.form.get('p'), os.environ.get("WEB_ADMIN_PASSWORD", "admin")):
        session['auth'] = True
    return redirect('/')

@app.route('/renew', methods=['POST'])
def renew():
    name = request.form.get('user')
    users = json.load(open(USERS_FILE))
    for u in users:
        if u['user'] == name:
            u['expiry'] = get_expiry()
            session['u'], session['p'], session['e'] = u['user'], u['password'], u['expiry']
            break
    json.dump(users, open(USERS_FILE,'w'), indent=2)
    return redirect('/')

@app.route('/add', methods=['POST'])
def add():
    u, p = request.form.get('user'), request.form.get('pass')
    users = json.load(open(USERS_FILE)) if os.path.exists(USERS_FILE) else []
    exp = get_expiry()
    users.append({"user":u, "password":p, "expiry": exp})
    json.dump(users, open(USERS_FILE,'w'), indent=2)
    session['u'], session['p'], session['e'] = u, p, exp
    sync_config(users)
    return redirect('/')

@app.route('/del', methods=['POST'])
def delete():
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

@app.route('/logout')
def logout(): session.clear(); return redirect('/')

if __name__ == "__main__": app.run(host="0.0.0.0", port=8080)
PY

# Restart Service
systemctl restart zivpn-web
