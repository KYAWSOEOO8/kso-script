#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar)
# Author mix: Zahid Islam (udp-zivpn) + KSO tweaks + KSO polish
# Features: apt-guard, binary fetch fallback, UFW rules, DNAT+MASQ, sysctl forward,
#           Flask 1.x-compatible Web UI (auto-refresh 120s), users.json <-> config.json mirror sync,
#           per-user Online/Offline via conntrack, expires accepts "YYYY-MM-DD" OR days "30",
#           Web UI: Header logo + title + Messenger button, Delete button per user, clean styling,
#           Login UI (form-based session, logo included) with /etc/zivpn/web.env credentials.
#           +++ Added: ONE-TIME KEY GATE (consume from built-in API before installing)

set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; M="\e[1;35m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP Server + Web UI ကို  KSO မှ ရေးသားထားသည်${Z}\n$LINE"

# ===== Root check =====
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}ဤ script ကို root အဖြစ် chạy ရပါမယ် (sudo -i)${Z}"; exit 1
fi

export DEBIAN_FRONTEND=noninteractive

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
  echo -ે "${Y}⚠️ apt timers ကို ယာယီရပ်နေပါတယ်${Z}"
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

# stop old services to avoid text busy
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
  say "${Y}🔐 SSL စိတျဖိုင်တွေ ဖန်တီးနေပါတယ်...${Z}"
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
if [ -ဇ "${input_pw:-}" ]; then PW_LIST='["zi"]'; else
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

# ===== Web Panel (Flask 1.x compatible, refresh 120s + Login UI) =====
say "${Y}🖥️ Web Panel (Flask) ကို ထည့်နေပါတယ်...${Z}"
cat >/etc/zivpn/web.py <<'PY'
from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session, make_response
import json, re, subprocess, os, tempfile, hmac
from datetime import datetime, timedelta

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LISTEN_FALLBACK = "5667"
RECENT_SECONDS = 120

LOGO_URL = "https://raw.githubusercontent.com/KYAWSOEOO8/kso-script/main/icon.png"

