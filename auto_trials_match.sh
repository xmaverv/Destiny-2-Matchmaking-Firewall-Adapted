#!/bin/bash
# Auto reset Trials matchmaking if external ID appears

LOGFILE="platform.log"
OBS_WINDOW=30     # segundos
SLEEP_BETWEEN=10  # segundos

MEUS_IDS=(
  "psn-400000000686815A"
  "psn-4000000006810123"
  "psn-4000000006B0EC74"
  "psn-40000000067776AC"
)

contains_my_id () {
  local id="$1"
  for my in "${MEUS_IDS[@]}"; do
    [[ "$id" == "$my" ]] && return 0
  done
  return 1
}

while true; do
  echo "[INFO] Starting new matchmaking attempt..."

  sudo ./d2firewall.sh -a start
  sudo ./d2firewall.sh -a sniff &

  SNIFF_PID=$!
  sleep "$OBS_WINDOW"

  kill "$SNIFF_PID" 2>/dev/null
  sleep 1

  external_found=0

  ids_detected=$(grep -o -P 'psn-[0-9A-Za-z]+' "$LOGFILE" | sort -u)

  for id in $ids_detected; do
    if ! contains_my_id "$id"; then
      external_found=1
      echo "[WARN] External ID detected: $id"
      break
    fi
  done

  if [ "$external_found" -eq 0 ]; then
    echo "[SUCCESS] Only your IDs detected. Lobby isolated."
    exit 0
  fi

  echo "[ACTION] Resetting firewall and retrying..."
  sudo ./d2firewall.sh -a reset
  sleep "$SLEEP_BETWEEN"
done
