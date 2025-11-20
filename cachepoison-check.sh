#!/usr/bin/env bash
# cachepoison-check.sh
# Quick cache poisoning test tool (header & query vectors)
# Usage: ./cachepoison-check.sh -u "https://example.com/path"
# Requirements: curl, grep, sed, mktemp, awk, tr, uuidgen (optional)

set -euo pipefail

print_usage() {
  cat <<EOF
Usage: $0 -u URL [-o OUTDIR] [-t TIMEOUT] [-r ROUNDS]

Options:
  -u URL       Target URL (required). Include protocol (http(s)://).
  -o OUTDIR    Output directory for results (default: ./cachepoison_results_TIMESTAMP)
  -t TIMEOUT   curl timeout seconds (default: 10)
  -r ROUNDS    Number of header vectors to try at once (default: 1 - you can increase to repeat checks)
Example:
  $0 -u "https://example.com/index.html" -o ./results -t 8
EOF
  exit 1
}

# defaults
OUTDIR=""
TIMEOUT=10
ROUNDS=1
URL=""

while getopts "u:o:t:r:h" opt; do
  case $opt in
    u) URL="$OPTARG" ;;
    o) OUTDIR="$OPTARG" ;;
    t) TIMEOUT="$OPTARG" ;;
    r) ROUNDS="$OPTARG" ;;
    h) print_usage ;;
    *) print_usage ;;
  esac
done

if [[ -z "$URL" ]]; then
  echo "Error: URL required."
  print_usage
fi

# safety reminder
cat <<WARN
##############################################################
WARNING: Only run this tool against systems YOU OWN or are
explicitly authorized to test. Unauthorized testing is illegal.
##############################################################
WARN

# prepare output dir
TS=$(date +%Y%m%d_%H%M%S)
OUTDIR=${OUTDIR:-"./cachepoison_results_$TS"}
mkdir -p "$OUTDIR"

# detect uuid generator for marker
if command -v uuidgen >/dev/null 2>&1; then
  mkid() { uuidgen; }
