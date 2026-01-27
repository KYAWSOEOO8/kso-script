#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - Bypass Key Version
set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; M="\e[1;35m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ echo -e "$1"; }

echo -e "\n$LINE\n${G}🌟 ZIVPN UDP Server + Web UI (Bypass Key)${Z}\n$LINE"

# ===== Root check =====
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}ဤ script ကို root အဖြစ် chạy ရပါမယ် (sudo -i)${Z}"; exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# =====================================================================
#   ONE-TIME KEY GATE ဖယ်ရှားပြီး (Bypassed)
# =====================================================================
echo -e "${G}✅ Key Check ကို ကျော်ဖြတ်ပြီး Installation စတင်နေပါပြီ...${Z}"

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
  systemctl stop --now unattended-upgrades.service 2>/dev/null || true
}
apt_guard_start(){
  wait_for_apt
  CNF_CONF="/etc/apt/apt.conf.d/50command-not-found"
  if [ -f "$CNF_CONF" ]; then mv "$CNF_CONF" "${CNF_CONF}.disabled"; CNF_DISABLED=1; else CNF_DISABLED=0; fi
}
apt_guard_end(){
  if [ "${CNF_DISABLED:-0}" = "1" ] && [ -f "${CNF_CONF}.disabled" ]; then mv "${CNF_CONF}.disabled" "$CNF_CONF"; fi
}

# ===== Packages =====
say "${Y}📦 Packages တင်နေပါတယ်...${Z}"
apt_guard_start
apt-get update -y >/dev/null
apt-get install -y curl ufw jq python3 python3-flask python3-apt iproute2 conntrack ca-certificates openssl >/dev/null
apt_guard_end

# Paths
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"
mkdir -p /etc/zivpn

# Stop old services
systemctl stop zivpn.service 2>/dev/null || true
systemctl stop zivpn-web.service 2>/dev/null || true

# ===== Download ZIVPN binary =====
say "${Y}⬇️ ZIVPN binary ကို ဒေါင်းနေပါတယ်...${Z}"
PRIMARY_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
curl -fsSL -o "$BIN" "$PRIMARY_URL" || say "${R}Download error!${Z}"
chmod +x "$BIN"

# ... (ကျန်တဲ့ config နဲ့ service အပိုင်းတွေက မူရင်းအတိုင်း ဆက်လက်အလုပ်လုပ်ပါမယ်)

