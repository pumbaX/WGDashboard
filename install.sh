#!/bin/bash
# ============================================================
#  AmneziaWG + WGDashboard — Auto Installer for Ubuntu 24.04
#  Usage: bash <(curl -fsSL https://raw.githubusercontent.com/YOUfffR/REPO/main/install.sh)
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# Root check
if [[ $EUID -ne 0 ]]; then
  err "Запусти от root: sudo bash install.sh"
fi

clear
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════════════╗"
echo "  ║     AmneziaWG + WGDashboard Installer           ║"
echo "  ║     Ubuntu 22.04 / 24.04 / 24.10                ║"
echo "  ╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

# Главное меню
echo -e "${BOLD}Что установить?${NC}"
echo "  1) AmneziaWG + WGDashboard  (рекомендуется)"
echo "  2) Только AmneziaWG         (без дашборда)"
echo "  3) Только WGDashboard       (WireGuard уже есть)"
echo "  4) Удалить WGDashboard"
echo "  0) Выход"
echo ""
read -rp "Выбор [0-4]: " MAIN_CHOICE

case $MAIN_CHOICE in
  1) MODE="full" ;;
  2) MODE="awg_only" ;;
  3) MODE="dash_only" ;;
  4) MODE="uninstall" ;;
  0) exit 0 ;;
  *) err "Неверный выбор" ;;
esac

# Параметры установки
if [[ "$MODE" != "uninstall" ]]; then
  echo ""
  read -rp "Порт WGDashboard [Enter = 10086]: " DASH_PORT
  DASH_PORT=${DASH_PORT:-10086}

  if [[ "$MODE" != "dash_only" ]]; then
    echo ""
    read -rp "Порт AmneziaWG [Enter = 51820]: " AWG_PORT
    AWG_PORT=${AWG_PORT:-51820}

    echo ""
    read -rp "Имя AWG-интерфейса [Enter = awg0]: " AWG_IF
    AWG_IF=${AWG_IF:-awg0}

    echo ""
    read -rp "Подсеть VPN [Enter = 10.0.0.1/24]: " AWG_SUBNET
    AWG_SUBNET=${AWG_SUBNET:-10.0.0.1/24}
  fi

  NET_IF=$(ip route | grep default | awk '{print $5}' | head -1)
  info "Основной сетевой интерфейс: ${BOLD}$NET_IF${NC}"

  echo ""
  INSTALL_USER=${SUDO_USER:-root}
  DEFAULT_PATH="/home/${INSTALL_USER}/WGDashboard"
  [[ "$INSTALL_USER" == "root" ]] && DEFAULT_PATH="/root/WGDashboard"
  read -rp "Путь установки WGDashboard [Enter = $DEFAULT_PATH]: " INSTALL_PATH
  INSTALL_PATH=${INSTALL_PATH:-$DEFAULT_PATH}
fi

# Подтверждение
echo ""
echo -e "${BOLD}══════════════ Параметры ══════════════${NC}"
echo "  Режим:           $MODE"
if [[ "$MODE" != "uninstall" ]]; then
  echo "  Путь:            $INSTALL_PATH"
  echo "  Порт дашборда:   $DASH_PORT"
  if [[ "$MODE" != "dash_only" ]]; then
    echo "  AWG порт:        $AWG_PORT"
    echo "  AWG интерфейс:   $AWG_IF"
    echo "  AWG подсеть:     $AWG_SUBNET"
    echo "  Сеть. интерфейс: $NET_IF"
  fi
fi
echo -e "${BOLD}═══════════════════════════════════════${NC}"
echo ""
read -rp "Продолжить? [y/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || exit 0

# ════════════════ ФУНКЦИИ ════════════════

install_amneziawg() {
  info "Установка AmneziaWG..."
  apt-get update -y -qq
  apt-get install -y -qq \
    software-properties-common python3-launchpadlib gnupg2 \
    "linux-headers-$(uname -r)" net-tools git iptables curl

  add-apt-repository -y ppa:amnezia/ppa
  apt-get update -y -qq
  # Ставим только модуль ядра из PPA
  apt-get install -y amneziawg

  # Собираем свежие amneziawg-tools из исходников (поддержка AWG 2.0)
  info "Сборка amneziawg-tools из исходников (поддержка AWG 2.0)..."
  apt-get install -y -qq gcc make libmnl-dev pkg-config
  rm -rf /tmp/amneziawg-tools
  git clone -q https://github.com/amnezia-vpn/amneziawg-tools.git /tmp/amneziawg-tools
  make -C /tmp/amneziawg-tools/src -j$(nproc)
  cp /tmp/amneziawg-tools/src/wg /usr/bin/awg
  cp /tmp/amneziawg-tools/src/wg-quick /usr/bin/awg-quick
  chmod +x /usr/bin/awg /usr/bin/awg-quick
  rm -rf /tmp/amneziawg-tools
  ok "amneziawg-tools собран: $(awg --version)"

  modprobe amneziawg

  if lsmod | grep -q amneziawg; then
    ok "Модуль amneziawg загружен"
  else
    err "Модуль не загрузился. Проверь: sudo dkms status"
  fi

  echo "amneziawg" > /etc/modules-load.d/amneziawg.conf

  grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || \
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  sysctl -p > /dev/null

  mkdir -p /etc/amnezia/amneziawg
  chmod 755 /etc/amnezia/amneziawg
  ok "AmneziaWG установлен"
}