HTML = """<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="120">
<style>
 :root{
  --bg:#ffffff; --fg:#111; --muted:#666; --card:#fafafa; --bd:#e5e5e5;
  --ok:#0a8a0a; --bad:#c0392b; --unk:#666; --btn:#fff; --btnbd:#ccc;
  --pill:#f5f5f5; --pill-bad:#ffecec; --pill-ok:#eaffe6; --pill-unk:#f0f0f0;
 }
 html,body{background:var(--bg);color:var(--fg); min-height: 100vh;}
 body{
   font-family:system-ui,Segoe UI,Roboto,Arial;
   margin:0; 
   display:flex; 
   flex-direction:column; 
   align-items:center; 
   padding:24px;
   box-sizing: border-box;
 }
 header{display:flex;flex-direction:column;align-items:center;gap:14px;margin-bottom:24px;text-align:center}
 h1{margin:0;font-size:1.8em;font-weight:600;line-height:1.2}
 .sub{color:var(--muted);font-size:.95em}
 .btn{
   padding:8px 14px;border-radius:999px;border:1px solid var(--btnbd);
   background:var(--btn);color:var(--fg);text-decoration:none;white-space:nowrap;cursor:pointer;
   display: inline-block;
 }
 table{border-collapse:collapse;width:100%;max-width:300px;margin: 0 auto}
 th,td{border:1px solid var(--bd);padding:10px;text-align:center} /* စာသားတွေကိုပါ အလယ်ပို့ထားပါတယ် */
 th{background:var(--card)}
 .ok{color:var(--ok);background:var(--pill-ok)}
 .bad{color:var(--bad);background:var(--pill-bad)}
 .unk{color:var(--unk);background:var(--pill-unk)}
 .pill{display:inline-block;padding:4px 10px;border-radius:999px}
 form.box{margin:18px auto;padding:24px;border:1px solid var(--bd);border-radius:12px;background:var(--card);max-width:480px;width:100%;text-align:left}
 label{display:block;margin:6px 0 2px}
 input{width:100%;padding:9px 12px;border:1px solid var(--bd);border-radius:10px;box-sizing:border-box}
 .row{display:flex;gap:18px;flex-wrap:wrap;justify-content:center}
 .row>div{flex:1 1 220px}
 .msg{margin:10px 0;color:var(--ok);text-align:center}
 .err{margin:10px 0;color:var(--bad);text-align:center}
 .muted{color:var(--muted)}
 .delform{display:inline}
 tr.expired td{opacity:.9; text-decoration-color: var(--bad);}
 .center{display:flex;align-items:center;justify-content:center;text-align:center}
 .login-card{max-width:420px;width:100%;margin:auto;padding:24px;border:1px solid var(--bd);border-radius:14px;background:var(--card)}
 .login-card h3{margin:10px 0 6px}
 .logo{height:64px;width:auto;border-radius:14px;box-shadow:0 2px 6px rgba(0,0,0,0.15)}
</style></head><body>

{% if not authed %}
  <div class="login-card">
    <div class="center"><img class="logo" src="{{ logo }}" alt="KSO-VIP"></div>
    <h3 class="center">KSO-VIP</h3>
    <p class="center muted" style="margin-top:0">ZIVPN User Panel — Login</p>
    {% if err %}<div class="err">{{err}}</div>{% endif %}
    <form method="post" action="/login">
      <label>Username</label>
      <input name="u" autofocus required>
      <label style="margin-top:8px">Password</label>
      <input name="p" type="password" required>
      <button class="btn" type="submit" style="margin-top:20px;width:100%; background:#111; color:#fff">Login</button>
    </form>
  </div>
{% else %}
<header>
  <div class="logo-container">
    <img src="{{ logo }}" alt="KSO-VIP" style="width: 80px; height: 80px; border-radius: 50%; box-shadow: 0 4px 8px rgba(0,0,0,0.1);">
  </div>
  <div>
    <h1>KSO VIP</h1>
  </div>
  <div style="width: 100%; max-width: 280px;">
    <a class="btn" href="https://m.me/kyawsoe.oo.1292019" target="_blank" rel="noopener" 
       style="display: block; background: #0084ff; color: white; border: none; padding: 12px; font-weight: bold; text-decoration: none; border-radius: 8px;">
      💬 Contact (Messenger)
    </a>
   <a class="btn" href="/logout">Logout</a>
  </div>
</header>

<div style="display: flex; justify-content: center; align-items: center; width: 100%; padding: 15px; background: #e0e5ec; min-height: 100vh; box-sizing: border-box; font-family: sans-serif;">
  <form method="post" action="/add" style="width: 100%; max-width: 300px; padding: 25px; border-radius: 30px; background: #e0e5ec; box-shadow: 15px 15px 30px #bec3c9, -15px -15px 30px #ffffff; border: none;">
    
    <h3 style="text-align: center; color: #444; font-weight: 300; margin-bottom: 25px; letter-spacing: 0.5px; font-size: 1.2em;">➕ ADD NEW USER</h3>

    {% if msg %}<div style="color: #0a8a0a; text-align: center; margin-bottom: 15px; font-weight: 300; font-size: 0.9em;">{{msg}}</div>{% endif %}
    {% if err %}<div style="color: #c0392b; text-align: center; margin-bottom: 15px; font-weight: 300; font-size: 0.9em;">{{err}}</div>{% endif %}

    <div style="display: flex; flex-direction: column; gap: 15px; margin-bottom: 25px;">
      
      <div>
        <label style="display: block; margin-left: 10px; margin-bottom: 5px; color: #666; font-weight: 300; font-size: 0.85em;">👤 Username</label>
        <input name="user" required style="width: 100%; padding: 10px 15px; border: none; border-radius: 12px; background: #e0e5ec; box-shadow: inset 4px 4px 8px #bec3c9, inset -4px -4px 8px #ffffff; outline: none; color: #444; box-sizing: border-box;">
      </div>

      <div>
        <label style="display: block; margin-left: 10px; margin-bottom: 5px; color: #666; font-weight: 300; font-size: 0.85em;">🔑 Password</label>
        <input name="password" required style="width: 100%; padding: 10px 15px; border: none; border-radius: 12px; background: #e0e5ec; box-shadow: inset 4px 4px 8px #bec3c9, inset -4px -4px 8px #ffffff; outline: none; color: #444; box-sizing: border-box;">
      </div>

      <div style="display: flex; gap: 15px;">
        <div style="flex: 1;">
          <label style="display: block; margin-left: 10px; margin-bottom: 5px; color: #666; font-weight: 300; font-size: 0.85em;">⏰ Expires</label>
          <input name="expires" placeholder="2025-12-31" style="width: 100%; padding: 10px 15px; border: none; border-radius: 12px; background: #e0e5ec; box-shadow: inset 4px 4px 8px #bec3c9, inset -4px -4px 8px #ffffff; outline: none; color: #444; box-sizing: border-box;">
        </div>
        <div style="flex: 1;">
          <label style="display: block; margin-left: 10px; margin-bottom: 5px; color: #666; font-weight: 300; font-size: 0.85em;">🔌 UDP Port</label>
          <input name="port" placeholder="auto" style="width: 100%; padding: 10px 15px; border: none; border-radius: 12px; background: #e0e5ec; box-shadow: inset 4px 4px 8px #bec3c9, inset -4px -4px 8px #ffffff; outline: none; color: #444; box-sizing: border-box;">
        </div>
      </div>

    </div>

    <div style="text-align: center;">
      <button type="submit" style="width: 90%; padding: 12px; border: none; border-radius: 15px; background: #e0e5ec; color: #0a8a0a; font-weight: 300; font-size: 1em; cursor: pointer; box-shadow: 5px 5px 10px #bec3c9, -5px -5px 10px #ffffff; transition: all 0.2s ease;">
        SAVE + SYNC
      </button>
    </div>

  </form>
</div>

<table>
  <tr>
    <th>👤 User</th><th>🔑 Password</th><th>⏰ Expires</th>
    <th>🔌 Port</th><th>🔎 Status</th><th>🗑️ Delete</th>
  </tr>
  {% for u in users %}
  <tr class="{% if u.expires and u.expires < today %}expired{% endif %}">
    <td class="usercell">{{u.user}}</td>
    <td>{{u.password}}</td>
    <td>{% if u.expires %}{{u.expires}}{% else %}<span class="muted">—</span>{% endif %}</td>
    <td>{% if u.port %}{{u.port}}{% else %}<span class="muted">—</span>{% endif %}</td>
    <td>
      {% if u.status == "Online" %}<span class="pill ok">Online</span>
      {% elif u.status == "Offline" %}<span class="pill bad">Offline</span>
      {% else %}<span class="pill unk">Unknown</span>
      {% endif %}
    </td>
    <td>
      <form class="delform" method="post" action="/delete" onsubmit="return confirm('ဖျက်မလား?')">
        <input type="hidden" name="user" value="{{u.user}}">
        <button type="submit" class="btn" style="border-color:transparent;background:#ffecec">Delete</button>
      </form>
    </td>
  </tr>
  {% endfor %}
</table>

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
  import re as _re
  m=_re.search(r":(\d+)$", listen) if listen else None
  return (m.group(1) if m else LISTEN_FALLBACK)

def get_udp_listen_ports():
  out=subprocess.run("ss -uHln", shell=True, capture_output=True, text=True).stdout
  import re as _re
  return set(_re.findall(r":(\d+)\s", out))

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
    # render login UI
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
  # GET
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
  try:
    if expires:
      datetime.strptime(expires,"%Y-%m-%d")
  except ValueError:
    return build_view(err="Expires format မမှန်ပါ (YYYY-MM-DD)")
  if port:
    import re as _re
    if not _re.fullmatch(r"\d{2,5}",port) or not (6000 <= int(port) <= 19999):
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
  import re as _re
  if port and (not _re.fullmatch(r"\d{2,5}",port) or not (6000<=int(port)<=19999)):
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
echo -e "\n$LINE\n${G}✅ Done${Z}"
echo -e "${C}Web Panel   :${Z} ${Y}http://$IP:8080${Z}"
echo -e "${C}users.json  :${Z} ${Y}/etc/zivpn/users.json${Z}"
echo -e "${C}config.json :${Z} ${Y}/etc/zivpn/config.json${Z}"
echo -e "${C}Services    :${Z} ${Y}systemctl status|restart zivpn  •  systemctl status|restart zivpn-web${Z}"
echo -ે "$LINE"  say "${Y}🔐 SSL စိတျဖိုင်တွေ ဖန်တီးနေပါတယ်...${Z}"
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

# ===== Web Panel (Flask 1.x compatible, refresh 120s + Login UI) =====
say "${Y}🖥️ Web Panel (Flask) ကို ထည့်နေပါတယ်...${Z}"
cat >/etc/zivpn/web.py <<'PY'
from flask import Flask, jsonify, render_template_string, request, redirect, url_for, session, make_response
import json, re, subprocess, os, tempfile, hmac
from datetime import datetime, timedelta

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LISTEN_FALLBACK = "5667"
RECENT_SECONDS = 120

LOGO_URL = "https://raw.githubusercontent.com/KYAWSOEOO8/kso-script/main/icon.png"


HTML = """<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="120">
<style>
 :root{
  --bg:#ffffff; --fg:#111; --muted:#666; --card:#fafafa; --bd:#e5e5e5;
  --ok:#0a8a0a; --bad:#c0392b; --unk:#666; --btn:#fff; --btnbd:#ccc;
  --pill:#f5f5f5; --pill-bad:#ffecec; --pill-ok:#eaffe6; --pill-unk:#f0f0f0;
 }
 html,body{background:var(--bg);color:var(--fg); min-height: 100vh;}
 body{
   font-family:system-ui,Segoe UI,Roboto,Arial;
   margin:0; 
   display:flex; 
   flex-direction:column; 
   align-items:center; 
   padding:24px;
   box-sizing: border-box;
 }
 header{display:flex;flex-direction:column;align-items:center;gap:14px;margin-bottom:24px;text-align:center}
 h1{margin:0;font-size:1.8em;font-weight:600;line-height:1.2}
 .sub{color:var(--muted);font-size:.95em}
 .btn{
   padding:8px 14px;border-radius:999px;border:1px solid var(--btnbd);
   background:var(--btn);color:var(--fg);text-decoration:none;white-space:nowrap;cursor:pointer;
   display: inline-block;
 }
 table{border-collapse:collapse;width:100%;max-width:980px;margin: 0 auto}
 th,td{border:1px solid var(--bd);padding:10px;text-align:center} /* စာသားတွေကိုပါ အလယ်ပို့ထားပါတယ် */
 th{background:var(--card)}
 .ok{color:var(--ok);background:var(--pill-ok)}
 .bad{color:var(--bad);background:var(--pill-bad)}
 .unk{color:var(--unk);background:var(--pill-unk)}
 .pill{display:inline-block;padding:4px 10px;border-radius:999px}
 form.box{margin:18px auto;padding:24px;border:1px solid var(--bd);border-radius:12px;background:var(--card);max-width:480px;width:100%;text-align:left}
 label{display:block;margin:6px 0 2px}
 input{width:100%;padding:9px 12px;border:1px solid var(--bd);border-radius:10px;box-sizing:border-box}
 .row{display:flex;gap:18px;flex-wrap:wrap;justify-content:center}
 .row>div{flex:1 1 220px}
 .msg{margin:10px 0;color:var(--ok);text-align:center}
 .err{margin:10px 0;color:var(--bad);text-align:center}
 .muted{color:var(--muted)}
 .delform{display:inline}
 tr.expired td{opacity:.9; text-decoration-color: var(--bad);}
 .center{display:flex;align-items:center;justify-content:center;text-align:center}
 .login-card{max-width:420px;width:100%;margin:auto;padding:24px;border:1px solid var(--bd);border-radius:14px;background:var(--card)}
 .login-card h3{margin:10px 0 6px}
 .logo{height:64px;width:auto;border-radius:14px;box-shadow:0 2px 6px rgba(0,0,0,0.15)}
