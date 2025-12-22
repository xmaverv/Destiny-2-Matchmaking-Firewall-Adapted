#!/bin/bash
# Modified for Steam SDR (IP based)
# Original credits: @BasRaayman and @inchenzo
# SDR adaptation: IP-based firewall

INTERFACE="tun0"
DEFAULT_NET="10.8.0.0/24"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

while getopts "a:" opt; do
  case $opt in
    a) action=$OPTARG ;;
    *) echo 'Not a valid command' >&2
       exit 1 ;;
  esac
done

reset_ip_tables () {
  sudo service iptables restart

  sudo iptables -P INPUT ACCEPT
  sudo iptables -P FORWARD ACCEPT
  sudo iptables -P OUTPUT ACCEPT

  sudo iptables -F
  sudo iptables -X

  if ip a | grep -q "tun0"; then
    sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
    sudo iptables -A INPUT -p udp --dport 1194 -j ACCEPT
    sudo iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -A FORWARD -s 10.8.0.0/24 -j ACCEPT
  fi
}

install_dependencies () {
  sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
  sudo ufw disable > /dev/null

  sudo apt-get update > /dev/null
  sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q install \
    iptables iptables-persistent ngrep > /dev/null
}

setup () {
  echo "Setting up firewall rules."
  reset_ip_tables

  read -p "Enter your platform (psn/xbox/steam_sdr): " platform
  platform=$(echo "$platform" | xargs)
  platform=${platform:-"steam_sdr"}

  read -p "Enter your network/netmask: " net
  net=$(echo "$net" | xargs)
  net=${net:-$DEFAULT_NET}

  echo "$platform" > /tmp/data.txt
  echo "$net" >> /tmp/data.txt
  echo "n" >> /tmp/data.txt

  ids=()

  read -p "Auto sniff IP/ID? y/n: " yn
  yn=${yn:-"y"}

  if [ "$yn" == "y" ]; then
    echo -e "${RED}Press any key to stop sniffing. DO NOT CTRL+C${NC}"
    sleep 1

    if [ "$platform" == "psn" ]; then
      ngrep -l -q -W byline -d $INTERFACE "psn-4" udp \
      | grep --line-buffered -o -P 'psn-4[0]{8}\K[A-F0-9]{7}' \
      | tee -a /tmp/data.txt &

    elif [ "$platform" == "xbox" ]; then
      ngrep -l -q -W byline -d $INTERFACE "xboxpwid:" udp \
      | grep --line-buffered -o -P 'xboxpwid:[A-F0-9]{24}\K[A-F0-9]{8}' \
      | tee -a /tmp/data.txt &

    elif [ "$platform" == "steam_sdr" ]; then
      ngrep -q -W byline -d $INTERFACE udp portrange 27020-27050 \
      | grep --line-buffered -oP '(?<=IP )([0-9]{1,3}\.){3}[0-9]{1,3}' \
      | grep -v "$(ip -4 addr show $INTERFACE | grep -oP '(?<=inet\s)\d+(\.\d+){3}')" \
      | sort -u \
      | tee -a /tmp/data.txt &
    fi

    while true; do
      read -t 1 -n 1 && break
    done
    pkill -15 ngrep

    awk '!a[$0]++' /tmp/data.txt > /tmp/temp.txt && mv /tmp/temp.txt /tmp/data.txt

    snum=$(tail -n +4 /tmp/data.txt | wc -l)
    awk "NR==4{print $snum}1" /tmp/data.txt > /tmp/temp.txt && mv /tmp/temp.txt /tmp/data.txt

    tmp_ids=$(tail -n +5 /tmp/data.txt)
    c=1
    while IFS= read -r line; do
      ids+=( "system$c;$line" )
      ((c++))
    done <<< "$tmp_ids"

  else
    read -p "How many IPs/IDs? " snum
    echo $snum >> /tmp/data.txt
    for ((i=1;i<=snum;i++)); do
      read -p "Enter value $i: " val
      echo "$val" >> /tmp/data.txt
      ids+=( "system$i;$val" )
    done
  fi

  mv /tmp/data.txt ./data.txt

  # === BLOCK ALL STEAM SDR BY DEFAULT ===
  if [ "$platform" == "steam_sdr" ]; then
    echo "-p udp --dport 27020:27050 -j REJECT" > reject.rule
    sudo iptables -I FORWARD -p udp --dport 27020:27050 -j REJECT
  fi

  n=${#ids[@]}
  INDEX=1
  for ((i=n-1;i>=0;i--)); do
    elem=${ids[i]}
    IFS=';' read -r cname ip <<< "$elem"
    sudo iptables -N "$cname"
    sudo iptables -I FORWARD -s "$ip" -p udp -j "$cname"
    ((INDEX++))
  done

  for i in "${ids[@]}"; do
    IFS=';' read -r cname ip <<< "$i"
    for j in "${ids[@]}"; do
      if [ "$i" != "$j" ]; then
        IFS=';' read -r _ ip2 <<< "$j"
        sudo iptables -A "$cname" -s "$ip2" -p udp -j ACCEPT
      fi
    done
  done

  iptables-save > /etc/iptables/rules.v4
  echo -e "${GREEN}Steam SDR matchmaking firewall active.${NC}"
}

if [ "$action" == "setup" ]; then
  install_dependencies
  setup

elif [ "$action" == "stop" ]; then
  echo "Stopping matchmaking restriction."
  reject=$(<reject.rule)
  sudo iptables -D FORWARD $reject

elif [ "$action" == "start" ]; then
  reject=$(<reject.rule)
  sudo iptables -I FORWARD $reject

elif [ "$action" == "list" ]; then
  tail -n +5 data.txt | cat -n

elif [ "$action" == "reset" ]; then
  reset_ip_tables
fi