install_wgdashboard() {
  info "Установка WGDashboard..."
  apt-get install -y -qq wireguard-tools git python3 python3-pip net-tools

  if [[ -d "$INSTALL_PATH" ]]; then
    warn "Папка существует, обновляем..."
    cd "$INSTALL_PATH" && git pull -q
  else
    git clone -q https://github.com/WGDashboard/WGDashboard.git "$INSTALL_PATH"
  fi

  cd "$INSTALL_PATH/src"
  chmod +x ./wgd.sh

  if [[ "$DASH_PORT" != "10086" ]]; then
    sed -i "s/10086/$DASH_PORT/g" wgd.sh 2>/dev/null || true
  fi

  ./wgd.sh install

  chmod -R 755 /etc/wireguard
  mkdir -p /etc/amnezia/amneziawg
  chmod -R 755 /etc/amnezia
  ok "WGDashboard установлен"
}

setup_systemd() {
  info "Настройка systemd..."
  SRC_PATH="$INSTALL_PATH/src"

  cat > /etc/systemd/system/wg-dashboard.service << EOF
[Unit]
Description=WGDashboard
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=${SRC_PATH}/gunicorn.pid
WorkingDirectory=${SRC_PATH}
ExecStart=${SRC_PATH}/wgd.sh start
ExecStop=${SRC_PATH}/wgd.sh stop
ExecReload=${SRC_PATH}/wgd.sh restart
TimeoutSec=120
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable wg-dashboard
  systemctl start wg-dashboard
  sleep 3

  if systemctl is-active --quiet wg-dashboard; then
    ok "Сервис wg-dashboard запущен"
  else
    warn "Сервис не запустился. Проверь: journalctl -u wg-dashboard -n 30"
  fi
}

setup_firewall() {
  info "Настройка фаервола..."
  if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
    ufw allow "$DASH_PORT/tcp" > /dev/null
    [[ "$MODE" != "dash_only" ]] && ufw allow "$AWG_PORT/udp" > /dev/null
    ufw reload > /dev/null
    ok "UFW обновлён"
  else
    warn "UFW не активен, порты не открыты автоматически"
  fi
}

