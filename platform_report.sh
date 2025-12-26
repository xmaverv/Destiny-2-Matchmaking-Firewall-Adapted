#!/bin/bash
# Platform Log Reporter
# Generates report by IP, platform and time window

LOGFILE="platform.log"

if [ ! -f "$LOGFILE" ]; then
  echo "platform.log not found."
  exit 1
fi

echo "=============================="
echo " Platform Traffic Report"
echo " Generated: $(date)"
echo "=============================="
echo

awk '
{
  # Extract timestamp
  match($0, /\[([0-9\-]+ [0-9:]+)\]/, t)
  time = t[1]

  # Extract platform
  match($0, /\] ([a-z]+):/, p)
  platform = p[1]

  # Extract IP
  match($0, /([0-9]{1,3}(\.[0-9]{1,3}){3})/, i)
  ip = i[1]

  key = platform "|" ip

  if (!(key in first)) {
    first[key] = time
  }
  last[key] = time
  count[key]++
}
END {
  printf "%-8s %-16s %-20s %-20s %s\n", \
         "PLATFORM", "IP", "FIRST SEEN", "LAST SEEN", "COUNT"
  printf "%-8s %-16s %-20s %-20s %s\n", \
         "--------", "--", "----------", "---------", "-----"

  for (k in count) {
    split(k, a, "|")
    printf "%-8s %-16s %-20s %-20s %d\n", \
           a[1], a[2], first[k], last[k], count[k]
  }
}
' "$LOGFILE" | sort
