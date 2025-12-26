#!/bin/bash
# Destiny 2 Matchmaking Firewall
# FINAL v3 – STABLE
# Trials matchmaking block + Platform Sniffer (PSN / Xbox / Steam / Epic)

INTERFACE="tun0"
DEFAULT_NET="10.8.0.0/24"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

LOGFILE="platform.log"

while getopts "a:" opt; do
  case $opt in
    a) action=$OPTARG ;;
    *) echo "Usage: $0 -a setup|start|stop|reset|sniff"; exit 1 ;;
  esac
done

# =========================
# DEPENDENCIES + OPENVPN
# =========================
install_dependencies () {
  sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
  sudo ufw disable > /dev/null
  sudo apt-get update > /dev/null
  sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q install \
    iptables iptables-persistent ngrep > /dev/null
}

# =========================
# IPTABLES RESET + OPENVPN
# =========================
reset_ip_tables () {
  sudo iptables -P INPUT ACCEPT
  sudo iptables -P FORWARD ACCEPT
  sudo iptables -P OUTPUT ACCEPT
  sudo iptables -F
  sudo iptables -X

  if ip a | grep -q "$INTERFACE"; then
    sudo iptables -t nat -A POSTROUTING -s $DEFAULT_NET -o eth0 -j MASQUERADE
    sudo iptables -A INPUT -p udp --dport 1194 -j ACCEPT
    sudo iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -A FORWARD -s $DEFAULT_NET -j ACCEPT
  fi
}

# =========================
# TRIALS MATCHMAKING BLOCK
# (INDEPENDENTE)
# =========================
setup_trials () {
  echo -e "${RED}Applying Trials matchmaking block...${NC}"
  reset_ip_tables

  echo "trials" > data.txt
  echo "$DEFAULT_NET" >> data.txt

  echo "# Trials matchmaking traffic block (UDP ports)" > reject.rule
  sudo iptables -I FORWARD -p udp --dport 27000:27200 -j REJECT
  echo "-p udp --dport 27000:27200 -j REJECT" >> reject.rule

  sudo iptables-save > /etc/iptables/rules.v4
  echo -e "${GREEN}Trials block ACTIVE.${NC}"
}

start_trials () {
  while IFS= read -r rule; do
    [[ "$rule" =~ ^#|^$ ]] && continue
    sudo iptables -I FORWARD $rule
  done < reject.rule
}

stop_trials () {
  while IFS= read -r rule; do
    [[ "$rule" =~ ^#|^$ ]] && continue
    sudo iptables -D FORWARD $rule 2>/dev/null
  done < reject.rule
}

# =========================
# PLATFORM MATCH STRING
# =========================
get_platform_match_str () {
  case "$1" in
    psn)   echo "psn-4" ;;
    xbox)  echo "xboxpwid:" ;;
    steam) echo "steamid:" ;;
    epic)  echo "epicgamesid:" ;;
    *)     echo "" ;;
  esac
}

# =========================
# PLATFORM SNIFFER (LOG ONLY)
# =========================
sniff_platforms () {
  echo -e "${RED}Sniffing platforms... Press any key to stop.${NC}"
  echo "=== Sniff started: $(date) ===" >> $LOGFILE

  for platform in psn xbox steam epic; do
    match=$(get_platform_match_str $platform)
    if [ -n "$match" ]; then
      ngrep -q -W byline -d $INTERFACE "$match" udp | \
  grep --line-buffered "$match" | \
  sed "s/^/[$(date '+%F %T')] $platform: /" >> $LOGFILE &
    fi
  done

  while true; do
    read -t 1 -n 1 && break
  done

  pkill -15 ngrep
  echo "=== Sniff stopped: $(date) ===" >> $LOGFILE
  echo -e "${GREEN}Sniff complete. Logged to $LOGFILE${NC}"
}

# =========================
# MAIN
# =========================
case "$action" in
  setup)
    install_dependencies
    setup_trials
    ;;
  start) start_trials ;;
  stop)  stop_trials ;;
  reset) reset_ip_tables ;;
  sniff) sniff_platforms ;;
  *)
    echo "Usage: $0 -a setup|start|stop|reset|sniff"
    ;;
esac
