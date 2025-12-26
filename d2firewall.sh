#!/bin/bash
#credits to @BasRaayman and @inchenzo

INTERFACE="tun0"
DEFAULT_NET="10.8.0.0/24"
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'
OBS_WINDOW=30
SLEEP_BETWEEN=10

while getopts "a:" opt; do
  case $opt in
    a) action=$OPTARG ;;
    *) echo 'Not a valid command' >&2
       exit 1
  esac
done

reset_ip_tables () {
  sudo service iptables restart

  #reset iptables to default
  sudo iptables -P INPUT ACCEPT
  sudo iptables -P FORWARD ACCEPT
  sudo iptables -P OUTPUT ACCEPT

  sudo iptables -F
  sudo iptables -X

  #allow openvpn
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
add_cross_platform_id () {
  local platform="$1"
  local match_str=$(get_platform_match_str "$platform")

  read -p "Enter the sniffed $platform ID: " sid
  sid=$(echo "$sid" | xargs)

  if [ -z "$sid" ]; then
    echo "Invalid ID"
    exit 1
  fi

  echo "$sid" >> data.txt

  n=$(sed -n '4p' < data.txt)
  ((n++))
  sed -i "4c$n" data.txt

  sys="system$n"

  sudo iptables -N "$sys"

  tail -n +5 data.txt | head -n -1 | while read other; do
    sudo iptables -A "$sys" -p udp -m string --string "$other" --algo bm -j ACCEPT
    sudo iptables -A FORWARD -p udp -m string --string "$sid" --algo bm -j "$sys"
  done

  iptables-save > /etc/iptables/rules.v4

  echo "$platform ID added successfully."
}
auto_trials () {

  MY_IDS=($(tail -n +5 data.txt))

  contains_my_id () {
    local id="$1"
    for my in "${MY_IDS[@]}"; do
      [[ "$id" == "$my" ]] && return 0
    done
    return 1
  }

  echo -e "${BLUE}[AUTO] Fast matchmaking automation (2 or 3 IDs)${NC}"

  while true; do
    bash d2firewall.sh -a start
     # TEMPORARIAMENTE libera matchmaking (remove REJECT)
    if [ -f reject.rule ]; then
      reject=$(<reject.rule)
      sudo iptables -D FORWARD $reject 2>/dev/null
    fi

    FOUND_IDS=()
    FOUND_TIMES=()
    FIRST_ID_TIME=0
SUCCESS=0

    echo -e "${BLUE}[AUTO] Sniffing...${NC}"

    ngrep -l -q -W byline -d $INTERFACE "psn-" udp | \
    grep --line-buffered -o -P 'psn-4[0]{8}\K[A-F0-9]{7}' | \
    while read id; do
      ts=$(date +%s)

      # ID externa → reset imediato
      if ! contains_my_id "$id"; then
        echo -e "${RED}[AUTO] External ID detected: $id${NC}"
        pkill -15 ngrep
        bash d2firewall.sh -a reset
        sleep 1
        continue 2
      fi

      # adiciona se ainda não existir
      if [[ ! " ${FOUND_IDS[*]} " =~ " $id " ]]; then
        FOUND_IDS+=("$id")
        FOUND_TIMES+=("$ts")
        echo -e "${GREEN}[AUTO] Valid ID detected (${#FOUND_IDS[@]}): $id${NC}"
      fi

      # apenas 1 ID → aguarda até 2s pela segunda
if [ "${#FOUND_IDS[@]}" -eq 1 ]; then
  if [ $((ts - FIRST_ID_TIME)) -gt 2 ]; then
    echo -e "${RED}[AUTO] Only one ID after 2s. Resetting.${NC}"
    pkill -15 ngrep
    bash d2firewall.sh -a reset
    sleep 1
    continue 2
  fi
fi

      # 2 IDs → sucesso se <= 1s
      if [ "${#FOUND_IDS[@]}" -eq 2 ]; then
        dt=$(( FOUND_TIMES[1] - FOUND_TIMES[0] ))

        if [ "$dt" -le 2 ]; then
  echo -e "${GREEN}[AUTO] 2 valid IDs detected. Confirming...${NC}"
sleep 5
pkill -15 ngrep

# REINSERE REJECT NO LOCAL CORRETO (CRÍTICO)
if [ -f reject.rule ]; then
  reject=$(<reject.rule)
  sudo iptables -D FORWARD $reject 2>/dev/null

  pos=$(iptables -L FORWARD | grep "system" | wc -l)
  ((pos++))
  sudo iptables -I FORWARD $pos $reject
fi

exit 0
        else
          echo -e "${RED}[AUTO] 2 IDs too slow. Resetting.${NC}"
          pkill -15 ngrep
          bash d2firewall.sh -a reset
          sleep 1
          continue 2
        fi
      fi

      # 3 IDs → sucesso se <= 2s
      if [ "${#FOUND_IDS[@]}" -eq 3 ]; then
        dt=$(( FOUND_TIMES[2] - FOUND_TIMES[0] ))

        if [ "$dt" -le 3 ]; then
  echo -e "${GREEN}[AUTO] 3 valid IDs detected. Confirming...${NC}"
sleep 5
pkill -15 ngrep

# REINSERE REJECT NO LOCAL CORRETO (CRÍTICO)
if [ -f reject.rule ]; then
  reject=$(<reject.rule)
  sudo iptables -D FORWARD $reject 2>/dev/null

  pos=$(iptables -L FORWARD | grep "system" | wc -l)
  ((pos++))
  sudo iptables -I FORWARD $pos $reject
fi

exit 0
        else
          echo -e "${RED}[AUTO] 3 IDs too slow. Resetting.${NC}"
          pkill -15 ngrep
          bash d2firewall.sh -a reset
          sleep 1
          continue 2
        fi
      fi
    done
  done
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
    echo -e "${RED}Installing OpenVPN. Please wait while it finishes...${NC}"
    sudo wget -q https://git.io/vpn -O openvpn-ubuntu-install.sh
    sudo chmod +x ./openvpn-ubuntu-install.sh
    (APPROVE_INSTALL=y APPROVE_IP=y IPV6_SUPPORT=n PORT_CHOICE=1 PROTOCOL_CHOICE=1 DNS=1 COMPRESSION_ENABLED=n CUSTOMIZE_ENC=n CLIENT=client PASS=1 ./openvpn-ubuntu-install.sh) &
    wait;
    sudo cp /root/client.ovpn /var/www/html/client.ovpn
    ip=$(dig +short myip.opendns.com @resolver1.opendns.com)
    echo -e "${GREEN}You can download the openvpn config from ${BLUE}http://$ip/client.ovpn"
    echo -e "${GREEN}If you are unable to access this file, you may need to allow/open the http port 80 with your vps provider."
    echo -e "Otherwise you can always run the command cat /root/client.ovpn and copy/paste ALL of its contents in a file on your PC."
    echo -e "It will be deleted automatically in 15 minutes for security reasons."
    echo -e "Be sure to import this config to your router and connect your consoles before proceeding any further.${NC}"
    nohup bash -c 'sleep 900 && sudo service nginx stop && sudo apt remove nginx -y && sudo rm /var/www/html/client.ovpn' &>/dev/null &
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
  if ! [[ $platform =~ ^(psn|xbox|steam)$ ]]; then
    yn="n"
  fi
  echo "n" >> /tmp/data.txt

  #auto sniffer
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

    #remove duplicates
    awk '!a[$0]++' /tmp/data.txt > /tmp/temp.txt && mv /tmp/temp.txt /tmp/data.txt
    #get number of accounts
    snum=$(tail -n +4 /tmp/data.txt | wc -l)
    awk "NR==4{print $snum}1" /tmp/data.txt > /tmp/temp.txt && mv /tmp/temp.txt /tmp/data.txt
    #get ids and add to ads array with identifier
    tmp_ids=$(tail -n +5 /tmp/data.txt)
    c=1
    while IFS= read -r line; do 
      idf="system$c"
      ids+=( "$idf;$line" )
      ((c++))
    done <<< "$tmp_ids"
  else #add ids manually
    read -p "How many accounts are you using for this? " snum
    if [ $snum -lt 1 ]; then
      exit 1;
    fi;
    echo $snum >> /tmp/data.txt
    for ((i = 0; i < snum; i++))
    do 
      num=$(( $i + 1 ))
      idf="system$num"
      read -p "Enter the sniffed ID for Account $num: " sid
      sid=$(echo "$sid" | xargs)
      echo $sid >> /tmp/data.txt
      ids+=( "$idf;$sid" )
    done
  fi;

  mv /tmp/data.txt ./data.txt

  echo "-m string --string $reject_str --algo bm -j REJECT" > reject.rule
  sudo iptables -I FORWARD -m string --string $reject_str --algo bm -j REJECT
  
  n=${#ids[*]}
  INDEX=1
  for (( i = n-1; i >= 0; i-- ))
  do
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
  for i in "${ids[@]}"
  do
    IFS=';' read -r -a id <<< "$i"
    INDEX2=1
    for j in "${ids[@]}"
    do
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
      fi
      ((INDEX2++))
    done
    ((INDEX1++))
  done

  iptables-save > /etc/iptables/rules.v4

  echo "Setup is complete and matchmaking firewall is now active."
}

if [ "$action" == "setup" ]; then
  if ! command -v ngrep &> /dev/null
  then
      install_dependencies
  fi
  setup
elif [ "$action" == "stop" ]; then
  echo "Matchmaking is no longer being restricted."
  reject=$(<reject.rule)
  sudo iptables -D FORWARD $reject
elif [ "$action" == "start" ]; then
  if ! sudo iptables-save | grep -q "REJECT"; then
    echo "Matchmaking is now being restricted."
    pos=$(iptables -L FORWARD | grep "system" | wc -l)
    ((pos++))
    reject=$(<reject.rule)
    sudo iptables -I FORWARD $pos $reject
  fi
elif [ "$action" == "add" ]; then
  read -p "Enter the sniffed ID: " id
  id=$(echo "$id" | xargs)
  if [ ! -z "$id" ]; then
    echo $id >> data.txt
    n=$(sed -n '4p' < data.txt)
    ((n++))
    sed -i "4c$n" data.txt
    read -p "Would you like to enter another ID? y/n " yn
    yn=${yn:-"y"}
    if [ $yn == "y" ]; then
      bash d2firewall.sh -a add
    else
      bash d2firewall.sh -a setup < data.txt
    fi
  fi
elif [ "$action" == "remove" ]; then
  list=$(tail -n +5 data.txt | cat -n)
  echo "$list"
  total=$(echo "$list" | wc -l)
  read -p "How many IDs do you want to remove from the end of this list? " num
  if [[ $num -gt 0 && $num -le $total ]]; then
    head -n -"$num" data.txt > /tmp/data.txt && mv /tmp/data.txt ./data.txt
    n=$(sed -n '4p' < data.txt)
    n=$((n-num))
    sed -i "4c$n" data.txt
    bash d2firewall.sh -a setup < data.txt
  fi;
elif [ "$action" == "sniff" ]; then
  platform=$(sed -n '1p' < data.txt)
  if ! [[ $platform =~ ^(psn|xbox|steam)$ ]]; then
      echo "Only psn,xbox, and steam are supported atm."
    exit 1
  fi
  bash d2firewall.sh -a stop

  #auto sniff
  echo -e "${RED}Press any key to stop sniffing. DO NOT CTRL C${NC}"

  sleep 1
  if [ $platform == "psn" ]; then
    ngrep -l -q -W byline -d $INTERFACE "psn-4" udp | grep --line-buffered -o -P 'psn-4[0]{8}\K[A-F0-9]{7}' | tee -a data.txt &
  elif [ $platform == "xbox" ]; then
    ngrep -l -q -W byline -d $INTERFACE "xboxpwid:" udp | grep --line-buffered -o -P 'xboxpwid:[A-F0-9]{24}\K[A-F0-9]{8}' | tee -a data.txt &
  elif [ $platform == "steam" ]; then
    ngrep -l -q -W byline -d $INTERFACE "steamid:" udp | grep --line-buffered -o -P 'steamid:[0-9]{7}\K[0-9]{10}' | tee -a data.txt &
  fi
  while [ true ] ; do
    read -t 1 -n 1
    if [ $? = 0 ] ; then
      break
      fi
  done
  pkill -15 ngrep

  #remove duplicates
  awk '!a[$0]++' data.txt > /tmp/data.txt && mv /tmp/data.txt ./data.txt

  #update total number of ids
  n=$(tail -n +5 data.txt | wc -l)
  sed -i "4c$n" data.txt

  bash d2firewall.sh -a setup < data.txt
elif [ "$action" == "list" ]; then
  tail -n +5 data.txt | cat -n
  elif [ "$action" == "addxbox" ]; then
  add_cross_platform_id "xbox"

elif [ "$action" == "addsteam" ]; then
  add_cross_platform_id "steam"
elif [ "$action" == "sniffall" ]; then
  bash d2firewall.sh -a stop

  echo -e "${RED}Sniffing PSN + Xbox + Steam at the same time."
  echo -e "Press any key to stop sniffing. DO NOT CTRL+C${NC}"

  sleep 1

  # PSN
  ngrep -l -q -W byline -d $INTERFACE "psn-4" udp \
  | grep --line-buffered -o -P 'psn-4[0]{8}\K[A-F0-9]{7}' \
  | tee -a data.txt &

  # Xbox
  ngrep -l -q -W byline -d $INTERFACE "xboxpwid:" udp \
  | grep --line-buffered -o -P 'xboxpwid:[A-F0-9]{24}\K[A-F0-9]{8}' \
  | tee -a data.txt &

  # Steam
  ngrep -l -q -W byline -d $INTERFACE "steamid:" udp \
  | grep --line-buffered -o -P 'steamid:[0-9]{7}\K[0-9]{10}' \
  | tee -a data.txt &

  while true; do
    read -t 1 -n 1
    if [ $? = 0 ]; then
      break
    fi
  done

  pkill -15 ngrep

  # remove duplicates
  awk '!a[$0]++' data.txt > /tmp/data.txt && mv /tmp/data.txt ./data.txt

  # update total number of ids
  n=$(tail -n +5 data.txt | wc -l)
  sed -i "4c$n" data.txt

  bash d2firewall.sh -a setup < data.txt
  elif [ "$action" == "autotries" ]; then
  auto_trials
elif [ "$action" == "update" ]; then
  wget -q https://raw.githubusercontent.com/xmaver/Destiny-2-Matchmaking-Firewall/main/d2firewall.sh -O ./d2firewall.sh
  chmod +x ./d2firewall.sh
  echo -e "${GREEN}Script update complete."
  echo -e "Please rerun the initial setup to avoid any issues.${NC}"
elif [ "$action" == "load" ]; then
  echo "Loading firewall rules."
  if [ -f ./data.txt ]; then
      bash d2firewall.sh -a setup < ./data.txt
  else
    iptables-restore < /etc/iptables/rules.v4
  fi
elif [ "$action" == "reset" ]; then
  echo "Erasing all firewall rules."
  reset_ip_tables
fi
