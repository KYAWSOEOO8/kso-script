#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - Modern UI Version
# Author mix: Zahid Islam (udp-zivpn) + KSO tweaks + UI Refreshed by Gemini

set -euo pipefail

# ===== Pretty Colors =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; M="\e[1;35m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP Server + Web UI (Modern Look) Installation${Z}\n$LINE"

# ===== Root check =====
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}ဤ script ကို root အဖြစ် run ရပါမယ် (sudo -i)${Z}"; exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# =====================================================================
#                   ONE-TIME KEY GATE (MANDATORY)
# =====================================================================
KEY_API_URL="http://103.114.203.183:8088"

consume_one_time_key() {
  local _key="$1"
  local _url="${KEY_API_URL%/}/api/consume"
  if ! command -v curl >/dev/null 2>&1; then
    echo -e "${R}❌ curl မရှိပါ — apt-get install -y curl နဲ့အရင်တင်ပါ${Z}"
    exit 2
  fi
  echo -e "${Y}🔑 One-time key ကိုစစ်နေပါတယ်...${Z}"
  local resp
  resp=$(curl -fsS -X POST "$_url" \
           -H 'Content-Type: application/json' \
           -d "{\"key\":\"${_key}\"}" 2>&1) || {
    echo -e "${R}❌ Key server ချိတ်ဆက်မရ:${Z} $resp"
    exit 2
  }
  if echo "$resp" | grep -q '"ok":\s*true'; then
    echo -e "${G}✅ Key မှန်တယ် (consumed) — Installation ဆက်လုပ်မယ်${Z}"
    return 0
  else
    echo -e "${R}❌ Key မမှန်/ပြီးသုံးပြီး:${Z} $resp"
    return 1
  fi
}

# ===== Prompt for one-time key =====
while :; do
  echo -ne "${C}Enter one-time key: ${Z}"
  read -r -s ONE_TIME_KEY
  echo
  if [ -z "${ONE_TIME_KEY:-}" ]; then
    echo -e "${Y}⚠️ key မထည့်ရသေးပါ — ထပ်ထည့်ပါ${Z}"
    continue
  fi
  if consume_one_time_key "$ONE_TIME_KEY"; then
    break
  else
    echo -e "${Y}🔁 ထပ်ထည့်ပါ (UI မှ key အသစ်ထုတ်လို့ရတယ်)${Z}"
  fi
done

# =====================================================================
#                   INSTALLATION START
# =====================================================================

# ===== apt guards =====
wait_for_apt() {
  echo -e "${Y}⏳ apt ပိတ်မချင်း စောင့်နေပါတယ်...${Z}"
  for _ in $(seq 1 60); do
    if pgrep -x apt-get >/dev/null || pgrep -x apt >/dev/null || pgrep -f 'apt.systemd.daily' >/dev/null || pgrep -x unattended-upgrade >/dev/null; then
      sleep 5
    else
      return 0
    fi
  done
  echo -e "${Y}⚠️ apt timers ကို ယာယီရပ်နေပါတယ်${Z}"
  systemctl stop --now unattended-upgrades.service 2>/dev/null || true
  systemctl stop --now apt-daily.service apt-daily.timer 2>/dev/null || true
  systemctl stop --now apt-daily-upgrade.service apt-daily-upgrade.timer 2>/dev/null || true
}
apt_guard_start(){
  wait_for_apt
  CNF_CONF="/etc/apt/apt.conf.d/50command-not-found"
  if [ -f "$CNF_CONF" ]; then mv "$CNF_CONF" "${CNF_CONF}.disabled"; CNF_DISABLED=1; else CNF_DISABLED=0; fi
}
apt_guard_end(){
  dpkg --configure -a >/dev/null 2>&1 || true
  apt-get -f install -y >/dev/null 2>&1 || true
  if [ "${CNF_DISABLED:-0}" = "1" ] && [ -f "${CNF_CONF}.disabled" ]; then mv "${CNF_CONF}.disabled" "$CNF_CONF"; fi
}

