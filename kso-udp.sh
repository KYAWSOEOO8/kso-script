#!/bin/bash
# KSO ZIVPN - Final Fix (Auto Directory Creation)
# Version: 5.0 (All Bug Fixed)

set -euo pipefail

# ===== ၁။ Folder မရှိရင် အော်တိုဆောက်ပေးမည့်အပိုင်း (အရေးကြီးဆုံး) =====
echo "📂 System Folders များ ပြင်ဆင်နေပါသည်..."
sudo mkdir -p /etc/zivpn
sudo chmod 777 /etc/zivpn

# ===== ၂။ အဟောင်းများရှိပါက အရင်ရှင်းထုတ်ခြင်း =====
systemctl stop zivpn zivpn-web 2>/dev/null || true

# ===== ၃။ Web UI Script (web.py) ပြန်ရေးသားခြင်း =====
cat >/etc/zivpn/web.py <<'PY'
import os, json, subprocess, hmac, datetime
from flask import Flask, render_template_string, request, redirect, session

app = Flask(__name__)
app.secret_key = "kso-fixed-key"
USERS_FILE = "/etc/zivpn/users.json"

# HTML UI with Screenshot & IP Info
HTML = """
<!doctype html>
<html lang="my">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
    <style>
        body { font-family: sans-serif; background: #f0f2f5; padding: 10px; }
        .card { background: #fff; border-radius: 15px; padding: 20px; max-width: 450px; margin: auto; box-shadow: 0 5px 15px rgba(0,0,0,0.1); }
        #capture { background: #1a1a1a; color: #fff; padding: 20px; border-radius: 12px; margin-bottom: 15px; border: 2px solid #0084ff; }
        .row { display: flex; justify-content: space-between; margin: 10px 0; border-bottom: 1px dashed #444; padding-bottom: 5px; }
        .val { color: #00ff00; font-weight: bold; }
        .btn { width: 100%; padding: 12px; border-radius: 10px; border: none; cursor: pointer; font-weight: bold; margin-top: 10px; color: #fff; }
        .btn-blue { background: #0084ff; }
        .btn-purple { background: #6f42c1; }
        input { width: 100%; padding: 12px; margin: 5px 0; border: 1px solid #ddd; border-radius: 8px; box-sizing: border-box; }
        table { width: 100%; margin-top: 15px; border-collapse: collapse; }
        td { padding: 10px; border-bottom: 1px solid #eee; font-size: 14px; }
    </style>
</head>
<body>
<div class="card">
    <h2 align="center">KSO ZIVPN PANEL</h2>
    <div id="capture">
        <div align="center" style="color:#0084ff; margin-bottom:10px;">🛡️ ACCOUNT INFO</div>
        <div class="row"><span>1. VPS IP:</span> <span class="val">{{vps_ip}}</span></div>
        <div class="row"><span>2. Name:</span> <span class="val">{{u or '---'}}</span></div>
        <div class="row"><span>3. Password:</span> <span class="val">{{p or '---'}}</span></div>
        <div class="row"><span>Expiry:</span> <span style="color:yellow;">{{e or '---'}}</span></div>
    </div>
    <button onclick="save()" class="btn btn-purple">📸 Save အပုံဒေါင်းရန်</button>
    <form method="POST" action="/add"><input name="user" placeholder="နာမည်" required><input name="pass" placeholder="စကားဝှက်" required><button class="btn btn-blue">Create User</button></form>
    <table>
        {% for user in users %}
        <tr><td><b>{{user.user}}</b><br><small>{{user.expiry}}</small></td><td><code>{{user.password}}</code></td></tr>
        {% endfor %}
    </table>
</div>
<script>
function save() { html2canvas(document.getElementById('capture')).then(c => { let l=document.createElement('a'); l.download='VPN.png'; l.href=c.toDataURL(); l.click(); }); }
</script>
</body></html>"""

@app.route('/')
def index():
    users = json.load(open(USERS_FILE)) if os.path.exists(USERS_FILE) else []
    vps_ip = subprocess.check_output(["hostname", "-I"]).decode().split()[0]
    return render_template_string(HTML, users=users, vps_ip=vps_ip, u=session.get('u'), p=session.get('p'), e=session.get('e'))

@app.route('/add', methods=['POST'])
def add():
    u, p = request.form.get('user'), request.form.get('pass')
    e = (datetime.datetime.now() + datetime.timedelta(days=30)).strftime("%Y-%m-%d")
    users = json.load(open(USERS_FILE)) if os.path.exists(USERS_FILE) else []
    users.append({"user":u, "password":p, "expiry":e})
    with open(USERS_FILE, 'w') as f: json.dump(users, f)
    session['u'], session['p'], session['e'] = u, p, e
    return redirect('/')

if __name__ == "__main__": app.run(host="0.0.0.0", port=8080)
PY

# ===== ၄။ လိုအပ်သော Files များ အော်တိုတည်ဆောက်ခြင်း =====
echo '[]' > /etc/zivpn/users.json
echo '{"auth":{"mode":"passwords","config":[]}}' > /etc/zivpn/config.json

# ===== ၅။ Service တပ်ဆင်ခြင်း =====
cat >/etc/systemd/system/zivpn-web.service <<EOF
[Unit]
After=network.target
[Service]
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now zivpn-web

IP=$(hostname -I | awk '{print $1}')
echo -e "\n✅ အားလုံး အဆင်ပြေသွားပါပြီ။"
echo -e "🌐 Link: http://$IP:8080"
