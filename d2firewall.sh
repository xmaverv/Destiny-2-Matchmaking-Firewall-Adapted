#!/bin/bash
# Destiny 2 Matchmaking Firewall
# Steam SDR FINAL – OUTPUT + FORWARD
# Original credits: @BasRaayman @inchenzo

INTERFACE="tun0"
DEFAULT_NET="10.8.0.0/24"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

while getopts "a:" opt; do
  case $opt in
    a) action=$OPTARG ;;
    *) exit 1 ;;
  esac
done

reset_ip_tables () {
  sudo service iptables restart

  sudo iptables -P INPUT ACCEPT
  sudo iptables -P FORWARD ACCEPT
  sudo iptables -P OUTPUT ACCEPT

  sudo iptables -F
  sudo iptables -X

  if ip a | grep -q tun0; then
    sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
    sudo iptables -A INPUT -p udp --dport 1194 -j ACCEPT
    sudo iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -A FORWARD -s 10.8.0.0/24 -j ACCEPT
  fi
}

install_dependencies () {
  sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
  sudo ufw disable >/dev/null
  sudo apt-get update >/dev/null
  sudo DEBIAN_FRONTEND=noninteractive apt-get -y install \
    iptables iptables-persistent ngrep >/dev/null
}

setup () {

  reset_ip_tables

  read -p "Platform (steam_sdr only): " platform
  platform=${platform:-steam_sdr}

  read -p "Network/netmask: " net
  net=${net:-$DEFAULT_NET}

  echo "$platform" > /tmp/data.txt
  echo "$net" >> /tmp/data.txt
  echo "n" >> /tmp/data.txt

  ids=()

  echo -e "${BLUE}Start matchmaking NOW.${NC}"
  echo -e "${RED}Press any key to stop sniffing.${NC}"
  sleep 1

  ngrep -q -W byline -d $INTERFACE udp portrange 27020-27050 \
  | grep --line-buffered -oP '(?<=IP )([0-9]{1,3}\.){3}[0-9]{1,3}' \
  | grep -v "$(ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')" \
  | sort -u | tee -a /tmp/data.txt &

  while true; do read -t 1 -n 1 && break; done
  pkill -15 ngrep

  awk '!a[$0]++' /tmp/data.txt > /tmp/t && mv /tmp/t /tmp/data.txt

  snum=$(tail -n +4 /tmp/data.txt | wc -l)
  awk "NR==4{print $snum}1" /tmp/data.txt > /tmp/t && mv /tmp/t /tmp/data.txt

  tmp_ids=$(tail -n +5 /tmp/data.txt)
  while read -r ip; do
    ids+=( "$ip" )
  done <<< "$tmp_ids"

  mv /tmp/data.txt ./data.txt

  # ==========================
  # MATCHMAKING RESTRICTION
  # ==========================

  # ALLOW WHITELISTED RELAYS (OUTPUT + FORWARD)
  for ip in "${ids[@]}"; do
    sudo iptables -I OUTPUT  -d "$ip" -p udp --dport 27020:27050 -j ACCEPT
    sudo iptables -I OUTPUT  -s "$ip" -p udp --sport 27020:27050 -j ACCEPT

    sudo iptables -I FORWARD -d "$ip" -p udp --dport 27020:27050 -j ACCEPT
    sudo iptables -I FORWARD -s "$ip" -p udp --sport 27020:27050 -j ACCEPT
  done

  # DEFAULT DENY (CRÍTICO)
  echo "-p udp --dport 27020:27050 -j REJECT" > reject.rule
  sudo iptables -A OUTPUT  -p udp --dport 27020:27050 -j REJECT
  sudo iptables -A FORWARD -p udp --dport 27020:27050 -j REJECT

  iptables-save > /etc/iptables/rules.v4

  echo -e "${GREEN}MATCHMAKING REALMENTE BLOQUEADO.${NC}"
}

if [ "$action" == "setup" ]; then
  install_dependencies
  setup

elif [ "$action" == "stop" ]; then
  reject=$(<reject.rule)
  sudo iptables -D OUTPUT  $reject
  sudo iptables -D FORWARD $reject
  echo "Restriction stopped."

elif [ "$action" == "start" ]; then
  reject=$(<reject.rule)
  sudo iptables -A OUTPUT  $reject
  sudo iptables -A FORWARD $reject
  echo "Restriction started."

elif [ "$action" == "reset" ]; then
  reset_ip_tables
  echo "Firewall reset."
fi
