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
  if ! [[ $platform =~ ^(psn|xbox|steam)$ ]]; then
    yn="n"
  fi
  echo "n" >> /tmp/data.txt

  if [ "$yn" == "y" ]; then

    echo -e "${RED}Press any key to stop sniffing. DO NOT CTRL C${NC}"
    sleep 1
    if [ $platform == "psn" ]; then
      ngrep -l -q -W byline -d $INTERFACE "psn-4" udp | grep --line-buffered -o -P 'psn-4[0]{8}\K[A-F0-9]{7}' | tee -a /tmp/data.txt &
    elif [ $platform == "xbox" ]; then
      ngrep -l -q -W byline -d $INTERFACE "xboxpwid:" udp | grep --line-buffered -o -P 'xboxpwid:[A-F0-9]{24}\K[A-F0-9]{8}' | tee -a /tmp/data.txt &
    elif [ $platform == "steam" ]; then
      ngrep -l -q -W byline -d $INTERFACE "steamid:" udp | grep --line-buffered -o -P 'steamid:[0-9]{7}\K[0-9]{10}' | tee -a /tmp/data.txt &
    fi

    while [ true ] ; do
      read -t 1 -n 1
      if [ $? = 0 ] ; then
        break
      fi
    done
    pkill -15 ngrep

    awk '!a[$0]++' /tmp/data.txt > /tmp/temp.txt && mv /tmp/temp.txt /tmp/data.txt
    snum=$(tail -n +4 /tmp/data.txt | wc -l)
    awk "NR==4{print $snum}1" /tmp/data.txt > /tmp/temp.txt && mv /tmp/temp.txt /tmp/data.txt

    tmp_ids=$(tail -n +5 /tmp/data.txt)
    c=1
    while IFS= read -r line; do 
      idf="system$c"
      ids+=( "$idf;$line" )
      ((c++))
    done <<< "$tmp_ids"

  else
    read -p "How many accounts are you using for this? " snum
    if [ $snum -lt 1 ]; then exit 1; fi
    echo $snum >> /tmp/data.txt
    for ((i=0;i<snum;i++)); do 
      num=$((i+1))
      idf="system$num"
      read -p "Enter the sniffed ID for Account $num: " sid
      sid=$(echo "$sid" | xargs)
      echo $sid >> /tmp/data.txt
      ids+=( "$idf;$sid" )
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
    if [ $INDEX -gt $offset ]; then
      inet=$net
    else
      inet="0.0.0.0/0"
    fi

    IFS=';' read -r -a id <<< "$elem"
    sudo iptables -N "${id[0]}"
    sudo iptables -I FORWARD -s $inet -p udp -m string --string "${id[1]}" --algo bm -j "${id[0]}"

    # ADD: support full PSN ID by also matching last 7 chars
    if [[ ${#id[1]} -gt 7 ]]; then
      short_id="${id[1]: -7}"
      sudo iptables -I FORWARD -s $inet -p udp -m string --string "$short_id" --algo bm -j "${id[0]}"
    fi

    ((INDEX++))
  done
  
  INDEX1=1
  for i in "${ids[@]}"; do
    IFS=';' read -r -a id <<< "$i"
    INDEX2=1
    for j in "${ids[@]}"; do
      if [ "$i" != "$j" ]; then
        if [[ $INDEX1 -eq 1 && $INDEX2 -eq 2 ]]; then
          inet=$net
        elif [[ $INDEX1 -eq 2 && $INDEX2 -eq 1 ]]; then
          inet=$net
        elif [[ $INDEX1 -gt 2 && $INDEX2 -lt 3 ]]; then
          inet=$net
        else
          inet="0.0.0.0/0"
        fi
        IFS=';' read -r -a idx <<< "$j"
        sudo iptables -A "${id[0]}" -s $inet -p udp -m string --string "${idx[1]}" --algo bm -j ACCEPT

        # ADD: support full PSN ID
        if [[ ${#idx[1]} -gt 7 ]]; then
          short_id="${idx[1]: -7}"
          sudo iptables -A "${id[0]}" -s $inet -p udp -m string --string "$short_id" --algo bm -j ACCEPT
        fi
      fi
      ((INDEX2++))
    done
    ((INDEX1++))
  done

  iptables-save > /etc/iptables/rules.v4
  echo "Setup is complete and matchmaking firewall is now active."
}

if [ "$action" == "setup" ]; then
  if ! command -v ngrep &> /dev/null; then
    install_dependencies
  fi
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