else
  mkid() { head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
fi

# header vectors to try (common cache-poisoning headers)
HEADER_VECTORS=(
  "X-Forwarded-Host"
  "X-Host"
  "X-Original-URL"
  "X-Rewrite-URL"
  "X-Forwarded-Proto"
  "X-Forwarded-Scheme"
  "X-Forwarded-For"
  "X-Forwarded"
  "Origin"
  "Referer"
  "User-Agent"
  # You can append more headers here
)

# query parameter vectors to try (append a unique param name)
QUERY_KEYS=(
  "q"
  "s"
  "id"
  "lang"
  "search"
  "page"
)

# helper: issue request and save headers+body
issue_request() {
  local req_url=$1
  shift
  local extra_curl_args=("$@")
  local tmpf_hdr tmpf_body
  tmpf_hdr=$(mktemp)
  tmpf_body=$(mktemp)
  # -sS to show errors, -D - to get headers, -L follow redirects
  curl -sS -D "$tmpf_hdr" --max-time "$TIMEOUT" -L "${extra_curl_args[@]}" "$req_url" -o "$tmpf_body" || true
  echo "$tmpf_hdr|$tmpf_body"
}

# baseline
echo "[*] Gathering baseline for $URL"
baseline_files="$OUTDIR/baseline"
mkdir -p "$baseline_files"
IFS='|' read -r hdr body < <(issue_request "$URL")
cp "$hdr" "$baseline_files/headers.txt"
cp "$body" "$baseline_files/body.html"
echo "[*] Baseline saved to $baseline_files"

# function to check response body for marker
body_contains_marker() {
  local bodyfile=$1
  local marker=$2
  if grep -Fq "$marker" "$bodyfile"; then
    return 0
  fi
  return 1
}

report_file="$OUTDIR/report.txt"
echo "Cache poisoning check report - $(date)" > "$report_file"
echo "Target: $URL" >> "$report_file"
echo "" >> "$report_file"

# iterate header vectors
for ((round=1; round<=ROUNDS; round++)); do
  echo ""
  echo "=== Round $round ==="
  echo "=== Round $round ===" >> "$report_file"

  for header in "${HEADER_VECTORS[@]}"; do
    marker="CP-${header}-$(mkid)"
    echo "[*] Testing header vector: $header -> marker: $marker"
    testdir="$OUTDIR/round${round}_$(echo $header | tr '/' '_' | tr ' ' '_')"
    mkdir -p "$testdir"

    # 1) send crafted request with header containing the marker
    # Some servers ignore angle brackets, so using a simple marker string
    IFS='|' read -r hdrfile bodyfile < <(issue_request "$URL" -H "$header: $marker")
    mv "$hdrfile" "$testdir/request_with_header_headers.txt"
    mv "$bodyfile" "$testdir/request_with_header_body.html"

    # 2) immediately request clean URL and save
    IFS='|' read -r hdrfile2 bodyfile2 < <(issue_request "$URL")
    mv "$hdrfile2" "$testdir/clean_after_header_headers.txt"
    mv "$bodyfile2" "$testdir/clean_after_header_body.html"

    # 3) analyze: check Age header and presence of marker in clean response
    age=$(grep -i '^Age:' "$testdir/clean_after_header_headers.txt" | head -n1 | awk '{print $2}' || echo "-")
    via=$(grep -i '^Via:' "$testdir/clean_after_header_headers.txt" | head -n1 | sed -n 's/^Via: //Ip' || echo "-")
    cache_control=$(grep -i '^Cache-Control:' "$testdir/request_with_header_headers.txt" | head -n1 | sed -n 's/^Cache-Control: //Ip' || echo "-")
    vary=$(grep -i '^Vary:' "$testdir/request_with_header_headers.txt" | head -n1 | sed -n 's/^Vary: //Ip' || echo "-")

    poisoned="no"
    if body_contains_marker "$testdir/clean_after_header_body.html" "$marker"; then
      poisoned="yes (marker reflected in subsequent clean response)"
    fi

    # also flag if Age header present with non-zero value
    if [[ "$age" != "-" && "$age" -gt 0 2>/dev/null ]]; then
      age_note="Age:$age (cache present)"
    elif [[ "$age" != "-" ]]; then
      age_note="Age:$age"
    else
      age_note="Age: -"
    fi

    echo "Header: $header" >> "$report_file"
    echo "  Marker: $marker" >> "$report_file"
    echo "  Poisoned: $poisoned" >> "$report_file"
    echo "  $age_note" >> "$report_file"
    echo "  Via: $via" >> "$report_file"
    echo "  Cache-Control (from crafted response): $cache_control" >> "$report_file"
    echo "  Vary (from crafted response): $vary" >> "$report_file"
    echo "" >> "$report_file"

    # short console summary
    echo "  -> Poisoned: $poisoned, $age_note, Via: $via"
  done

  # Now try query param vectors (same procedure but append param)
  for qk in "${QUERY_KEYS[@]}"; do
    marker="CP-Q-${qk}-$(mkid)"
    echo "[*] Testing query-vector: ?${qk}=${marker}"
    testdir="$OUTDIR/round${round}_query_${qk}"
    mkdir -p "$testdir"

    # craft URL with query param
    # if URL already has query, append with &, else ?
    if [[ "$URL" == *\?* ]]; then
      test_url="${URL}&${qk}=${marker}"
    else
      test_url="${URL}?${qk}=${marker}"
    fi

    IFS='|' read -r hdrfile bodyfile < <(issue_request "$test_url")
    mv "$hdrfile" "$testdir/request_with_query_headers.txt"
    mv "$bodyfile" "$testdir/request_with_query_body.html"

    # immediate clean request
    IFS='|' read -r hdrfile2 bodyfile2 < <(issue_request "$URL")
    mv "$hdrfile2" "$testdir/clean_after_query_headers.txt"
    mv "$bodyfile2" "$testdir/clean_after_query_body.html"

    age=$(grep -i '^Age:' "$testdir/clean_after_query_headers.txt" | head -n1 | awk '{print $2}' || echo "-")
    via=$(grep -i '^Via:' "$testdir/clean_after_query_headers.txt" | head -n1 | sed -n 's/^Via: //Ip' || echo "-")
    cache_control=$(grep -i '^Cache-Control:' "$testdir/request_with_query_headers.txt" | head -n1 | sed -n 's/^Cache-Control: //Ip' || echo "-")
    vary=$(grep -i '^Vary:' "$testdir/request_with_query_headers.txt" | head -n1 | sed -n 's/^Vary: //Ip' || echo "-")

    poisoned="no"
    if body_contains_marker "$testdir/clean_after_query_body.html" "$marker"; then
      poisoned="yes (marker reflected in subsequent clean response)"
    fi

    if [[ "$age" != "-" && "$age" -gt 0 2>/dev/null ]]; then
      age_note="Age:$age (cache present)"
    elif [[ "$age" != "-" ]]; then
      age_note="Age:$age"
    else
      age_note="Age: -"
    fi

    echo "Query param: $qk" >> "$report_file"
    echo "  Marker: $marker" >> "$report_file"
    echo "  Poisoned: $poisoned" >> "$report_file"
    echo "  $age_note" >> "$report_file"
    echo "  Via: $via" >> "$report_file"
    echo "  Cache-Control (from crafted response): $cache_control" >> "$report_file"
    echo "  Vary (from crafted response): $vary" >> "$report_file"
    echo "" >> "$report_file"

    echo "  -> Poisoned: $poisoned, $age_note, Via: $via"
  done
done

echo ""
echo "[*] Done. Report: $report_file"
echo "[*] Raw responses and headers saved under: $OUTDIR"

# quick tips appended
cat >> "$report_file" <<EOF

Notes:
- 'Poisoned' = marker string injected by crafted request was observed in the subsequent clean response.
- Presence of Age header >0 or the Via header suggests an intermediate cache/CDN.
- False positives can happen (origin may reflect something temporarily without caching). Re-run several times and review timestamps.
- Extend HEADER_VECTORS and QUERY_KEYS in the script to try additional vectors.
- Only test targets you own or are authorized to test.

EOF