</style></head><body>

{% if not authed %}
  <div class="login-card">
    <div class="center"><img class="logo" src="{{ logo }}" alt="KSO-VIP"></div>
    <h3 class="center">KSO-VIP</h3>
    {% if err %}<div class="err">{{err}}</div>{% endif %}
    <form method="post" action="/login">
      <label>Username</label>
      <input name="u" autofocus required>
      <label style="margin-top:8px">Password</label>
      <input name="p" type="password" required>
      <button class="btn" type="submit" style="margin-top:20px;width:100%; background:#111; color:#fff">Login</button>
    </form>
  </div>
{% else %}
<header>
  <div class="logo-container">
    <img src="{{ logo }}" alt="KSO-VIP" style="width: 80px; height: 80px; border-radius: 50%; box-shadow: 0 4px 8px rgba(0,0,0,0.1);">
  </div>
  <div>
    <h1>KSO VIP</h1>
  </div>
  <div style="width: 100%; max-width: 90px;">
    <a class="btn" href="https://m.me/kyawsoe.oo.1292019" target="_blank" rel="noopener" 
       style="display: block; background: #0084ff; color: white; border: none; padding: 12px; font-weight: bold; text-decoration: none; border-radius: 8px;">
      💬 Contact (Messenger)
    </a>
    <a class="btn" href="/logout">Logout</a>
  </div>