# ===== Packages =====
say "${Y}📦 Packages တင်နေပါတယ်...${Z}"
apt_guard_start
apt-get update -y -o APT::Update::Post-Invoke-Success::= -o APT::Update::Post-Invoke::= >/dev/null
apt-get install -y curl ufw jq python3 python3-flask python3-apt iproute2 conntrack ca-certificates >/dev/null || {
  apt-get install -y -o DPkg::Lock::Timeout=60 python3-apt >/dev/null || true
  apt-get install -y curl ufw jq python3 python3-flask iproute2 conntrack ca-certificates >/dev/null
}
apt_guard_end

# stop old services
systemctl stop zivpn.service 2>/dev/null || true
systemctl stop zivpn-web.service 2>/dev/null || true

# ===== Paths =====
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"
mkdir -p /etc/zivpn

# ===== Download ZIVPN binary =====
say "${Y}⬇️ ZIVPN binary ကို ဒေါင်းနေပါတယ်...${Z}"
PRIMARY_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
FALLBACK_URL="https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
TMP_BIN="$(mktemp)"
if ! curl -fsSL -o "$TMP_BIN" "$PRIMARY_URL"; then
  echo -e "${Y}Primary URL မရ — latest ကို စမ်းပါတယ်...${Z}"
  curl -fSL -o "$TMP_BIN" "$FALLBACK_URL"
fi
install -m 0755 "$TMP_BIN" "$BIN"
rm -f "$TMP_BIN"

# ===== Base config =====
if [ ! -f "$CFG" ]; then
  say "${Y}🧩 config.json ဖန်တီးနေပါတယ်...${Z}"
  curl -fsSL -o "$CFG" "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json" || echo '{}' > "$CFG"
fi

# ===== Certs =====
if [ ! -f /etc/zivpn/zivpn.crt ] || [ ! -f /etc/zivpn/zivpn.key ]; then
  say "${Y}🔐 SSL keys ဖန်တီးနေပါတယ်...${Z}"
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=UPK/OU=Net/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# ===== Web Admin (Login UI credentials) =====
say "${Y}🔒 Web Admin Login UI ထည့်မလား? (လစ်: မဖိတ်)${Z}"
read -r -p "Web Admin Username (Enter=disable): " WEB_USER
if [ -n "${WEB_USER:-}" ]; then
  read -r -s -p "Web Admin Password: " WEB_PASS; echo
  # strong secret for Flask session
  if command -v openssl >/dev/null 2>&1; then
    WEB_SECRET="$(openssl rand -hex 32)"
  else
    WEB_SECRET="$(python3 - <<'PY'\nimport secrets;print(secrets.token_hex(32))\nPY\n)"
  fi
  {
    echo "WEB_ADMIN_USER=${WEB_USER}"
    echo "WEB_ADMIN_PASSWORD=${WEB_PASS}"
    echo "WEB_SECRET=${WEB_SECRET}"
  } > "$ENVF"
  chmod 600 "$ENVF"
  say "${G}✅ Web login UI ဖွင့်ထားပါတယ်${Z}"
else
  rm -f "$ENVF" 2>/dev/null || true
  say "${Y}ℹ️ Web login UI မဖွင့်ထားပါ (dev mode)${Z}"
fi

# ===== Ask initial VPN passwords =====
say "${G}🔏 VPN Password List (ကော်မာဖြင့်ခွဲ) eg: upkvip,alice,pass1${Z}"
read -r -p "Passwords (Enter=zi): " input_pw
if [ -z "${input_pw:-}" ]; then PW_LIST='["zi"]'; else
  PW_LIST=$(echo "$input_pw" | awk -F',' '{
    printf("["); for(i=1;i<=NF;i++){gsub(/^ *| *$/,"",$i); printf("%s\"%s\"", (i>1?",":""), $i)}; printf("]")
  }')
fi

