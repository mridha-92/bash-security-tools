#!/usr/bin/env bash
# cachepoison-batch.sh
# Batch-run cachepoison-check.sh against a list of endpoints.
# Usage: ./cachepoison-batch.sh -f endpoints.txt [-p PARALLEL] [-o OUTDIR] [-t TIMEOUT] [-s SCRIPT]
#
# endpoints.txt should contain one URL per line. Lines starting with # are ignored.

set -euo pipefail

print_usage(){
  cat <<EOF
Usage: $0 -f ENDPOINT_FILE [-p PARALLEL] [-o OUTDIR] [-t TIMEOUT] [-s SCRIPT]
Options:
  -f ENDPOINT_FILE   File with endpoint URLs (one per line). Required.
  -p PARALLEL        Number of concurrent workers (default: 4).
  -o OUTDIR          Base output directory (default: ./batch_results_TIMESTAMP).
  -t TIMEOUT         curl timeout (passed to inner script) default: 10
  -s SCRIPT          Path to single-target script (default: ./cachepoison-check.sh)
Example:
  ./cachepoison-batch.sh -f targets.txt -p 6 -o ./results_all -t 8
EOF
  exit 1
}

# defaults
PARALLEL=4
OUTDIR=""
TIMEOUT=10
ENDPOINT_FILE=""
SINGLE_SCRIPT="./cachepoison-check.sh"

while getopts "f:p:o:t:s:h" opt; do
  case $opt in
    f) ENDPOINT_FILE="$OPTARG" ;;
    p) PARALLEL="$OPTARG" ;;
    o) OUTDIR="$OPTARG" ;;
    t) TIMEOUT="$OPTARG" ;;
    s) SINGLE_SCRIPT="$OPTARG" ;;
    h) print_usage ;;
    *) print_usage ;;
  esac
done

if [[ -z "$ENDPOINT_FILE" ]]; then
  echo "[!] Endpoint file required."
  print_usage
fi

if [[ ! -f "$ENDPOINT_FILE" ]]; then
  echo "[!] Endpoint file '$ENDPOINT_FILE' not found."
  exit 2
fi

if [[ ! -x "$SINGLE_SCRIPT" ]]; then
  echo "[!] Single-target script '$SINGLE_SCRIPT' not found or not executable."
  echo "    Make sure cachepoison-check.sh is in the same directory and executable."
  exit 3
fi

TS=$(date +%Y%m%d_%H%M%S)
OUTDIR=${OUTDIR:-"./batch_results_$TS"}
mkdir -p "$OUTDIR"

LOG_SUCCESS="$OUTDIR/success.log"
LOG_FAIL="$OUTDIR/fail.log"
LOG_SKIP="$OUTDIR/skip.log"

echo "Batch run started: $(date)" > "$OUTDIR/run_info.txt"
echo "Endpoint file: $ENDPOINT_FILE" >> "$OUTDIR/run_info.txt"
echo "Parallel: $PARALLEL" >> "$OUTDIR/run_info.txt"
echo "Timeout: $TIMEOUT" >> "$OUTDIR/run_info.txt"
echo "Single script: $SINGLE_SCRIPT" >> "$OUTDIR/run_info.txt"
echo "Output dir: $OUTDIR" >> "$OUTDIR/run_info.txt"

# sanitize a URL into a safe folder name
sanitize_name() {
  local url="$1"
  # remove protocol and trailing slash, replace non-alnum by _
  local name
  name=$(echo "$url" | sed -E 's~https?://~~I; s~/$~~; s/[^a-zA-Z0-9.\-]/_/g')
  echo "$name"
}

# validate basic URL form (allows http/https)
valid_url() {
  local u="$1"
  if [[ "$u" =~ ^https?://[A-Za-z0-9._%:+@-]+(:[0-9]+)?(/.*)?$ ]]; then
    return 0
  fi
  return 1
}

# worker that runs for one URL
run_one() {
  local url="$1"
  local outbase="$2"
  local timeout="$3"
  local script="$4"

  # create per-target folder
  local sanitized
  sanitized=$(sanitize_name "$url")
  local tgt_out="$outbase/$sanitized"
  mkdir -p "$tgt_out"

  echo "[*] Starting: $url"
  # call single script with custom outdir
  if "$script" -u "$url" -o "$tgt_out" -t "$timeout" > "$tgt_out/_stdout.log" 2> "$tgt_out/_stderr.log"; then
    echo "$(date +%Y-%m-%d_%H:%M:%S) OK $url -> $tgt_out" >> "$LOG_SUCCESS"
    echo "[+] OK: $url"
  else
    echo "$(date +%Y-%m-%d_%H:%M:%S) FAIL $url -> $tgt_out" >> "$LOG_FAIL"
    echo "[-] FAIL: $url (see $tgt_out/_stderr.log)"
  fi
}

export -f sanitize_name valid_url run_one
export SINGLE_SCRIPT
export LOG_SUCCESS LOG_FAIL LOG_SKIP
export OUTDIR TIMEOUT

# Read file, remove comments/empty lines, and prepare tasks
TASKS_FILE=$(mktemp)
while IFS= read -r line || [[ -n "$line" ]]; do
  line_trim=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  # skip comments or blank lines
  if [[ -z "$line_trim" || "$line_trim" == \#* ]]; then
    continue
  fi
  # if not starting with http[s]://, try to add https:// and validate
  if [[ ! "$line_trim" =~ ^https?:// ]]; then
    candidate="https://$line_trim"
  else
    candidate="$line_trim"
  fi
  if valid_url "$candidate"; then
    echo "$candidate" >> "$TASKS_FILE"
  else
    echo "$(date +%Y-%m-%d_%H:%M:%S) SKIP $line_trim (invalid URL)" >> "$LOG_SKIP"
    echo "[!] Skip invalid URL: $line_trim"
  fi
done < "$ENDPOINT_FILE"

TOTAL=$(wc -l < "$TASKS_FILE" | tr -d ' ')
echo "Prepared $TOTAL valid endpoints."

# run tasks in parallel using xargs (fallback to sequential if PARALLEL=1)
if [[ "$PARALLEL" -gt 1 ]]; then
  # xargs will call bash -c 'run_one "$0" "$OUTDIR" "$TIMEOUT" "$SINGLE_SCRIPT"' url
  cat "$TASKS_FILE" | xargs -n1 -P"$PARALLEL" -I{} bash -c 'run_one "$0" "$1" "$2" "$3"' {} "$OUTDIR" "$TIMEOUT" "$SINGLE_SCRIPT"
else
  while IFS= read -r url; do
    run_one "$url" "$OUTDIR" "$TIMEOUT" "$SINGLE_SCRIPT"
  done < "$TASKS_FILE"
fi

rm -f "$TASKS_FILE"

echo "Batch run finished: $(date)" >> "$OUTDIR/run_info.txt"
echo "Results: successes: $(wc -l < "$LOG_SUCCESS" 2>/dev/null || echo 0), failures: $(wc -l < "$LOG_FAIL" 2>/dev/null || echo 0), skipped: $(wc -l < "$LOG_SKIP" 2>/dev/null || echo 0)"
echo "Success log: $LOG_SUCCESS"
echo "Fail log: $LOG_FAIL"
echo "Skip log: $LOG_SKIP"
echo "Per-target results in: $OUTDIR"

