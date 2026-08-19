#!/usr/bin/env bash
# ddr-demo.sh — generate realistic demo DNS traffic against UltraDDR.
#
# Two modes:
#   doh  — query the UltraDDR DoH endpoint directly with the client ID header.
#          Works from any network; traffic shows up in the UltraDDR dashboard
#          under that client ID. Logs verdict/category per query.
#   dig  — plain port-53 queries via the system resolver. Use this when the Pi
#          is on the TESTDDR network (192.168.3.0/24) and that network's DNS
#          egresses to UltraDDR.
#
# Usage:
#   ./ddr-demo.sh --mode doh --duration 600
#   ./ddr-demo.sh --mode dig --duration 0        # 0 = run forever
#
# Env overrides: DDR_ENDPOINT, DDR_CLIENT_ID, BENIGN_FILE, SUSPECT_FILE,
#                SUSPECT_PCT (default 15), LOG_FILE
set -u

DDR_ENDPOINT="${DDR_ENDPOINT:-https://rcsv1.ddr.ultradns.com/resolve}"
DDR_CLIENT_ID="${DDR_CLIENT_ID:-5fe714d3-6cb6-4f24-8002-723e09cc387b}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENIGN_FILE="${BENIGN_FILE:-$SCRIPT_DIR/domains-benign.txt}"
SUSPECT_FILE="${SUSPECT_FILE:-$SCRIPT_DIR/domains-suspect.txt}"
ADTRACK_FILE="${ADTRACK_FILE:-$SCRIPT_DIR/domains-adtrack.txt}"
SUSPECT_PCT="${SUSPECT_PCT:-15}"
ADTRACK_PCT="${ADTRACK_PCT:-20}"
LOG_FILE="${LOG_FILE:-$SCRIPT_DIR/ddr-demo.log.csv}"

