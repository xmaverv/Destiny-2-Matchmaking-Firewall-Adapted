#!/bin/bash
# Count unique players per sniff session
# Uses platform.log

LOGFILE="platform.log"

if [ ! -f "$LOGFILE" ]; then
  echo "platform.log not found"
  exit 1
fi

awk '
/^=== Sniff started:/ {
  session_start = substr($0, index($0,$5))
  delete players
  next
}

/^=== Sniff stopped:/ {
  session_end = substr($0, index($0,$5))
  count = 0
  for (p in players) count++
  printf "%-25s %-25s %-8s %d\n", session_start, session_end, "PSN", count
  next
}

{
  if (match($0, /(psn-[0-9A-Za-z]+)/, m)) {
    players[m[1]] = 1
  }
}
' "$LOGFILE" | \
awk 'BEGIN {
  printf "%-25s %-25s %-8s %s\n", \
         "SESSION START", "SESSION END", "PLATFORM", "UNIQUE_PLAYERS"
  printf "%-25s %-25s %-8s %s\n", \
         "-------------", "-----------", "--------", "--------------"
} { print }'
