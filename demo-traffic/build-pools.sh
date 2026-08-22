#!/usr/bin/env bash
# build-pools.sh — (re)build the large diversity pools used by ddr-demo.sh.
# Run on the demo host (jmacpi). Produces:
#   pools/top-1m.csv      top-sites list for benign traffic (gitignored, ~22MB)
#   domains-threat.txt    malware-feed domains FILTERED to those UltraDDR blocks
#
# The threat filter is the safety guarantee: we keep only domains that return
# UltraDDR's block-page IP (74.2.55.x), so every threat query the demo makes is
# intercepted at UltraDDR and never reaches live infrastructure. Domains the
# feed lists but UltraDDR allows are discarded here and never queried at runtime.
#
# Env: DIG_SERVER (default 204.74.103.5), MAX_CHECK (default 2500), PAR (30)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
DIG_SERVER="${DIG_SERVER:-204.74.103.5}"
MAX_CHECK="${MAX_CHECK:-2500}"
PAR="${PAR:-30}"
mkdir -p pools && cd pools

echo "[1/4] top-sites list (Tranco, fallback Cisco Umbrella)..."
if ! curl -fsSL -m 120 -o tranco.zip "https://tranco-list.eu/top-1m.csv.zip"; then
  curl -fsSL -m 120 -o tranco.zip "https://s3-us-west-1.amazonaws.com/umbrella-static/top-1m.csv.zip"
fi
unzip -o -q tranco.zip && test -f top-1m.csv
echo "      top-1m.csv: $(wc -l < top-1m.csv) rows"

echo "[2/4] malware feed (abuse.ch URLhaus host file)..."
curl -fsSL -m 120 -o urlhaus-hosts.txt "https://urlhaus.abuse.ch/downloads/hostfile/"

echo "[3/4] extract + dedup candidate domains..."
awk '$2 {print $2}' urlhaus-hosts.txt | grep -v '^#' | tr -d '\r' \
  | grep -E '^[a-z0-9.-]+\.[a-z]{2,}$' | sort -u > threat-candidates.txt
echo "      candidates: $(wc -l < threat-candidates.txt)"

echo "[4/4] filter to UltraDDR-blocked (74.2.55.x), $PAR-way parallel, cap $MAX_CHECK..."
check() { local ip; ip=$(dig +short +time=3 +tries=1 @"$DIG_SERVER" "$1" A 2>/dev/null | grep -v '^;;' | head -1); [[ "$ip" == 74.2.55.* ]] && echo "$1"; }
export -f check; export DIG_SERVER
{
  echo "# UltraDDR-blocked malware domains (abuse.ch URLhaus, filtered)."
  echo "# Rebuilt by build-pools.sh. Every entry returns the block page, so"
  echo "# queries stop at UltraDDR and never reach live infrastructure."
  head -"$MAX_CHECK" threat-candidates.txt | xargs -P "$PAR" -I{} bash -c 'check "$@"' _ {}
} > ../domains-threat.txt
echo "      kept: $(grep -cv '^#' ../domains-threat.txt) blocked domains -> domains-threat.txt"
echo "done."