# ===== Update config.json =====
if jq . >/dev/null 2>&1 <<<'{}'; then
  TMP=$(mktemp)
  jq --argjson pw "$PW_LIST" '
    .auth.mode = "passwords" |
    .auth.config = $pw |
    .listen = (."listen" // ":5667") |
    .cert = "/etc/zivpn/zivpn.crt" |
    .key  = "/etc/zivpn/zivpn.key" |
    .obfs = (."obfs" // "zivpn")
  ' "$CFG" > "$TMP" && mv "$TMP" "$CFG"
fi
[ -f "$USERS" ] || echo "[]" > "$USERS"
chmod 644 "$CFG" "$USERS"

# ===== systemd: ZIVPN =====
say "${Y}🧰 systemd service (zivpn) ကို သွင်းနေပါတယ်...${Z}"
cat >/etc/systemd/system/zivpn.service <<'EOF'
[Unit]
Description=ZIVPN UDP Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# ===== Web Panel (Improved Modern UI) =====
say "${Y}🖥️ Web Panel (Flask - Modern UI) ကို ထည့်နေပါတယ်...${Z}"
cat >/etc/zivpn/web.py <<'PY'
from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session, make_response
import json, re, subprocess, os, tempfile, hmac
from datetime import datetime, timedelta

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LISTEN_FALLBACK = "5667"
RECENT_SECONDS = 120

LOGO_URL = "https://raw.githubusercontent.com/Upk123/upkvip-ziscript/refs/heads/main/20251018_231111.png"

# === MODERN UI HTML ===
HTML = """<!doctype html>
<html lang="my">
<head>
<meta charset="utf-8">
<title>ZIVPN User Panel</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="120">
<link rel="preconnect" href="https://fonts.googleapis.com">
<style>
 :root {
  --primary: #2563eb; --primary-hover: #1d4ed8;
  --bg: #f0f4f8; --card-bg: #ffffff; --text: #1e293b; --muted: #64748b;
  --border: #e2e8f0; --shadow: 0 4px 6px -1px rgba(0,0,0,0.1), 0 2px 4px -1px rgba(0,0,0,0.06);
  --success: #10b981; --danger: #ef4444; --warning: #f59e0b;
 }
 * { box-sizing: border-box; }
 body {
  background-color: var(--bg); color: var(--text);
  font-family: 'Segoe UI', system-ui, sans-serif;
  margin: 0; padding: 20px;
  line-height: 1.5;
 }
 .container { max-width: 1000px; margin: 0 auto; }
 
 /* Header */
 header {
  display: flex; align-items: center; justify-content: space-between;
  margin-bottom: 24px; padding-bottom: 20px; border-bottom: 2px solid #e2e8f0;
 }
 .brand { display: flex; align-items: center; gap: 16px; }
 .brand img { height: 60px; width: auto; border-radius: 12px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
 .brand h1 { margin: 0; font-size: 1.5rem; color: #0f172a; }
 .brand span { color: var(--muted); font-size: 0.9rem; }
 .actions { display: flex; gap: 10px; }
 
 /* Buttons */
 .btn {
  display: inline-flex; align-items: center; justify-content: center;
  padding: 8px 16px; border-radius: 8px; font-weight: 500; text-decoration: none;
  border: 1px solid transparent; cursor: pointer; transition: all 0.2s; font-size: 0.9rem;
 }
 .btn-primary { background: var(--primary); color: white; }
 .btn-primary:hover { background: var(--primary-hover); }
 .btn-outline { background: white; border-color: var(--border); color: var(--text); }
 .btn-outline:hover { background: #f8fafc; border-color: #cbd5e1; }
 .btn-danger-soft { background: #fef2f2; color: var(--danger); }
 .btn-danger-soft:hover { background: #fee2e2; }

 /* Cards */
 .card {
  background: var(--card-bg); border-radius: 16px; box-shadow: var(--shadow);
  padding: 24px; margin-bottom: 24px; border: 1px solid var(--border);
 }
 .card h3 { margin-top: 0; margin-bottom: 16px; font-size: 1.1rem; color: #334155; }

 /* Form */
 .form-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; margin-bottom: 16px; }
 label { display: block; font-size: 0.85rem; font-weight: 600; color: var(--muted); margin-bottom: 6px; }
 input {
  width: 100%; padding: 10px 12px; border: 2px solid var(--border); border-radius: 8px;
  font-size: 0.95rem; transition: border-color 0.2s;
 }
 input:focus { outline: none; border-color: var(--primary); }

 /* Table */
 .table-responsive { overflow-x: auto; border-radius: 12px; border: 1px solid var(--border); }
 table { width: 100%; border-collapse: collapse; background: white; }
 th, td { padding: 14px 16px; text-align: left; border-bottom: 1px solid #f1f5f9; }
 th { background: #f8fafc; font-weight: 600; color: var(--muted); font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.5px; }
 tr:last-child td { border-bottom: none; }
 tr:hover td { background: #f8fafc; }
 
 /* Status Pills */
 .pill { padding: 4px 10px; border-radius: 20px; font-size: 0.75rem; font-weight: 600; display: inline-block; }
 .pill.online { background: #d1fae5; color: #065f46; }
 .pill.offline { background: #fee2e2; color: #991b1b; }
 .pill.unknown { background: #f1f5f9; color: #64748b; }
 
 /* Utilities */
 .msg { background: #dcfce7; color: #166534; padding: 12px; border-radius: 8px; margin-bottom: 16px; border: 1px solid #bbf7d0; }
 .err { background: #fee2e2; color: #991b1b; padding: 12px; border-radius: 8px; margin-bottom: 16px; border: 1px solid #fecaca; }
 .expired td { opacity: 0.5; }
 .login-wrapper { display: flex; align-items: center; justify-content: center; min-height: 80vh; }
 .login-card { width: 100%; max-width: 400px; padding: 32px; text-align: center; }
 .login-card img { margin-bottom: 16px; }
</style>
</head>
<body>

{% if not authed %}
  <div class="login-wrapper">
    <div class="card login-card">
      <img src="{{ logo }}" alt="Logo" style="height:64px;width:auto;border-radius:12px">
      <h3>Admin Login</h3>
      {% if err %}<div class="err">{{err}}</div>{% endif %}
      <form method="post" action="/login">
        <div style="text-align:left; margin-bottom:12px">
            <label>Username</label>
            <input name="u" autofocus required>
        </div>
        <div style="text-align:left; margin-bottom:20px">
            <label>Password</label>
            <input name="p" type="password" required>
        </div>
        <button class="btn btn-primary" type="submit" style="width:100%">Login</button>
      </form>
    </div>
  </div>
{% else %}

<div class="container">
  <header>
    <div class="brand">
      <img src="{{ logo }}" alt="Logo">
      <div>
        <h1>DEV-U PHOE KAUNT</h1>
        <span>ZIVPN User Manager</span>
      </div>
    </div>
    <div class="actions">
      <a class="btn btn-outline" href="https://m.me/upkvpnfastvpn" target="_blank">💬 Messenger</a>
      <a class="btn btn-danger-soft" href="/logout">Logout</a>
    </div>
  </header>

  <div class="card">
    <h3>➕ Add New User</h3>
    {% if msg %}<div class="msg">{{msg}}</div>{% endif %}
    {% if err %}<div class="err">{{err}}</div>{% endif %}
    <form method="post" action="/add">
      <div class="form-grid">
        <div><label>👤 User Name</label><input name="user" required placeholder="eg. user1"></div>
        <div><label>🔑 Password</label><input name="password" required placeholder="secret"></div>
        <div><label>⏰ Expires (Days or Date)</label><input name="expires" placeholder="30 or 2025-12-31"></div>
        <div><label>🔌 UDP Port</label><input name="port" placeholder="Auto (6000+)"></div>
      </div>
      <button class="btn btn-primary" type="submit">Create User & Sync</button>
    </form>
  </div>

  <div class="card" style="padding:0; overflow:hidden">
    <div class="table-responsive">
      <table>
        <thead>
          <tr>
            <th>User</th>
            <th>Password</th>
            <th>Expires</th>
            <th>Port</th>
            <th>Status</th>
            <th style="text-align:right">Action</th>
          </tr>
        </thead>
        <tbody>
          {% for u in users %}
          <tr class="{% if u.expires and u.expires < today %}expired{% endif %}">
            <td style="font-weight:500">{{u.user}}</td>
            <td style="font-family:monospace">{{u.password}}</td>
            <td>{% if u.expires %}{{u.expires}}{% else %}<span style="color:#cbd5e1">—</span>{% endif %}</td>
            <td>{% if u.port %}{{u.port}}{% else %}<span style="color:#cbd5e1">auto</span>{% endif %}</td>
            <td>
              {% if u.status == "Online" %}<span class="pill online">Online</span>
              {% elif u.status == "Offline" %}<span class="pill offline">Offline</span>
              {% else %}<span class="pill unknown">Unknown</span>
              {% endif %}
            </td>
            <td style="text-align:right">
              <form method="post" action="/delete" onsubmit="return confirm('ဖျက်မှာသေချာလား?')" style="display:inline">
                <input type="hidden" name="user" value="{{u.user}}">
                <button type="submit" class="btn btn-danger-soft" style="padding:4px 10px; font-size:0.8rem">Delete</button>
              </form>
            </td>
          </tr>
          {% endfor %}
        </tbody>
      </table>
    </div>
  </div>
</div>

{% endif %}
</body></html>"""

app = Flask(__name__)

# Secret & Admin credentials (via env)
app.secret_key = os.environ.get("WEB_SECRET","dev-secret-change-me")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER","").strip()
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD","").strip()

def read_json(path, default):
  try:
    with open(path,"r") as f: return json.load(f)
  except Exception:
    return default

def write_json_atomic(path, data):
  d=json.dumps(data, ensure_ascii=False, indent=2)
  dirn=os.path.dirname(path); fd,tmp=tempfile.mkstemp(prefix=".tmp-", dir=dirn)
  try:
    with os.fdopen(fd,"w") as f: f.write(d)
    os.replace(tmp,path)
  finally:
    try: os.remove(tmp)
    except: pass

def load_users():
  v=read_json(USERS_FILE,[])
  out=[]
  for u in v:
    out.append({"user":u.get("user",""),
                "password":u.get("password",""),
                "expires":u.get("expires",""),
                "port":str(u.get("port","")) if u.get("port","")!="" else ""})
  return out

def save_users(users): write_json_atomic(USERS_FILE, users)

def get_listen_port_from_config():
  cfg=read_json(CONFIG_FILE,{})
  listen=str(cfg.get("listen","")).strip()
  m=re.search(r":(\d+)$", listen) if listen else None
  return (m.group(1) if m else LISTEN_FALLBACK)

def get_udp_listen_ports():
  out=subprocess.run("ss -uHln", shell=True, capture_output=True, text=True).stdout
  return set(re.findall(r":(\d+)\s", out))

def pick_free_port():
  used={str(u.get("port","")) for u in load_users() if str(u.get("port",""))}
  used |= get_udp_listen_ports()
  for p in range(6000,20000):
    if str(p) not in used: return str(p)
  return ""

def has_recent_udp_activity(port):
  if not port: return False
  try:
    out=subprocess.run("conntrack -L -p udp 2>/dev/null | grep 'dport=%s\\b'"%port,
                       shell=True, capture_output=True, text=True).stdout
    return bool(out)
  except Exception:
    return False

def status_for_user(u, active_ports, listen_port):
  port=str(u.get("port",""))
  check_port=port if port else listen_port
  if has_recent_udp_activity(check_port): return "Online"
  if check_port in active_ports: return "Offline"
  return "Unknown"

# --- mirror sync: config.json(auth.config) = users.json passwords only
def sync_config_passwords(mode="mirror"):
  cfg=read_json(CONFIG_FILE,{})
  users=load_users()
  users_pw=sorted({str(u["password"]) for u in users if u.get("password")})
  if mode=="merge":
    old=[]
    if isinstance(cfg.get("auth",{}).get("config",None), list):
      old=list(map(str, cfg["auth"]["config"]))
    new_pw=sorted(set(old)|set(users_pw))
  else:
    new_pw=users_pw
  if not isinstance(cfg.get("auth"),dict): cfg["auth"]={}
  cfg["auth"]["mode"]="passwords"
  cfg["auth"]["config"]=new_pw
  cfg["listen"]=cfg.get("listen") or ":5667"
  cfg["cert"]=cfg.get("cert") or "/etc/zivpn/zivpn.crt"
  cfg["key"]=cfg.get("key") or "/etc/zivpn/zivpn.key"
  cfg["obfs"]=cfg.get("obfs") or "zivpn"
  write_json_atomic(CONFIG_FILE,cfg)
  subprocess.run("systemctl restart zivpn.service", shell=True)

# --- Login guard helpers
def login_enabled(): return bool(ADMIN_USER and ADMIN_PASS)
def is_authed(): return session.get("auth") == True
def require_login():
  if login_enabled() and not is_authed():
    return False
  return True

def build_view(msg="", err=""):
  if not require_login():
    return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None))
  users=load_users()
  active=get_udp_listen_ports()
  listen_port=get_listen_port_from_config()
  view=[]
  for u in users:
    view.append(type("U",(),{
      "user":u.get("user",""),
      "password":u.get("password",""),
      "expires":u.get("expires",""),
      "port":u.get("port",""),
      "status":status_for_user(u,active,listen_port)
    }))
  view.sort(key=lambda x:(x.user or "").lower())
  today=datetime.now().strftime("%Y-%m-%d")
  return render_template_string(HTML, authed=True, logo=LOGO_URL, users=view, msg=msg, err=err, today=today)

