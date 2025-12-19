#!/bin/bash
# ============================================================
# Destiny 2 Matchmaking Firewall
# Steam Datagram Relay + PSN + OpenVPN + AWS
# Teardown-based matchmaking control
# Legacy compatible with d2firewall.sh (-a ...)
# ============================================================

######################## CONFIG ########################

INTERFACE="tun0"

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$BASE_DIR/cache"
RULES_DIR="$BASE_DIR/rules"
STATE_DIR="$BASE_DIR/state"

SESSION_LOG="$CACHE_DIR/sessions.log"
LAST_LOBBY="$CACHE_DIR/last_lobby.txt"
KNOWN_IDS="$CACHE_DIR/known_ids.txt"

ALLOW_LIST="$RULES_DIR/allow.txt"
BLOCK_LIST="$RULES_DIR/block.txt"

STATE_FILE="$STATE_DIR/firewall.state"
VERSION_FILE="$BASE_DIR/VERSION"

STEAM_REGEX="steamid:[0-9]{17}"
PSN_REGEX="psn-4[0-9A-Fa-f]{7,16}"
ID_REGEX="($STEAM_REGEX|$PSN_REGEX)"

#######################################################

mkdir -p "$CACHE_DIR" "$RULES_DIR" "$STATE_DIR"
touch "$SESSION_LOG" "$LAST_LOBBY" "$KNOWN_IDS" "$ALLOW_LIST" "$BLOCK_LIST" "$STATE_FILE"

[[ ! -f "$VERSION_FILE" ]] && echo "1.1.0" > "$VERSION_FILE"

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

#################### OBSERVE / SNIFF ##################

observe() {
  echo "[*] Observando teardown do Destiny 2 (Steam + PSN)"
  echo "[*] Pressione qualquer tecla para parar"

  ngrep -l -q -W byline -d "$INTERFACE" udp | \
  grep --line-buffered -E "$ID_REGEX" | \
  while read -r line; do
    ip=$(echo "$line" | awk '{print $1}')
    id=$(echo "$line" | grep -oE "$ID_REGEX")
    ts=$(date +"%Y-%m-%d %H:%M:%S")

    echo "$ts $ip $id" >> "$SESSION_LOG"
    echo "$ip $id" >> "$LAST_LOBBY"
    echo "$id" >> "$KNOWN_IDS"

    awk '!a[$0]++' "$LAST_LOBBY" > /tmp/lb && mv /tmp/lb "$LAST_LOBBY"
    awk '!a[$0]++' "$KNOWN_IDS" > /tmp/ki && mv /tmp/ki "$KNOWN_IDS"
  done &

  read -n 1
  pkill -15 ngrep
  echo
  echo "[✓] Observação finalizada"
}

#################### FIREWALL #########################

start_firewall() {
  echo "[*] Ativando controle de matchmaking"

  iptables -F FORWARD

  while read -r id; do
    [[ -z "$id" ]] && continue
    iptables -I FORWARD -i "$INTERFACE" -m string --string "$id" --algo bm -j ACCEPT
  done < "$ALLOW_LIST"

  while read -r id; do
    [[ -z "$id" ]] && continue
    iptables -A FORWARD -i "$INTERFACE" -m string --string "$id" --algo bm -j DROP
  done < "$BLOCK_LIST"

  set_state "started"
  echo "[✓] Firewall ATIVO"
}

stop_firewall() {
  echo "[*] Desativando controle de matchmaking"
  iptables -F FORWARD
  set_state "stopped"
  echo "[✓] Firewall DESATIVADO"
}

#################### LISTAGENS ########################

list_lobby() {
  echo "=== ÚLTIMO LOBBY ==="
  [[ ! -s "$LAST_LOBBY" ]] && echo "(vazio)" && return
  nl -w2 -s'. ' "$LAST_LOBBY"
}

list_known() {
  echo "=== IDS CONHECIDOS (STEAM / PSN) ==="
  nl -w2 -s'. ' "$KNOWN_IDS"
}

################ PREVIEW PRÓXIMA SESSÃO ###############

next_session() {
  echo "=== PRÓXIMA SESSÃO (PREVISTA) ==="

  if [[ ! -s "$ALLOW_LIST" ]]; then
    echo "ALLOW vazio → lobby aberto"
    return
  fi

  grep -v -F -f "$BLOCK_LIST" "$ALLOW_LIST" | nl -w2 -s'. '
}

################## EDITAR REGRAS ######################

allow_id() {
  read -p "SteamID ou PSNID para ALLOW: " id
  [[ -z "$id" ]] && return
  echo "$id" >> "$ALLOW_LIST"
  awk '!a[$0]++' "$ALLOW_LIST" > /tmp/a && mv /tmp/a "$ALLOW_LIST"
  echo "[✓] ID permitido"
}

block_id() {
  read -p "SteamID ou PSNID para BLOCK: " id
  [[ -z "$id" ]] && return
  echo "$id" >> "$BLOCK_LIST"
  awk '!a[$0]++' "$BLOCK_LIST" > /tmp/b && mv /tmp/b "$BLOCK_LIST"
  echo "[✓] ID bloqueado"
}

#################### UPDATE ###########################

update_script() {
  echo "[*] Atualização via git"
  echo "Versão atual: $(cat "$VERSION_FILE")"
  echo "Use: git pull"
}

################ LEGACY FLAGS (-a) ###################

ACTION=""

while getopts "a:" opt; do
  case $opt in
    a) ACTION="$OPTARG" ;;
  esac
done

CMD="${ACTION:-$1}"

######################## MENU #########################

case "$CMD" in
  observe|sniff) observe ;;
  start) start_firewall ;;
  stop) stop_firewall ;;
  state) echo "Estado: $(get_state)" ;;
  lobby) list_lobby ;;
  allow) allow_id ;;
  block) block_id ;;
  next) next_session ;;
  known) list_known ;;
  update) update_script ;;
  *)
    echo "Uso:"
    echo "  sudo bash destiny2-mm.sh -a sniff"
    echo "  sudo bash destiny2-mm.sh -a start"
    echo "  sudo bash destiny2-mm.sh -a stop"
    echo "  sudo bash destiny2-mm.sh -a lobby"
    echo "  sudo bash destiny2-mm.sh -a allow"
    echo "  sudo bash destiny2-mm.sh -a block"
    echo "  sudo bash destiny2-mm.sh -a next"
    ;;
esac
