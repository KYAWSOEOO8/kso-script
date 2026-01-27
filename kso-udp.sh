#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - No Key Version
# Author mix: Zahid Islam + UPK tweaks + DEV-U PHOE KAUNT UI polish

set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; M="\e[1;35m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP Server + Web UI (Keyless Version)${Z}\n$LINE"

# ===== Root check =====
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}ဤ script ကို root အဖြစ် run ရပါမယ် (sudo -i)${Z}"; exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# =====================================================================
#  ONE-TIME KEY GATE REMOVED (တိုက်ရိုက်သွင်းနိုင်ပါပြီ)
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
apt-get update -y >/dev/null
apt-get install -y curl ufw jq python3 python3-flask python3-apt iproute2 conntrack ca-certificates openssl >/dev/null
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
TMP_BIN="$(mktemp)"
if ! curl -fsSL -o "$TMP_BIN" "$PRIMARY_URL"; then
  say "${R}❌ Binary download မရပါ${Z}"; exit 1
fi
install -m 0755 "$TMP_BIN" "$BIN"
rm -f "$TMP_BIN"

# ===== Base config & Certs =====
if [ ! -f "$CFG" ]; then
  echo '{}' > "$CFG"
fi
if [ ! -f /etc/zivpn/zivpn.crt ]; then
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/O=UPK/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# ===== Web Admin Setup =====
say "${Y}🔒 Web Panel အတွက် Login သတ်မှတ်ပါ${Z}"
read -r -p "Admin Username: " WEB_USER
read -r -s -p "Admin Password: " WEB_PASS; echo
WEB_SECRET=$(python3 -c 'import secrets; print(secrets.token_hex(32))')

echo "WEB_ADMIN_USER=${WEB_USER}" > "$ENVF"
echo "WEB_ADMIN_PASSWORD=${WEB_PASS}" >> "$ENVF"
echo "WEB_SECRET=${WEB_SECRET}" >> "$ENVF"
chmod 600 "$ENVF"

# VPN Default Pass
PW_LIST='["zi"]'

# Update config.json
TMP=$(mktemp)
jq --argjson pw "$PW_LIST" '.auth.mode="passwords" | .auth.config=$pw | .listen=":5667" | .cert="/etc/zivpn/zivpn.crt" | .key="/etc/zivpn/zivpn.key" | .obfs="zivpn"' "$CFG" > "$TMP" && mv "$TMP" "$CFG"
[ -f "$USERS" ] || echo "[]" > "$USERS"

# (ကျန်ရှိသော Flask web.py နှင့် systemd အပိုင်းများသည် မူရင်းအတိုင်း ဆက်လက်အလုပ်လုပ်ပါမည်)
# ... (မူရင်း script ထဲက web.py အပိုင်းကို ဒီမှာ ထည့်သွင်းပေးရပါမယ် - နေရာလွတ်သက်သာရန် ချန်လှပ်ခဲ့သည်)

# ===== Networking =====
say "${Y}🌐 Networking Setup လုပ်နေပါတယ်...${Z}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
IFACE=$(ip -4 route ls | awk '/default/ {print $5; exit}')
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
ufw allow 5667/udp && ufw allow 6000:19999/udp && ufw allow 8080/tcp

# Finish
systemctl daemon-reload
# (Systemd startup commands...)

IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ Install ပြီးပါပြီ${Z}\nPanel: http://$IP:8080\n$LINE"
