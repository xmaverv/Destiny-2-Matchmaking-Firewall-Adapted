#!/bin/bash
# credits to @BasRaayman and @inchenzo
# modified to ONLY accept LONG PSN IDs (400000000XXXXXXX)

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
       exit 1
  esac
done

#######################################
# NEW: PSN short -> long ID converter #
#######################################
to_long_psn_id () {
  local short_id="$1"

  if [[ ! "$short_id" =~ ^[A-F0-9]{7}$ ]]; then
    echo ""
    return
  fi

  echo "400000000$short_id"
}

reset_ip_tables () {
  sudo service iptables restart

  sudo iptables -P INPUT ACCEPT
  sudo iptables -P FORWARD ACCEPT
  sudo iptables -P OUTPUT ACCEPT

  sudo iptables -F
  sudo iptables -X

  if ip a | grep -q "tun0"; then
    if ! sudo iptables-save | grep -q "POSTROUTING -s 10.8.0.0/24"; then
      sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
    fi
    sudo iptables -A INPUT -p udp --dport 1194 -j ACCEPT
    sudo iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -A FORWARD -s 10.8.0.0/24 -j ACCEPT
  fi
}

get_platform_match_str () {
  local val="psn-4"
  if [ "$1" == "psn" ]; then
    val="psn-4"
  elif [ "$1" == "xbox" ]; then
    val="xboxpwid:"
  elif [ "$1" == "steam" ]; then
    val="steamid:"
  fi
  echo $val
}

install_dependencies () {
  sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null
  sudo ufw disable > /dev/null

  if ip a | grep -q "tun0"; then
    yn="n"
  else 
    echo -e -n "${GREEN}Would you like to install OpenVPN?${NC} y/n: "
    read yn
    yn=${yn:-"y"}
  fi

  echo -e "${RED}Installing dependencies...${NC}"
  sudo apt-get update > /dev/null
  
  if [ "$yn" == "y" ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q install iptables iptables-persistent ngrep nginx > /dev/null
    sudo wget -q https://git.io/vpn -O openvpn-ubuntu-install.sh
    sudo chmod +x ./openvpn-ubuntu-install.sh
    (APPROVE_INSTALL=y APPROVE_IP=y IPV6_SUPPORT=n PORT_CHOICE=1 PROTOCOL_CHOICE=1 DNS=1 COMPRESSION_ENABLED=n CUSTOMIZE_ENC=n CLIENT=client PASS=1 ./openvpn-ubuntu-install.sh) &
    wait
  else
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q install iptables iptables-persistent ngrep > /dev/null
  fi
}

setup () {
  echo "Setting up firewall rules."
  reset_ip_tables

  read -p "Enter your platform xbox, psn, steam: " platform
  platform=$(echo "$platform" | xargs)
  platform=${platform:-"psn"}

  reject_str=$(get_platform_match_str $platform)
  echo $platform > /tmp/data.txt

  read -p "Enter your network/netmask: " net
  net=$(echo "$net" | xargs)
  net=${net:-$DEFAULT_NET}
  echo $net >> /tmp/data.txt

  ids=()
  read -p "Would you like to sniff the ID automatically?(psn/xbox/steam only) y/n: " yn
  yn=${yn:-"y"}
  echo "n" >> /tmp/data.txt

  if [ "$yn" == "y" ] && [ "$platform" == "psn" ]; then
    echo -e "${RED}Press any key to stop sniffing. DO NOT CTRL C${NC}"
    sleep 1

    ngrep -l -q -W byline -d $INTERFACE "psn-4" udp | \
    grep --line-buffered -o -P 'psn-4[0]{8}\K[A-F0-9]{7}' | \
    while read sid; do
      long_id=$(to_long_psn_id "$sid")
      [ -n "$long_id" ] && echo "$long_id"
    done | tee -a /tmp/data.txt &

    while true; do
      read -t 1 -n 1 && break
    done
    pkill -15 ngrep
  else
    read -p "How many accounts are you using for this? " snum
    echo $snum >> /tmp/data.txt

    for ((i=1;i<=snum;i++)); do
      read -p "Enter the LONG PSN ID for Account $i: " sid
      sid=$(echo "$sid" | xargs | tr 'a-f' 'A-F')

      if [[ ! "$sid" =~ ^400000000[A-F0-9]{7}$ ]]; then
        echo "❌ Invalid PSN ID format."
        exit 1
      fi

      echo "$sid" >> /tmp/data.txt
      ids+=( "system$i;$sid" )
    done
  fi

  mv /tmp/data.txt ./data.txt

  echo "-m string --string $reject_str --algo bm -j REJECT" > reject.rule
  sudo iptables -I FORWARD -m string --string $reject_str --algo bm -j REJECT

  n=${#ids[*]}
  INDEX=1
  for (( i=n-1; i>=0; i-- )); do
    elem=${ids[i]}
    inet=$net
    IFS=';' read -r -a id <<< "$elem"
    sudo iptables -N "${id[0]}"
    sudo iptables -I FORWARD -s $inet -p udp -m string --string "${id[1]}" --algo bm -j "${id[0]}"
  done

  for i in "${ids[@]}"; do
    IFS=';' read -r -a id <<< "$i"
    for j in "${ids[@]}"; do
      if [ "$i" != "$j" ]; then
        IFS=';' read -r -a idx <<< "$j"
        sudo iptables -A "${id[0]}" -p udp -m string --string "${idx[1]}" --algo bm -j ACCEPT
      fi
    done
  done

  iptables-save > /etc/iptables/rules.v4
  echo "Setup complete. Firewall active."
}

if [ "$action" == "setup" ]; then
  setup
elif [ "$action" == "stop" ]; then
  reject=$(<reject.rule)
  sudo iptables -D FORWARD $reject
elif [ "$action" == "start" ]; then
  reject=$(<reject.rule)
  sudo iptables -I FORWARD $reject
elif [ "$action" == "add" ]; then
  read -p "Enter the LONG PSN ID: " id
  id=$(echo "$id" | xargs | tr 'a-f' 'A-F')

  if [[ ! "$id" =~ ^400000000[A-F0-9]{7}$ ]]; then
    echo "❌ Invalid PSN ID."
    exit 1
  fi

  echo "$id" >> data.txt
elif [ "$action" == "list" ]; then
  tail -n +5 data.txt | cat -n
elif [ "$action" == "reset" ]; then
  reset_ip_tables
fi
