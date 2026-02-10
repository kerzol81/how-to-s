#!/bin/sh
# test_gps.sh - Sierra MC7304 GNSS test (AT-based, BusyBox-safe)
# Prints GNSS status + tries to dump all available GNSS info each poll.
# 0=FIX, 2=NO FIX, 1=ERROR

AT_PORT="${1:-/dev/ttyUSB2}"
BAUD=115200
TIMEOUT=600
POLL=5

log(){ echo "gps_test: $*"; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: missing command: $1" >&2; exit 1; }; }
need microcom
need tr
need grep
need sed
need date
need sleep

[ -c "$AT_PORT" ] || { echo "error: $AT_PORT not found" >&2; exit 1; }

at() {
  # microcom returns modem output + OK/ERROR; we normalize CR
  printf "%s\r\n" "$1" | microcom -t 1200 "$AT_PORT" 2>/dev/null | tr -d '\r'
}

get_last_fix_status() {
  echo "$1" | sed -n 's/.*Last Fix Status[[:space:]]*=[[:space:]]*\([^,]*\).*/\1/p' | head -n1
}

# True fix if 2D/3D/VALID/SUCCESS
has_real_fix() {
  s="$1"
  echo "$s" | grep -Eqi 'Last[[:space:]]+Fix[[:space:]]+Status[[:space:]]*=[[:space:]]*(2D|3D|VALID|SUCCESS)' && return 0
  echo "$s" | grep -Eqi 'Fix[[:space:]]+Session[[:space:]]+Status[[:space:]]*=[[:space:]]*(2D|3D|VALID|SUCCESS)' && return 0
  return 1
}

dump_cmd() {
  cmd="$1"
  out="$(at "$cmd")"
  # Print even if ERROR (so you can see what's supported)
  echo "----- $cmd -----"
  echo "$out"
}

log "Using AT port: $AT_PORT"
log "ATI:"
dump_cmd "ATI" | sed -n '1,80p'

log "Starting GPS session (AUTOSTART + GPSTRACK)..."

at "AT!GPSAUTOSTART=1" >/dev/null 2>&1
at "AT!GPSTRACK=1,255,60,1000,1" >/dev/null 2>&1

log "Polling GNSS for up to ${TIMEOUT}s (every ${POLL}s)..."
start="$(date +%s 2>/dev/null)"; [ -z "$start" ] && start=0

while :; do
  s="$(at "AT!GPSSTATUS?")"
  echo "===== AT!GPSSTATUS? ====="
  echo "$s"

  lfs="$(get_last_fix_status "$s")"
  [ -n "$lfs" ] && log "LastFixStatus=$lfs"

  dump_cmd "AT!GPSINFO?"
  dump_cmd "AT!GPSLOC?"
  dump_cmd "AT!GPSTRACK?"
  dump_cmd "AT!GPSCFG?"
  dump_cmd "AT!GPSSATINFO?"

  if has_real_fix "$s"; then
    log "REAL FIX ACQUIRED"
    exit 0
  fi

  now="$(date +%s 2>/dev/null)"; [ -z "$now" ] && now="$start"
  elapsed=$((now - start))
  [ "$elapsed" -ge "$TIMEOUT" ] && break

  sleep "$POLL"
done

log "NO FIX YET"
log "If time stays 1980 and status shows FAIL/NONE, GNSS is running but not seeing satellites."
log "Most common reasons: GNSS antenna not connected (or wrong connector), indoors/poor sky view, or GNSS path not wired."
log "To stop GPS:"
echo "  microcom -s $BAUD $AT_PORT"
echo "  AT!GPSTRACK=0"
echo "  AT!GPSAUTOSTART=0"
exit 2

