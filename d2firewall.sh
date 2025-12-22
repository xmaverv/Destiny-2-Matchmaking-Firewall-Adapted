#!/bin/bash
# Destiny 2 Matchmaking Firewall
# Original credits: @BasRaayman @inchenzo
# Steam SDR IP adaptation – FIXED & RESTRICTIVE

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

  read -p "Platform (psn/xbox/steam_sdr): " platform
  platform=${platform:-steam_sdr}

  read -p "Network/netmask: " net
  net=${net:-$DEFAULT_NET}

  echo "$platform" > /tmp/data.txt
  echo "$net" >> /tmp/data.txt
  echo "n" >> /tmp/data.txt

  ids=()

  echo -e "${BLUE}Start matchmaking now.${NC}"
  echo -e "${RED}Press any key to stop sniffing.${NC}"
  sleep 1

  if [ "$platform" == "psn" ]; then
    ngrep -q -W byline -d $INTERFACE "psn-4" udp \
    | grep --line-buffered -oP 'psn-4[0]{8}\K[A-F0-9]{7}' \
    | tee -a /tmp/data.txt &

  elif [ "$platform" == "xbox" ]; then
    ngrep -q -W byline -d $INTERFACE "xboxpwid:" udp \
    | grep --line-buffered -oP 'xboxpwid:[A-F0-9]{24}\K[A-F0-9]{8}' \
    | tee -a /tmp/data.txt &

  elif [ "$platform" == "steam_sdr" ]; then
    ngrep -q -W byline -d $INTERFACE udp portrange 27020-27050 \
    | grep --line-buffered -oP '(?<=IP )([0-9]{1,3}\.){3}[0-9]{1,3}' \
    | grep -v "$(ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')" \
    | sort -u | tee -a /tmp/data.txt &
  fi

  while true; do read -t 1 -n 1 && break; done
  pkill -15 ngrep

  awk '!a[$0]++' /tmp/data.txt > /tmp/t && mv /tmp/t /tmp/data.txt

  snum=$(tail -n +4 /tmp/data.txt | wc -l)
  awk "NR==4{print $snum}1" /tmp/data.txt > /tmp/t && mv /tmp/t /tmp/data.txt

  tmp_ids=$(tail -n +5 /tmp/data.txt)
  c=1
  while read -r line; do
    ids+=( "system$c;$line" )
    ((c++))
  done <<< "$tmp_ids"

  mv /tmp/data.txt ./data.txt

  # ==========================
  # MATCHMAKING RESTRICTION
  # ==========================

  if [ "$platform" == "steam_sdr" ]; then

    # ALLOW whitelisted relays
    for i in "${ids[@]}"; do
      IFS=';' read -r _ ip <<< "$i"
      sudo iptables -I FORWARD -s "$ip" -p udp --dport 27020:27050 -j ACCEPT
      sudo iptables -I FORWARD -d "$ip" -p udp --sport 27020:27050 -j ACCEPT
    done

    # DEFAULT DENY
    echo "-p udp --dport 27020:27050 -j REJECT" > reject.rule
    sudo iptables -A FORWARD -p udp --dport 27020:27050 -j REJECT
  fi

  iptables-save > /etc/iptables/rules.v4

  echo -e "${GREEN}Matchmaking restriction ACTIVE.${NC}"
}

if [ "$action" == "setup" ]; then
  install_dependencies
  setup

elif [ "$action" == "stop" ]; then
  reject=$(<reject.rule)
  sudo iptables -D FORWARD $reject
  echo "Restriction stopped."

elif [ "$action" == "start" ]; then
  reject=$(<reject.rule)
  sudo iptables -A FORWARD $reject
  echo "Restriction started."

elif [ "$action" == "reset" ]; then
  reset_ip_tables
  echo "Firewall reset."
fi
