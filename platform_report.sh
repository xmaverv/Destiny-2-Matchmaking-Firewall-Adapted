#!/bin/bash
# Platform Log Reporter
# Generates report by IP, platform and time window
# Optional filters: --psn --xbox --steam --epic

LOGFILE="platform.log"

if [ ! -f "$LOGFILE" ]; then
  echo "platform.log not found."
  exit 1
fi

# -------------------------
# PLATFORM FILTER PARSING
# -------------------------
FILTERS=()

for arg in "$@"; do
  case "$arg" in
    --psn)   FILTERS+=("psn") ;;
    --xbox)  FILTERS+=("xbox") ;;
    --steam) FILTERS+=("steam") ;;
    --epic)  FILTERS+=("epic") ;;
    *)
      echo "Unknown option: $arg"
      echo "Usage: $0 [--psn] [--xbox] [--steam] [--epic]"
      exit 1
      ;;
  esac
done

# Build regex for awk (if filters exist)
if [ ${#FILTERS[@]} -gt 0 ]; then
  PLATFORM_REGEX=$(IFS="|"; echo "${FILTERS[*]}")
else
  PLATFORM_REGEX=".*"
fi

echo "=============================="
echo " Platform Traffic Report"
echo " Generated: $(date)"
if [ "$PLATFORM_REGEX" != ".*" ]; then
  echo " Filter: $PLATFORM_REGEX"
fi
echo "=============================="
echo

awk -v platform_regex="$PLATFORM_REGEX" '
{
  match($0, /\[([0-9\-]+ [0-9:]+)\]/, t)
  time = t[1]

  match($0, /\] ([a-z]+):/, p)
  platform = p[1]

  if (platform !~ platform_regex) {
    next
  }

  # Extract IP (prefer destination IP)
  if (match($0, /-> ([0-9]{1,3}(\.[0-9]{1,3}){3})/, i)) {
    ip = i[1]
  } else if (match($0, /([0-9]{1,3}(\.[0-9]{1,3}){3})/, i)) {
    ip = i[1]
  } else {
    next
  }

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
