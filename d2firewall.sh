#!/bin/bash
# Destiny 2 Matchmaking Firewall
# FINAL v2 – STABLE
# Steam: UDP 27000–27200 ONLY (no 3074)

INTERFACE="tun0"
DEFAULT_NET="10.8.0.0/24"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

while getopts "a:" opt; do
  case $opt in
    a) action=$OPTARG ;;
    *) echo "Usage: $0 -a setup|start|stop|reset"; exit 1 ;;
  esac
done

reset_ip_tables () {
  sudo iptables -P INPUT ACCEPT
  sudo iptables -P FORWARD ACCEPT
  sudo iptables -P OUTPUT ACCEPT
  sudo iptables -F
  sudo iptables -X

  if ip a | grep -q "$INTERFACE"; then
    sudo iptables -t nat -A POSTROUTING -s $DEFAULT_NET -o eth0 -j MASQUERADE
    sudo iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -A FORWARD -s $DEFAULT_NET -j ACCEPT
  fi
}

setup () {
  echo -e "${RED}Setting up firewall rules...${NC}"
  reset_ip_tables

  echo "steam" > data.txt
  echo "$DEFAULT_NET" >> data.txt

  echo "# Steam matchmaking block (UDP ports)" > reject.rule

  sudo iptables -I FORWARD -p udp --dport 27000:27200 -j REJECT
  echo "-p udp --dport 27000:27200 -j REJECT" >> reject.rule

  sudo iptables-save > /etc/iptables/rules.v4
  echo -e "${GREEN}Setup complete. Firewall ACTIVE.${NC}"
}

start_fw () {
  echo "Enabling matchmaking block..."
  while IFS= read -r rule; do
    [[ "$rule" =~ ^[[:space:]]*#|^[[:space:]]*$ ]] && continue
    sudo iptables -I FORWARD $rule
  done < reject.rule
}

stop_fw () {
  echo "Disabling matchmaking block..."
  while IFS= read -r rule; do
    [[ "$rule" =~ ^[[:space:]]*#|^[[:space:]]*$ ]] && continue
    sudo iptables -D FORWARD $rule 2>/dev/null
  done < reject.rule
}

case "$action" in
  setup) setup ;;
  start) start_fw ;;
  stop)  stop_fw ;;
  reset) reset_ip_tables ;;
  *) echo "Usage: $0 -a setup|start|stop|reset" ;;
esac