</header>

<div style="display: flex; justify-content: center; align-items: center; width: 90%; padding: 5px; background: #e0e5ec; min-height: 100vh; box-sizing: border-box; font-family: sans-serif;">
  <form method="post" action="/add" style="width: 100%; max-width: 90px; padding: 15px; border-radius: 20px; background: #e0e5ec; box-shadow: 8px 8px 16px #bec3c9, -8px -8px 16px #ffffff; border: none;">
    
    <h3 style="text-align: center; color: #444; font-weight: 400; margin-bottom: 15px; font-size: 1em; letter-spacing: 0px;">➕ ADD USER</h3>

    <div style="display: flex; flex-direction: column; gap: 10px; margin-bottom: 15px;">
      
      <div>
        <label style="display: block; margin-left: 5px; margin-bottom: 2px; color: #666; font-weight: 400; font-size: 0.75em;">👤 Username</label>
        <input name="user" required style="width: 90%; padding: 6px 10px; border: none; border-radius: 8px; background: #e0e5ec; box-shadow: inset 2px 2px 5px #bec3c9, inset -2px -2px 5px #ffffff; outline: none; color: #444; font-size: 0.8em; box-sizing: border-box;">
      </div>

      <div>
        <label style="display: block; margin-left: 5px; margin-bottom: 2px; color: #666; font-weight: 400; font-size: 0.75em;">🔑 Password</label>
        <input name="password" required style="width: 90%; padding: 6px 10px; border: none; border-radius: 8px; background: #e0e5ec; box-shadow: inset 2px 2px 5px #bec3c9, inset -2px -2px 5px #ffffff; outline: none; color: #444; font-size: 0.8em; box-sizing: border-box;">
      </div>

      <div style="display: flex; gap: 8px;">
        <div style="flex: 1.3;">
          <label style="display: block; margin-left: 5px; margin-bottom: 2px; color: #666; font-weight: 400; font-size: 0.75em;">⏰ Expires</label>
          <input name="expires" placeholder="2026..." style="width: 90%; padding: 6px 10px; border: none; border-radius: 8px; background: #e0e5ec; box-shadow: inset 2px 2px 5px #bec3c9, inset -2px -2px 5px #ffffff; outline: none; color: #444; font-size: 0.75em; box-sizing: border-box;">
        </div>
        <div style="flex: 0.7;">
          <label style="display: block; margin-left: 5px; margin-bottom: 2px; color: #666; font-weight: 400; font-size: 0.75em;">🔌 Port</label>
          <input name="port" placeholder="auto" style="width: 90%; padding: 6px 10px; border: none; border-radius: 8px; background: #e0e5ec; box-shadow: inset 2px 2px 5px #bec3c9, inset -2px -2px 5px #ffffff; outline: none; color: #444; font-size: 0.75em; box-sizing: border-box;">
        </div>
      </div>

    </div>

    <div style="text-align: center;">
      <button type="submit" style="width: 90%; padding: 8px; border: none; border-radius: 12px; background: #e0e5ec; color: #0a8a0a; font-weight: 400; font-size: 0.85em; cursor: pointer; box-shadow: 3px 3px 6px #bec3c9, -3px -3px 6px #ffffff;">
        SAVE + SYNC
      </button>
    </div>

  </form>
