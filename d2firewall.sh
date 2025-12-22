#!/bin/bash
# Destiny 2 Matchmaking Firewall
# Original credits: @BasRaayman / @inchenzo
# Steam IP adaptation: updated

INTERFACE="tun0"
DEFAULT_NET="10.8.0.0/24"

# Steam Datagram Relay IP ranges (matchmaking)
STEAM_IP_RANGES=(
  "155.133.0.0/16"
  "162.254.192.0/18"
  "185.25.182.0/24"
)

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

while getopts "a:" opt; do
  case $opt in
    a) action=$OPTARG ;;
    *) echo 'Not a valid command' >&2; exit 1 ;;
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

get_platform_match_str () {
  local val=""
  if [ "$1" == "psn" ]; then
    val="psn-4"
  elif [ "$1" == "xbox" ]; then
    val="xboxpwid:"
  fi
  echo $val
}

install_dependencies () {
  sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
  sudo ufw disable > /dev/null
  sudo apt-get update > /dev/null
  sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q install iptables iptables-persistent ngrep > /dev/null
}

setup () {
  echo "Setting up firewall rules."
  reset_ip_tables

  read -p "Enter your platform xbox, psn, steam: " platform
  platform=$(echo "$platform" | xargs)
  platform=${platform:-"psn"}

  read -p "Enter your network/netmask: " net
  net=$(echo "$net" | xargs)
  net=${net:-$DEFAULT_NET}

  echo "$platform" > /tmp/data.txt
  echo "$net" >> /tmp/data.txt
  echo "n" >> /tmp/data.txt
  echo "0" >> /tmp/data.txt

  if [ "$platform" == "steam" ]; then
    echo "# Steam IP reject rules" > reject.rule
    for ip in "${STEAM_IP_RANGES[@]}"; do
      sudo iptables -I FORWARD -p udp -d $ip -j REJECT
      echo "-p udp -d $ip -j REJECT" >> reject.rule
    done
  else
    reject_str=$(get_platform_match_str $platform)
    echo "-m string --string $reject_str --algo bm -j REJECT" > reject.rule
    sudo iptables -I FORWARD -m string --string $reject_str --algo bm -j REJECT

    ids=()
    read -p "How many accounts are you using? " snum
    echo "$snum" >> /tmp/data.txt

    for ((i=1;i<=snum;i++)); do
      read -p "Enter the sniffed ID for Account $i: " sid
      sid=$(echo "$sid" | xargs)
      echo "$sid" >> /tmp/data.txt
      ids+=( "system$i;$sid" )
    done

    n=${#ids[*]}
    INDEX=1
    for (( i = n-1; i >= 0; i-- )); do
      elem=${ids[i]}
      offset=$((n - 2))
      if [ $INDEX -gt $offset ]; then
        inet=$net
      else
        inet="0.0.0.0/0"
      fi
      IFS=';' read -r -a id <<< "$elem"
      sudo iptables -N "${id[0]}"
      sudo iptables -I FORWARD -s $inet -p udp -m string --string "${id[1]}" --algo bm -j "${id[0]}"
      ((INDEX++))
    done

    INDEX1=1
    for i in "${ids[@]}"; do
      IFS=';' read -r -a id <<< "$i"
      INDEX2=1
      for j in "${ids[@]}"; do
        if [ "$i" != "$j" ]; then
          inet="0.0.0.0/0"
          IFS=';' read -r -a idx <<< "$j"
          sudo iptables -A "${id[0]}" -s $inet -p udp -m string --string "${idx[1]}" --algo bm -j ACCEPT
        fi
        ((INDEX2++))
      done
      ((INDEX1++))
    done
  fi

  mv /tmp/data.txt ./data.txt
  iptables-save > /etc/iptables/rules.v4
  echo -e "${GREEN}Setup complete. Matchmaking firewall active.${NC}"
}

if [ "$action" == "setup" ]; then
  if ! command -v ngrep &> /dev/null; then
    install_dependencies
  fi
  setup

elif [ "$action" == "stop" ]; then
  echo "Matchmaking is no longer being restricted."
  while read rule; do
    sudo iptables -D FORWARD $rule
  done < reject.rule

elif [ "$action" == "start" ]; then
  echo "Matchmaking is now being restricted."
  while read rule; do
    sudo iptables -I FORWARD $rule
  done < reject.rule

elif [ "$action" == "reset" ]; then
  echo "Erasing all firewall rules."
  reset_ip_tables
fi
