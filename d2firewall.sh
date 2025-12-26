#!/bin/bash
# credits to @BasRaayman and @inchenzo
# unified platform version (minimal change)

INTERFACE="tun0"
DEFAULT_NET="10.8.0.0/24"

# unified match string (EDIT HERE IF NEEDED)
UNIFIED_MATCH="D2MATCH"

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

  # allow openvpn (PRESERVED)
  if ip a | grep -q "tun0"; then
    if ! sudo iptables-save | grep -q "POSTROUTING -s 10.8.0.0/24"; then
      sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
    fi
    sudo iptables -A INPUT -p udp --dport 1194 -j ACCEPT
    sudo iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
    sudo iptables -A FORWARD -s 10.8.0.0/24 -j ACCEPT
  fi
}

# platform abstraction kept for compatibility
get_platform_match_str () {
  echo "$UNIFIED_MATCH"
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

  echo -e "${RED}Installing dependencies. Please wait...${NC}"
  sudo apt-get update > /dev/null
  
  if [ "$yn" == "y" ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q install iptables iptables-persistent ngrep nginx > /dev/null
    sudo wget -q https://git.io/vpn -O openvpn-ubuntu-install.sh
    sudo chmod +x ./openvpn-ubuntu-install.sh
    (APPROVE_INSTALL=y APPROVE_IP=y IPV6_SUPPORT=n PORT_CHOICE=1 PROTOCOL_CHOICE=1 DNS=1 COMPRESSION_ENABLED=n CUSTOMIZE_ENC=n CLIENT=client PASS=1 ./openvpn-ubuntu-install.sh) &
    wait
    sudo cp /root/client.ovpn /var/www/html/client.ovpn
  else
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q install iptables iptables-persistent ngrep > /dev/null
  fi
}

setup () {
  reset_ip_tables

  # kept for compatibility
  read -p "Enter your platform xbox, psn, steam: " platform
  platform=$(echo "$platform" | xargs)
  platform=${platform:-"psn"}

  reject_str=$(get_platform_match_str "$platform")
  echo "$platform" > /tmp/data.txt

  read -p "Enter your network/netmask: " net
  net=$(echo "$net" | xargs)
  net=${net:-$DEFAULT_NET}
  echo "$net" >> /tmp/data.txt

  ids=()
  read -p "Would you like to sniff the ID automatically? y/n: " yn
  yn=${yn:-"y"}
  echo "n" >> /tmp/data.txt

  if [ "$yn" == "y" ]; then
    echo -e "${RED}Press any key to stop sniffing. DO NOT CTRL+C${NC}"
    sleep 1

    ngrep -l -q -W byline -d $INTERFACE "$UNIFIED_MATCH" udp | \
      tee -a /tmp/data.txt &

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
      idf="system$c"
      ids+=( "$idf;$line" )
      ((c++))
    done <<< "$tmp_ids"
  else
    read -p "How many accounts are you using? " snum
    echo "$snum" >> /tmp/data.txt
    for ((i=1;i<=snum;i++)); do
      idf="system$i"
      read -p "Enter the sniffed ID for Account $i: " sid
      echo "$sid" >> /tmp/data.txt
      ids+=( "$idf;$sid" )
    done
  fi

  mv /tmp/data.txt ./data.txt

  echo "-m string --string $reject_str --algo bm -j REJECT" > reject.rule
  sudo iptables -I FORWARD -m string --string "$reject_str" --algo bm -j REJECT

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

  iptables-save > /etc/iptables/rules.v4
  echo "Setup is complete and matchmaking firewall is now active."
}

# command handling (UNCHANGED)
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
elif [ "$action" == "add" ]; then
  read -p "Enter the sniffed ID: " id
  echo "$id" >> data.txt
  bash d2firewall.sh -a setup < data.txt
elif [ "$action" == "remove" ]; then
  tail -n +5 data.txt | cat -n
elif [ "$action" == "sniff" ]; then
  bash d2firewall.sh -a stop
  echo -e "${RED}Press any key to stop sniffing.${NC}"
  ngrep -l -q -W byline -d $INTERFACE "$UNIFIED_MATCH" udp | tee -a data.txt &
  read -n 1
  pkill -15 ngrep
  awk '!a[$0]++' data.txt > /tmp/data.txt && mv /tmp/data.txt ./data.txt
  bash d2firewall.sh -a setup < data.txt
elif [ "$action" == "list" ]; then
  tail -n +5 data.txt | cat -n
elif [ "$action" == "load" ]; then
  if [ -f ./data.txt ]; then
    bash d2firewall.sh -a setup < ./data.txt
  else
    iptables-restore < /etc/iptables/rules.v4
  fi
elif [ "$action" == "reset" ]; then
  reset_ip_tables
fi
