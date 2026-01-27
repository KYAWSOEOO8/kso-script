#!/bin/bash
# KSO ZIVPN - AUTO DOWNLOAD IMAGE & EDIT FEATURE

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

app = Flask(__name__)

HTML = """<!doctype html>
<html>
<head>
    <meta charset="utf-8">
    <title>KSO ZIVPN PRO</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
    <style>
        :root { --bg: #0f172a; --card: #1e293b; --accent: #3b82f6; --safe: #10b981; }
        body { background: var(--bg); color: #e2e8f0; font-family: sans-serif; margin: 0; padding: 15px; }
        .card-3d { background: var(--card); border-radius: 20px; padding: 20px; margin: 10px auto; max-width: 450px;
                box-shadow: 10px 10px 20px #000; text-align: center; }
        input { background: #0f172a; border: 1px solid #334155; padding: 12px; border-radius: 10px; color: #fff; 
                width: 85%; margin: 8px 0; outline: none; }
        .btn-main { background: var(--accent); color: white; border: none; padding: 12px; border-radius: 10px;
                    width: 90%; font-weight: bold; cursor: pointer; margin-top: 10px; }
        .user-card { background: var(--card); border-radius: 15px; padding: 15px; margin: 15px auto; max-width: 450px;
                     display: flex; align-items: center; justify-content: space-between; box-shadow: 5px 5px 15px #000; }
        .icon-btn { width: 35px; height: 35px; border-radius: 8px; display: flex; align-items: center; justify-content: center;
                    color: white; text-decoration: none; margin-bottom: 5px; cursor: pointer; border: none; }
        
        /* Account Style for Image Download */
        #account-slip { background: linear-gradient(135deg, #1e293b, #0f172a); padding: 20px; border-radius: 15px;
                        border: 2px solid var(--accent); display: none; width: 300px; margin: 20px auto; }
    </style>
</head>
<body>
    <img src="{{ logo }}" style="height:70px; border-radius:50%; border:3px solid var(--accent); display: block; margin: 0 auto;">
    <h2 style="text-align:center; margin: 5px 0;">KSO ZIVPN</h2>

    <div class="card-3d">
        <form id="user-form" method="POST" action="/add">
            <input type="hidden" name="old_user" id="old_user">
            <input name="user" id="in_user" placeholder="Name 1" required>
            <input name="password" id="in_pass" placeholder="Password 2" required>
            <input name="days" id="in_days" placeholder="Validity Days 3" required>
            <button class="btn-main" type="submit" onclick="startDownload()"><i class="fa-solid fa-save"></i> SAVE & DOWNLOAD 4</button>
        </form>
    </div>

    <div id="account-slip">
        <h3 style="color:var(--accent); margin:0;">KSO ZIVPN PREMIUM</h3>
        <hr style="border:0.5px solid #334155;">
        <p>User: <span id="slip-user" style="color:white; font-weight:bold;"></span></p>
        <p>Pass: <span id="slip-pass" style="color:white; font-weight:bold;"></span></p>
        <p>Exp: <span id="slip-exp" style="color:white; font-weight:bold;"></span></p>
        <p style="font-size:10px; color:#94a3b8;">Thank you for using our service!</p>
    </div>

    {% for u in users %}
    <div class="user-card">
        <div style="flex-grow:1;">
            <b style="color:var(--accent); font-size:1.1rem;">{{u.user}}</b><br>
            <small style="color:#94a3b8;">{{u.expires}} ({{u.rem}} days)</small>
        </div>
        <div style="display:flex; flex-direction:column;">
            <button onclick="editUser('{{u.user}}', '{{u.password}}', '{{u.rem}}')" class="icon-btn" style="background:var(--safe);"><i class="fa-solid fa-rotate-right"></i></button>
            <a href="/delete/{{u.user}}" class="icon-btn" style="background:#f43f5e;"><i class="fa-solid fa-trash"></i></a>
        </div>
    </div>
    {% endfor %}

    <script>
    // Renew နှိပ်ရင် အချက်အလက်တွေ အပေါ်က Form မှာ ပြန်ဖြည့်မယ်
    function editUser(name, pass, days) {
        document.getElementById('old_user').value = name;
        document.getElementById('in_user').value = name;
        document.getElementById('in_pass').value = pass;
        document.getElementById('in_days').value = days;
        window.scrollTo({top: 0, behavior: 'smooth'});
    }

    // Save နှိပ်ရင် ပုံအဖြစ် သိမ်းမယ်
    function startDownload() {
        const name = document.getElementById('in_user').value;
        const pass = document.getElementById('in_pass').value;
        const days = document.getElementById('in_days').value;
        
        if(!name || !pass) return;

        // Slip မှာ အချက်အလက်ဖြည့်
        document.getElementById('slip-user').innerText = name;
        document.getElementById('slip-pass').innerText = pass;
        document.getElementById('slip-exp').innerText = days + " Days";
        
        const slip = document.getElementById('account-slip');
        slip.style.display = 'block';

        html2canvas(slip).then(canvas => {
            const link = document.createElement('a');
            link.download = name + '_account.png';
            link.href = canvas.toDataURL();
            link.click();
            slip.style.display = 'none';
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
    if old_user: # Edit Mode
        db = [u for u in db if u['user'] != old_user]
    
    exp = (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")
    db.append({"user": user, "password": pw, "expires": exp, "port": 6000+len(db), "status": "active"})
    write_db(db); return redirect("/")

@app.route("/delete/<name>")
def delete(name):
    db = [u for u in read_db() if u['user'] != name]
    write_db(db); return redirect("/")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PY

pkill -f web.py
nohup python3 /etc/zivpn/web.py > /dev/null 2>&1 &
echo "Done! Refresh http://147.50.253.235:8080"
