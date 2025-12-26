#!/bin/bash
#credits to @BasRaayman and @inchenzo

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
    sudo iptables -A INPUT -p udp -m udp --dport 1194 -j ACCEPT
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

  echo -e "${RED}Installing dependencies. Please wait while it finishes...${NC}"
  sudo apt-get update > /dev/null
  
  if [ "$yn" == "y" ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q install iptables iptables-persistent ngrep nginx > /dev/null
    sudo wget -q https://git.io/vpn -O openvpn-ubuntu-install.sh
    sudo chmod +x ./openvpn-ubuntu-install.sh
    (APPROVE_INSTALL=y APPROVE_IP=y IPV6_SUPPORT=n PORT_CHOICE=1 PROTOCOL_CHOICE=1 DNS=1 COMPRESSION_ENABLED=n CUSTOMIZE_ENC=n CLIENT=client PASS=1 ./openvpn-ubuntu-install.sh) &
    wait;
    sudo cp /root/client.ovpn /var/www/html/client.ovpn
    ip=$(dig +short myip.opendns.com @resolver1.opendns.com)
    echo -e "${GREEN}You can download the openvpn config from ${BLUE}http://$ip/client.ovpn${NC}"
  else
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q install iptables iptables-persistent ngrep > /dev/null
  fi
}

setup () {
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

  if [ "$yn" != "y" ]; then
    read -p "How many accounts are you using for this? " snum
    echo $snum >> /tmp/data.txt

    for ((i=0;i<snum;i++)); do
      num=$((i+1))
      idf="system$num"
      read -p "Enter the sniffed ID for Account $num: " sid
      sid=$(echo "$sid" | xargs)

      if [[ ${#sid} -gt 7 ]]; then
        sid_short="${sid: -7}"
      else
        sid_short="$sid"
      fi

      echo "$sid" >> /tmp/data.txt
      ids+=( "$idf;$sid;$sid_short" )
    done
  fi

  mv /tmp/data.txt ./data.txt

  echo "-m string --string $reject_str --algo bm -j REJECT" > reject.rule
  sudo iptables -I FORWARD -m string --string $reject_str --algo bm -j REJECT
  
  n=${#ids[*]}
  INDEX=1
  for (( i = n-1; i >= 0; i-- )); do
    elem=${ids[i]}
    offset=$((n - 2))
    if [ $INDEX -gt $offset ]; then inet=$net; else inet="0.0.0.0/0"; fi

    IFS=';' read -r -a id <<< "$elem"
    if [ ${#id[@]} -eq 2 ]; then id[2]="${id[1]}"; fi

    sudo iptables -N "${id[0]}"
    sudo iptables -I FORWARD -s $inet -p udp -m string --string "${id[1]}" --algo bm -j "${id[0]}"
    sudo iptables -I FORWARD -s $inet -p udp -m string --string "${id[2]}" --algo bm -j "${id[0]}"
    ((INDEX++))
  done

  INDEX1=1
  for i in "${ids[@]}"; do
    IFS=';' read -r -a id <<< "$i"
    if [ ${#id[@]} -eq 2 ]; then id[2]="${id[1]}"; fi

    INDEX2=1
    for j in "${ids[@]}"; do
      if [ "$i" != "$j" ]; then
        inet=$net
        IFS=';' read -r -a idx <<< "$j"
        if [ ${#idx[@]} -eq 2 ]; then idx[2]="${idx[1]}"; fi

        sudo iptables -A "${id[0]}" -s $inet -p udp -m string --string "${idx[1]}" --algo bm -j ACCEPT
        sudo iptables -A "${id[0]}" -s $inet -p udp -m string --string "${idx[2]}" --algo bm -j ACCEPT
      fi
      ((INDEX2++))
    done
    ((INDEX1++))
  done

  iptables-save > /etc/iptables/rules.v4
  echo "Setup is complete and matchmaking firewall is now active."
}

if [ "$action" == "setup" ]; then
  setup
elif [ "$action" == "stop" ]; then
  reject=$(<reject.rule)
  sudo iptables -D FORWARD $reject
elif [ "$action" == "start" ]; then
  if ! sudo iptables-save | grep -q "REJECT"; then
    pos=$(iptables -L FORWARD | grep "system" | wc -l)
    ((pos++))
    reject=$(<reject.rule)
    sudo iptables -I FORWARD $pos $reject
  fi
fi