</div>
    <tr>
      <th>အသုံးပြုသူ</th>
      <th>သက်တမ်း/Port</th>
      <th>အခြေအနေ</th>
      <th style="text-align:right;">စီမံရန်</th>
    </tr>
  </thead>
  <tbody>
    {% for u in users %}
    <tr class="user-row {% if u.expires and u.expires < today %}expired{% endif %}">
      <td>
        <div style="font-weight:600; color:#1e293b; font-size:15px;">{{u.user}}</div>
        <div style="font-size:12px; color:#94a3b8;">🔑 {{u.password}}</div>
      </td>
      <td>
        <div style="color:#475569; font-weight:500;">{{u.expires if u.expires else '—'}}</div>
        <div style="font-size:11px; color:#94a3b8;">Port: <span style="color:#6366f1;">{{u.port if u.port else 'auto'}}</span></div>
      </td>
      <td>
        {% if u.status == "Online" %}
          <span class="pill ok">● Online</span>
        {% elif u.status == "Offline" %}
          <span class="pill bad">○ Offline</span>
        {% else %}
          <span class="pill unk">? Unknown</span>
        {% endif %}
      </td>
      <td>
        <div style="display:flex; gap:8px; justify-content:flex-end;">
          <form method="post" action="/delete" onsubmit="return confirm('ဖျက်မှာ သေချာပါသလား?')" style="margin:0;">
            <input type="hidden" name="user" value="{{u.user}}">
            <button type="submit" class="btn-del">🗑️</button>
          </form>
        </div>
      </td>
    </tr>
    {% endfor %}
  </tbody>
</table>



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
    # render login UI
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
  # GET
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
echo -e "\n$LINE\n${G}✅ Done${Z}"
echo -e "${C}Web Panel   :${Z} ${Y}http://$IP:8080${Z}"
echo -e "${C}users.json  :${Z} ${Y}/etc/zivpn/users.json${Z}"
echo -e "${C}config.json :${Z} ${Y}/etc/zivpn/config.json${Z}"
echo -e "${C}Services    :${Z} ${Y}systemctl status|restart zivpn  •  systemctl status|restart zivpn-web${Z}"
echo -e "$LINE"