@app.route("/login", methods=["GET","POST"])
def login():
  if not login_enabled():
    return redirect(url_for('index'))
  if request.method=="POST":
    u=(request.form.get("u") or "").strip()
    p=(request.form.get("p") or "").strip()
    if hmac.compare_digest(u, ADMIN_USER) and hmac.compare_digest(p, ADMIN_PASS):
      session["auth"]=True
      return redirect(url_for('index'))
    else:
      session["auth"]=False
      session["login_err"]="မှန်ကန်မှုမရှိပါ (username/password)"
      return redirect(url_for('login'))
  return render_template_string(HTML, authed=False, logo=LOGO_URL, err=session.pop("login_err", None))

@app.route("/logout", methods=["GET"])
def logout():
  session.pop("auth", None)
  return redirect(url_for('login') if login_enabled() else url_for('index'))

@app.route("/", methods=["GET"])
def index(): return build_view()

@app.route("/add", methods=["POST"])
def add_user():
  if not require_login(): return redirect(url_for('login'))
  user=(request.form.get("user") or "").strip()
  password=(request.form.get("password") or "").strip()
  expires=(request.form.get("expires") or "").strip()
  port=(request.form.get("port") or "").strip()

  if expires.isdigit():
    expires=(datetime.now() + timedelta(days=int(expires))).strftime("%Y-%m-%d")

  if not user or not password:
    return build_view(err="User နှင့် Password လိုအပ်သည်")
  if expires:
    try: datetime.strptime(expires,"%Y-%m-%d")
    except ValueError:
      return build_view(err="Expires format မမှန်ပါ (YYYY-MM-DD)")
  if port:
    if not re.fullmatch(r"\d{2,5}",port) or not (6000 <= int(port) <= 19999):
      return build_view(err="Port အကွာအဝေး 6000-19999")
  else:
    port=pick_free_port()

  users=load_users(); replaced=False
  for u in users:
    if u.get("user","").lower()==user.lower():
      u["password"]=password; u["expires"]=expires; u["port"]=port; replaced=True; break
  if not replaced:
    users.append({"user":user,"password":password,"expires":expires,"port":port})
  save_users(users); sync_config_passwords()
  return build_view(msg="Saved & Synced")