create_awg_config() {
  info "Создание AWG конфигурации..."
  AWG_CONF="/etc/amnezia/amneziawg/${AWG_IF}.conf"

  if [[ -f "$AWG_CONF" ]]; then
    warn "Конфиг $AWG_CONF уже существует, пропускаем"
    return
  fi

  PRIVATE_KEY=$(awg genkey)
  PUBLIC_KEY=$(echo "$PRIVATE_KEY" | awg pubkey)

  # Jc / Jmin / Jmax
  JC=$((RANDOM % 8 + 3))
  JMIN=$((RANDOM % 50 + 50))
  JMAX=$((JMIN + RANDOM % 400 + 200))
  [[ $JMAX -gt 1280 ]] && JMAX=1280

  # S1 / S2
  S1=$((RANDOM % 50 + 15))
  S2=$((RANDOM % 50 + 15))
  while [[ $((S1 + 56)) -eq $S2 ]]; do S2=$((S2 + 1)); done

  # ── S3 / S4 ───────────────────────────────────────────────
  S3=$((RANDOM % 32))
  S4=$((RANDOM % 16))

  # ── H1-H4 диапазоны AWG 2.0 — не перекрываются ───────────
  BASE=$((RANDOM % 50000 + 100000))
  STEP=$((RANDOM % 30000 + 80000))
  RANGE=$((RANDOM % 20000 + 30000))
  H1_MIN=$BASE;           H1_MAX=$((H1_MIN + RANGE))
  H2_MIN=$((H1_MAX + STEP)); H2_MAX=$((H2_MIN + RANGE))
  H3_MIN=$((H2_MAX + STEP)); H3_MAX=$((H3_MIN + RANGE))
  H4_MIN=$((H3_MAX + STEP)); H4_MAX=$((H4_MIN + RANGE))

  # ── I1 QUIC-имитация, I2 энтропия ────────────────────────
  QUIC_LIST=("c7000000010" "c0000000011" "c000000001" "c700000001")
  QUIC=${QUIC_LIST[$((RANDOM % 4))]}
  R1=$((RANDOM % 30 + 20))
  R2=$((RANDOM % 20 + 10))
  I1="<b 0x${QUIC}><r ${R1}><c><t>"
  I2="<r ${R2}><c><t>"

  cat > "$AWG_CONF" << EOF
[Interface]
Address = ${AWG_SUBNET}
ListenPort = ${AWG_PORT}
PrivateKey = ${PRIVATE_KEY}
DNS = 1.1.1.1, 8.8.8.8
Jc = ${JC}
Jmin = ${JMIN}
Jmax = ${JMAX}
S1 = ${S1}
S2 = ${S2}
S3 = ${S3}
S4 = ${S4}
H1 = ${H1_MIN}-${H1_MAX}
H2 = ${H2_MIN}-${H2_MAX}
H3 = ${H3_MIN}-${H3_MAX}
H4 = ${H4_MIN}-${H4_MAX}
I1 = ${I1}
I2 = ${I2}
PostUp = iptables -A FORWARD -i ${AWG_IF} -j ACCEPT; iptables -A FORWARD -o ${AWG_IF} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${NET_IF} -j MASQUERADE;
PreDown = iptables -D FORWARD -i ${AWG_IF} -j ACCEPT; iptables -D FORWARD -o ${AWG_IF} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${NET_IF} -j MASQUERADE;
EOF

  chmod 600 "$AWG_CONF"
  ok "AWG 2.0 конфиг создан: $AWG_CONF"
  echo ""
  info "PublicKey сервера: ${BOLD}$PUBLIC_KEY${NC}"
  echo ""
  info "AWG 2.0 параметры:"
  echo "   Jc=${JC}  Jmin=${JMIN}  Jmax=${JMAX}"
  echo "   S1=${S1}  S2=${S2}  S3=${S3}  S4=${S4}"
  echo "   H1=${H1_MIN}-${H1_MAX}"
  echo "   H2=${H2_MIN}-${H2_MAX}"
  echo "   H3=${H3_MIN}-${H3_MAX}"
  echo "   H4=${H4_MIN}-${H4_MAX}"
  echo "   I1=${I1}"
  echo "   I2=${I2}"
  echo ""
  warn "Сохрани эти параметры — они нужны для настройки клиентов!"
}

do_uninstall() {
  warn "Удаление WGDashboard..."
  systemctl stop wg-dashboard 2>/dev/null || true
  systemctl disable wg-dashboard 2>/dev/null || true
  rm -f /etc/systemd/system/wg-dashboard.service
  systemctl daemon-reload

  echo ""
  read -rp "Удалить папку WGDashboard? [y/N]: " DEL_FILES
  if [[ "$DEL_FILES" =~ ^[Yy]$ ]]; then
    INSTALL_USER=${SUDO_USER:-root}
    DEFAULT_PATH="/home/${INSTALL_USER}/WGDashboard"
    [[ "$INSTALL_USER" == "root" ]] && DEFAULT_PATH="/root/WGDashboard"
    read -rp "Путь [Enter = $DEFAULT_PATH]: " DEL_PATH
    DEL_PATH=${DEL_PATH:-$DEFAULT_PATH}
    rm -rf "$DEL_PATH"
    ok "Папка удалена"
  fi

  ok "WGDashboard удалён"
  exit 0
}

# ════════════════ ЗАПУСК ════════════════

case $MODE in
  uninstall) do_uninstall ;;
  awg_only)
    install_amneziawg
    create_awg_config
    setup_firewall
    ;;
  dash_only)
    install_wgdashboard
    setup_systemd
    setup_firewall
    ;;
  full)
    install_amneziawg
    create_awg_config
    install_wgdashboard
    setup_systemd
    setup_firewall
    ;;
esac

# Итог
SERVER_IP=$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

echo ""
echo -e "${BOLD}${GREEN}══════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  Готово!${NC}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════════${NC}"
echo ""

if [[ "$MODE" == "full" || "$MODE" == "dash_only" ]]; then
  echo -e "  Дашборд:  ${BOLD}http://${SERVER_IP}:${DASH_PORT}${NC}"
  echo -e "  Логин:    ${BOLD}admin${NC} / ${BOLD}admin${NC}  ← сразу сменить!"
  echo ""
fi

if [[ "$MODE" == "full" || "$MODE" == "awg_only" ]]; then
  echo -e "  AWG конфиг: ${BOLD}/etc/amnezia/amneziawg/${AWG_IF}.conf${NC}"
  echo -e "  AWG порт:   ${BOLD}${AWG_PORT}/udp${NC}"
  echo ""
fi

echo -e "  ${CYAN}systemctl status wg-dashboard${NC}"
echo -e "  ${CYAN}journalctl -u wg-dashboard -f${NC}"
echo -e "  ${CYAN}awg show${NC}"
echo ""