MODE="dig"
DURATION=600
DIURNAL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)     MODE="$2"; shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    --diurnal)  DIURNAL=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Diurnal rate multiplier (percent of peak), Eastern Time.
# Weekday working hours = 100; after hours = 80 (the requested 20% drop);
# weekend runs the same shape a notch lower; overnight dips harder so the
# day/night curve is visible on the dashboard. Tune the numbers freely.
diurnal_multiplier() {
  local dow hr m
  dow=$(TZ=America/New_York date +%u)          # 1=Mon .. 7=Sun
  hr=$((10#$(TZ=America/New_York date +%H)))
  if (( dow <= 5 )); then
    if   (( hr >= 8 && hr < 18 )); then m=100  # weekday working hours
    elif (( hr >= 23 || hr < 7 )); then m=40   # weekday overnight
    else                                m=80   # weekday after hours
    fi
  else
    if   (( hr >= 9 && hr < 21 )); then m=85   # weekend daytime
    elif (( hr >= 23 || hr < 8 )); then m=34   # weekend overnight
    else                                m=68   # weekend evening
    fi
  fi
  echo "$m"
}

mapfile -t BENIGN  < <(grep -v '^\s*\(#\|$\)' "$BENIGN_FILE")
mapfile -t SUSPECT < <(grep -v '^\s*\(#\|$\)' "$SUSPECT_FILE")
[[ ${#BENIGN[@]} -gt 0 && ${#SUSPECT[@]} -gt 0 ]] || { echo "empty domain lists" >&2; exit 1; }
ADTRACK=()
[[ -f "$ADTRACK_FILE" ]] && mapfile -t ADTRACK < <(grep -v '^\s*\(#\|$\)' "$ADTRACK_FILE")
[[ ${#ADTRACK[@]} -gt 0 ]] || ADTRACK_PCT=0

[[ -f "$LOG_FILE" ]] || echo "timestamp,mode,domain,kind,verdict,categories,answer" >> "$LOG_FILE"

query_doh() {  # $1=domain -> sets VERDICT, CATEGORIES, ANSWER
  local hdrs body
  hdrs="$(curl -sS -m 10 -D - -o /dev/null \
      -H "X-UltraDDR-Client-Id: $DDR_CLIENT_ID" \
      -H "Accept: application/dns-json" \
      --get --data-urlencode "name=$1" --data-urlencode "type=A" \
      "$DDR_ENDPOINT" 2>/dev/null)" || { VERDICT="error"; CATEGORIES=""; ANSWER=""; return; }
  VERDICT="$(sed -n 's/^[Xx]-[Uu]ltraddr-[Vv]erdict-[Ss]tatus: *//p' <<<"$hdrs" | tr -d '\r')"
  CATEGORIES="$(sed -n 's/^[Xx]-[Uu]ltraddr-[Cc]ategories: *//p' <<<"$hdrs" | tr -d '\r')"
  body="$(curl -sS -m 10 \
      -H "X-UltraDDR-Client-Id: $DDR_CLIENT_ID" \
      -H "Accept: application/dns-json" \
      --get --data-urlencode "name=$1" --data-urlencode "type=A" \
      "$DDR_ENDPOINT" 2>/dev/null)" || true
  ANSWER="$(grep -o '"data":"[^"]*"' <<<"$body" | head -1 | cut -d'"' -f4)"
}

query_dig() {  # $1=domain -> sets VERDICT, CATEGORIES, ANSWER
  # DIG_SERVERS: space-separated resolver IPs; one is picked per query.
  # Pin these to the UltraDDR resolvers so nothing falls back to LAN DNS.
  local at=()
  if [[ -n "${DIG_SERVERS:-}" ]]; then
    local srv=($DIG_SERVERS)
    at=("@${srv[RANDOM % ${#srv[@]}]}")
  fi
  ANSWER="$(dig +short +time=5 +tries=1 "${at[@]}" "$1" A 2>/dev/null | head -1)"
  VERDICT=""; CATEGORIES=""
  # UltraDDR block-page IPs come from 74.2.55.0/24 (observed .86, .57)
  [[ "$ANSWER" == 74.2.55.* ]] && VERDICT="block"
}

START=$(date +%s)
COUNT=0
echo "[$(date '+%H:%M:%S')] mode=$MODE duration=${DURATION}s suspect=${SUSPECT_PCT}% log=$LOG_FILE"
while :; do
  [[ "$DURATION" -gt 0 && $(( $(date +%s) - START )) -ge "$DURATION" ]] && break

  # A "browsing session": burst of 3-8 queries, then a longer pause.
  BURST=$(( RANDOM % 6 + 3 ))
  for ((i=0; i<BURST; i++)); do
    R=$(( RANDOM % 100 ))
    if (( R < SUSPECT_PCT )); then
      DOMAIN="${SUSPECT[RANDOM % ${#SUSPECT[@]}]}"; KIND="suspect"
    elif (( R < SUSPECT_PCT + ADTRACK_PCT )); then
      DOMAIN="${ADTRACK[RANDOM % ${#ADTRACK[@]}]}"; KIND="adtrack"
    else
      DOMAIN="${BENIGN[RANDOM % ${#BENIGN[@]}]}"; KIND="benign"
    fi
    if [[ "$MODE" == "doh" ]]; then query_doh "$DOMAIN"; else query_dig "$DOMAIN"; fi
    echo "$(date -Is),$MODE,$DOMAIN,$KIND,${VERDICT:-},${CATEGORIES:-},${ANSWER:-}" >> "$LOG_FILE"
    COUNT=$((COUNT+1))
    [[ -n "${VERDICT:-}" && "${VERDICT:-}" != "None" ]] && \
      echo "[$(date '+%H:%M:%S')] $DOMAIN -> verdict=$VERDICT categories=$CATEGORIES"
    sleep "0.$(( RANDOM % 8 + 1 ))"
  done
  if (( DIURNAL )); then
    M=$(diurnal_multiplier)
    # Pause base 4-12s ≈ 1M queries per 30 days across the diurnal curve
    # (~1,850/hr weekday peak). Was 15-44s ≈ 315k/month.
    PAUSE=$(( (RANDOM % 9 + 4) * 100 / M ))
    echo "[$(date '+%H:%M:%S')] $COUNT queries sent (rate=${M}%, next burst in ${PAUSE}s)"
  else
    PAUSE=$(( RANDOM % 20 + 5 ))
    echo "[$(date '+%H:%M:%S')] $COUNT queries sent"
  fi
  sleep "$PAUSE"
done
echo "done: $COUNT queries in $(( $(date +%s) - START ))s -> $LOG_FILE"