@app.route("/delete", methods=["POST"])
def delete_user_html():
  if not require_login(): return redirect(url_for('login'))
  user = (request.form.get("user") or "").strip()
  if not user:
    return build_view(err="User လိုအပ်သည်")
  remain = [u for u in load_users() if (u.get("user","").lower() != user.lower())]
  save_users(remain)
  sync_config_passwords(mode="mirror")
  return build_view(msg=f"Deleted: {user}")

@app.route("/api/user.delete", methods=["POST"])
def delete_user_api():
  if not require_login():
    return make_response(jsonify({"ok": False, "err":"login required"}), 401)
  data = request.get_json(silent=True) or {}
  user = (data.get("user") or "").strip()
  if not user:
    return jsonify({"ok": False, "err": "user required"}), 400
  remain = [u for u in load_users() if (u.get("user","").lower() != user.lower())]
  save_users(remain)
  sync_config_passwords(mode="mirror")
  return jsonify({"ok": True})

@app.route("/api/users", methods=["GET","POST"])
def api_users():
  if not require_login():
    return make_response(jsonify({"ok": False, "err":"login required"}), 401)
  if request.method=="GET":
    users=load_users(); active=get_udp_listen_ports(); listen_port=get_listen_port_from_config()
    for u in users: u["status"]=status_for_user(u,active,listen_port)
    return jsonify(users)
  data=request.get_json(silent=True) or {}
  user=(data.get("user") or "").strip()
  password=(data.get("password") or "").strip()
  expires=(data.get("expires") or "").strip()
  port=str(data.get("port") or "").strip()
  if expires.isdigit():
    expires=(datetime.now()+timedelta(days=int(expires))).strftime("%Y-%m-%d")
  if not user or not password: return jsonify({"ok":False,"err":"user/password required"}),400
  if port and (not re.fullmatch(r"\d{2,5}",port) or not (6000<=int(port)<=19999)):
    return jsonify({"ok":False,"err":"invalid port"}),400
  if not port: port=pick_free_port()
  users=load_users(); replaced=False
  for u in users:
    if u.get("user","").lower()==user.lower():
      u["password"]=password; u["expires"]=expires; u["port"]=port; replaced=True; break
  if not replaced:
    users.append({"user":user,"password":password,"expires":expires,"port":port})
  save_users(users); sync_config_passwords()
  return jsonify({"ok":True})

