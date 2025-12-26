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

  sudo apt-get update > /dev/null
  
  if [ "$yn" == "y" ]; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q install iptables iptables-persistent ngrep nginx > /dev/null
    sudo wget -q https://git.io/vpn -O openvpn-ubuntu-install.sh
    sudo chmod +x ./openvpn-ubuntu-install.sh
    (APPROVE_INSTALL=y APPROVE_IP=y IPV6_SUPPORT=n PORT_CHOICE=1 PROTOCOL_CHOICE=1 DNS=1 COMPRESSION_ENABLED=n CUSTOMIZE_ENC=n CLIENT=client PASS=1 ./openvpn-ubuntu-install.sh) &
    wait;
    sudo cp /root/client.ovpn /var/www/html/client.ovpn
  else
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q install iptables iptables-persistent ngrep > /dev/null
  fi
}

setup () {

  # NON-INTERACTIVE MODE (called from add/remove/sniff/load)
  if [ ! -t 0 ]; then
    read platform
    read net
    read sniff_flag
    read snum

    ids=()
    for ((i=0;i<snum;i++)); do
      read sid
      ids+=( "system$((i+1));$sid" )
    done
  else
    reset_ip_tables

    read -p "Enter your platform xbox, psn, steam: " platform
    platform=$(echo "$platform" | xargs)
    platform=${platform:-"psn"}

    read -p "Enter your network/netmask: " net
    net=$(echo "$net" | xargs)
    net=${net:-$DEFAULT_NET}

    ids=()
    read -p "Would you like to sniff the ID automatically?(psn/xbox/steam only) y/n: " yn
    yn=${yn:-"y"}

    echo $platform > /tmp/data.txt
    echo $net >> /tmp/data.txt
    echo "n" >> /tmp/data.txt

    if [ "$yn" == "y" ]; then
      echo -e "${RED}Press any key to stop sniffing. DO NOT CTRL C${NC}"
      sleep 1
      ngrep -l -q -W byline -d $INTERFACE "psn-4" udp | \
        grep --line-buffered -o -P 'psn-4[0]{8}\K[A-F0-9]{7}' | tee -a /tmp/data.txt &

      while true; do
        read -t 1 -n 1 && break
      done
      pkill -15 ngrep

      awk '!a[$0]++' /tmp/data.txt > /tmp/tmp && mv /tmp/tmp /tmp/data.txt
      snum=$(tail -n +4 /tmp/data.txt | wc -l)
      awk "NR==4{print $snum}1" /tmp/data.txt > /tmp/tmp && mv /tmp/tmp /tmp/data.txt

      c=1
      tail -n +5 /tmp/data.txt | while read line; do
        ids+=( "system$c;$line" )
        ((c++))
      done
    else
      read -p "How many accounts are you using for this? " snum
      echo $snum >> /tmp/data.txt
      for ((i=0;i<snum;i++)); do
        read -p "Enter the sniffed ID for Account $((i+1)): " sid
        echo $sid >> /tmp/data.txt
        ids+=( "system$((i+1));$sid" )
      done
    fi

    mv /tmp/data.txt ./data.txt
  fi

  reset_ip_tables
  reject_str=$(get_platform_match_str $platform)
  echo "-m string --string $reject_str --algo bm -j REJECT" > reject.rule
  sudo iptables -I FORWARD -m string --string $reject_str --algo bm -j REJECT

  n=${#ids[@]}
  INDEX=1
  for ((i=n-1;i>=0;i--)); do
    IFS=';' read -r name sid <<< "${ids[i]}"
    inet=$net

    sudo iptables -N "$name"
    sudo iptables -I FORWARD -s $inet -p udp -m string --string "$sid" --algo bm -j "$name"

    # SUPPORT FULL ID
    if [[ ${#sid} -gt 7 ]]; then
      sudo iptables -I FORWARD -s $inet -p udp -m string --string "${sid: -7}" --algo bm -j "$name"
    fi
    ((INDEX++))
  done

  for i in "${ids[@]}"; do
    IFS=';' read -r name sid <<< "$i"
    for j in "${ids[@]}"; do
      if [ "$i" != "$j" ]; then
        IFS=';' read -r _ jsid <<< "$j"
        sudo iptables -A "$name" -s $net -p udp -m string --string "$jsid" --algo bm -j ACCEPT
        if [[ ${#jsid} -gt 7 ]]; then
          sudo iptables -A "$name" -s $net -p udp -m string --string "${jsid: -7}" --algo bm -j ACCEPT
        fi
      fi
    done
  done

  iptables-save > /etc/iptables/rules.v4
  echo "Setup complete."
}

case "$action" in
  setup)
    setup
    ;;
  add)
    read -p "Enter the sniffed ID: " id
    echo $id >> data.txt
    n=$(sed -n '4p' data.txt)
    sed -i "4c$((n+1))" data.txt
    bash d2firewall.sh -a setup < data.txt
    ;;
  list)
    tail -n +5 data.txt | cat -n
    ;;
  remove)
    list=$(tail -n +5 data.txt | cat -n)
    echo "$list"
    read -p "How many IDs to remove from the end? " num
    head -n -"$num" data.txt > /tmp/data.txt && mv /tmp/data.txt data.txt
    n=$(sed -n '4p' data.txt)
    sed -i "4c$((n-num))" data.txt
    bash d2firewall.sh -a setup < data.txt
    ;;
  sniff)
    bash d2firewall.sh -a setup
    ;;
  load)
    bash d2firewall.sh -a setup < data.txt
    ;;
  stop)
    reject=$(<reject.rule)
    sudo iptables -D FORWARD $reject
    ;;
  start)
    reject=$(<reject.rule)
    sudo iptables -I FORWARD $reject
    ;;
esac
