#!/bin/bash
# ============================================================
# Destiny 2 Firewall – Console / Router / OpenVPN / AWS
#
# MODELO ATUAL (FUNCIONAL):
# - Registra PSNID no teardown (histórico)
# - Registra IP remoto SDR usado na sessão
# - Controle MANUAL de matchmaking (liga / desliga)
# - -a start  → bloqueio TOTAL de novas conexões
# - -a stop   → libera tudo
#
# NÃO tenta permitir jogador por PSNID (isso não funciona mais)
# ============================================================

######################## CONFIG ########################

INTERFACE="tun0"          # interface do túnel OpenVPN
STATE_DIR="state"
CACHE_DIR="cache"

PSN_LOG="$CACHE_DIR/psnid.log"
SDR_LOG="$CACHE_DIR/sdr_ips.log"
SESSION_LOG="$CACHE_DIR/sessions.log"
STATE_FILE="$STATE_DIR/firewall.state"

PSN_REGEX="psn-4[0-9A-Fa-f]{7,16}"

#######################################################

mkdir -p "$CACHE_DIR" "$STATE_DIR"
touch "$PSN_LOG" "$SDR_LOG" "$SESSION_LOG" "$STATE_FILE"

######################## CHECKS ########################

if [[ $EUID -ne 0 ]]; then
  echo "[!] Execute com sudo."
  exit 1
fi

if ! ip a | grep -q "$INTERFACE"; then
  echo "[!] Interface $INTERFACE não encontrada."
  exit 1
fi

######################## STATE #########################

get_state() {
  cat "$STATE_FILE" 2>/dev/null || echo "stopped"
}

set_state() {
  echo "$1" > "$STATE_FILE"
}

#################### SNIFF / OBSERVE ##################

observe() {
  echo "[*] Observando teardown do Destiny 2"
  echo "[*] Registrando PSNID + IP remoto SDR"
  echo "[*] Pressione qualquer tecla para parar"

  ngrep -l -q -W byline -d "$INTERFACE" udp | \
  while read -r line; do

    # IP remoto (SDR / peer)
    REMOTE_IP=$(echo "$line" | awk '{print $1}')

    # PSNID (se existir)
    PSNID=$(echo "$line" | grep -oE "$PSN_REGEX")

    TS=$(date +"%Y-%m-%d %H:%M:%S")

    # Sempre registra IP remoto (é isso que importa para controle)
    if [[ -n "$REMOTE_IP" ]]; then
      echo "$REMOTE_IP" >> "$SDR_LOG"
      echo "$TS IP $REMOTE_IP" >> "$SESSION_LOG"
    fi

    # Registra PSNID apenas como histórico
    if [[ -n "$PSNID" ]]; then
      echo "$PSNID" >> "$PSN_LOG"
      echo "$TS PSN $PSNID" >> "$SESSION_LOG"
    fi

    # remove duplicados
    awk '!a[$0]++' "$SDR_LOG" > /tmp/sdr && mv /tmp/sdr "$SDR_LOG"
    awk '!a[$0]++' "$PSN_LOG" > /tmp/psn && mv /tmp/psn "$PSN_LOG"

  done &

  read -n 1
  pkill -15 ngrep

  echo
  echo "[✓] Observação finalizada"
}

#################### FIREWALL #########################

start_firewall() {
  echo "[*] Ativando bloqueio TOTAL de novas conexões"

  iptables -F FORWARD

  # Permite conexões já estabelecidas
  iptables -I FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  # BLOQUEIA TODAS as novas conexões UDP (matchmaking)
  iptables -A FORWARD -p udp -m conntrack --ctstate NEW -j DROP

  set_state "started"
  echo "[✓] Firewall ATIVO – novas conexões BLOQUEADAS"
}

stop_firewall() {
  echo "[*] Desativando firewall"
  iptables -F FORWARD
  set_state "stopped"
  echo "[✓] Firewall DESATIVADO"
}

#################### LISTAGENS ########################

list_psn() {
  echo "=== PSNIDs REGISTRADAS (HISTÓRICO) ==="
  nl -ba "$PSN_LOG"
}

list_sdr() {
  echo "=== IPs SDR REGISTRADOS ==="
  nl -ba "$SDR_LOG"
}

list_state() {
  echo "Estado: $(get_state)"
}

#################### LEGACY FLAGS #####################

ACTION=""

while getopts "a:" opt; do
  case $opt in
    a) ACTION="$OPTARG" ;;
  esac
done

CMD="${ACTION:-$1}"

######################## MENU #########################

case "$CMD" in
  sniff|observe)
    observe
    ;;
  start)
    start_firewall
    ;;
  stop)
    stop_firewall
    ;;
  state)
    list_state
    ;;
  list)
    echo "Use:"
    echo "  -a list psn"
    echo "  -a list sdr"
    ;;
  psn)
    list_psn
    ;;
  sdr)
    list_sdr
    ;;
  *)
    echo "Uso (modo antigo):"
    echo "  sudo bash d2firewall.sh -a sniff"
    echo "  sudo bash d2firewall.sh -a start"
    echo "  sudo bash d2firewall.sh -a stop"
    echo "  sudo bash d2firewall.sh -a state"
    echo "  sudo bash d2firewall.sh -a psn"
    echo "  sudo bash d2firewall.sh -a sdr"
    ;;
esac
