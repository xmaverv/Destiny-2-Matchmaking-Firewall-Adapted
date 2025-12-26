#!/bin/bash
# credits to @BasRaayman and @inchenzo
# unified platform version

INTERFACE="tun0"
DEFAULT_NET="10.8.0.0/24"
MATCH_STRING="D2MATCH"

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
    sudo cp /root/client.ovpn /var/www/html/client.ovpn
  else
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y -q install iptables iptables-persistent ngrep > /dev/null
  fi
}

setup () {
  reset_ip_tables

  read -p "Enter your network/netmask: " net
  net=${net:-$DEFAULT_NET}

  echo "$MATCH_STRING" > /tmp/data.txt
  echo "$net" >> /tmp/data.txt

  read -p "How many accounts are you using? " snum
  echo "$snum" >> /tmp/data.txt

  ids=()
  for ((i=1;i<=snum;i++)); do
    read -p "Enter sniffed ID for account $i: " sid
    echo "$sid" >> /tmp/data.txt
    ids+=( "system$i;$sid" )
  done

  mv /tmp/data.txt ./data.txt

  echo "-m string --string $MATCH_STRING --algo bm -j REJECT" > reject.rule
  sudo iptables -I FORWARD -m string --string $MATCH_STRING --algo bm -j REJECT

  for elem in "${ids[@]}"; do
    IFS=';' read -r name id <<< "$elem"
    sudo iptables -N "$name"
    sudo iptables -I FORWARD -s "$net" -p udp -m string --string "$id" --algo bm -j "$name"
  done

  for i in "${ids[@]}"; do
    IFS=';' read -r name id <<< "$i"
    for j in "${ids[@]}"; do
      IFS=';' read -r oname oid <<< "$j"
      if [ "$id" != "$oid" ]; then
        sudo iptables -A "$name" -p udp -m string --string "$oid" --algo bm -j ACCEPT
      fi
    done
  done

  iptables-save > /etc/iptables/rules.v4
  echo "Setup complete. Firewall active."
}

case "$action" in
  setup) install_dependencies; setup ;;
  start) reject=$(<reject.rule); sudo iptables -I FORWARD $reject ;;
  stop) reject=$(<reject.rule); sudo iptables -D FORWARD $reject ;;
  list) tail -n +4 data.txt | cat -n ;;
  sniff)
    echo -e "${RED}Press any key to stop sniffing.${NC}"
    ngrep -d $INTERFACE "$MATCH_STRING" udp | tee -a data.txt &
    read -n 1
    pkill -15 ngrep
    ;;
  load) bash d2firewall.sh -a setup < data.txt ;;
  reset) reset_ip_tables ;;
  update)
    wget -q https://raw.githubusercontent.com/xmaver/Destiny-2-Matchmaking-Firewall/main/d2firewall.sh -O ./d2firewall.sh
    chmod +x ./d2firewall.sh
    ;;
esac