@app.route("/favicon.ico", methods=["GET"])
def favicon(): return ("",204)

@app.errorhandler(405)
def handle_405(e): return redirect(url_for('index'))

if __name__ == "__main__":
  app.run(host="0.0.0.0", port=8080)
PY

# ===== Web systemd =====
cat >/etc/systemd/system/zivpn-web.service <<'EOF'
[Unit]
Description=ZIVPN Web Panel
After=network.target

[Service]
Type=simple
User=root
# Load optional web login credentials
EnvironmentFile=-/etc/zivpn/web.env
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# ===== Networking: forwarding + DNAT + MASQ + UFW =====
echo -e "${Y}🌐 UDP/DNAT + UFW + sysctl အပြည့်ချထားနေပါတယ်...${Z}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
[ -n "${IFACE:-}" ] || IFACE=eth0
# DNAT 6000:19999/udp -> :5667
iptables -t nat -C PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || \
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
# MASQ out
iptables -t nat -C POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE

ufw allow 5667/udp >/dev/null 2>&1 || true
ufw allow 6000:19999/udp >/dev/null 2>&1 || true
ufw allow 8080/tcp >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true

# ===== CRLF sanitize =====
sed -i 's/\r$//' /etc/zivpn/web.py /etc/systemd/system/zivpn.service /etc/systemd/system/zivpn-web.service || true

# ===== Enable services =====
systemctl daemon-reload
systemctl enable --now zivpn.service
systemctl enable --now zivpn-web.service

IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ Done! UI Updated to Modern Style.${Z}"
echo -e "${C}Web Panel   :${Z} ${Y}http://$IP:8080${Z}"
echo -e "${C}users.json  :${Z} ${Y}/etc/zivpn/users.json${Z}"
echo -e "${C}Services    :${Z} ${Y}systemctl restart zivpn-web${Z}"
echo -e "$LINE"
