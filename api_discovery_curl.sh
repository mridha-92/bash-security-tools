#!/usr/bin/env bash
# api_discovery_curl_v2.sh
# Ready-to-run Bash script for discovering API endpoints using curl
# Includes: robots.txt, sitemap.xml, swagger/openapi, JS scraping, wordlist fuzzing,
#          GraphQL introspection check, basic subdomain enumeration via crt.sh,
#          header inspection, and aggregation of results.
#
# Safety note: Do NOT use this script against targets you don't own or have
# explicit permission to test. Remove any real targets when publishing.
#
# Requirements: curl, grep (with -P or -o), sed, awk, jq (optional but recommended)
# Usage examples:
#   chmod +x api_discovery_curl_v2.sh
#   ./api_discovery_curl_v2.sh -u https://example.com -w wordlist.txt
#   ./api_discovery_curl_v2.sh -u https://example.com -o ./outdir
#
# Author: Generated for you
# License: MIT

set -euo pipefail
IFS=$'\n\t'

# Default values
TARGET=""
WORDLIST=""
OUTDIR="./api_discovery_results"
TIMEOUT=10
VERBOSE=1
USER_AGENT="api-discovery-script/1.0 (+https://example.com)"

function usage() {
  cat <<EOF
Usage: $0 -u <target-url> [options]

Options:
  -u <url>       Target base URL (required). Example: https://example.com
  -w <file>      Wordlist file for fuzzing endpoints (one path per line)
  -o <dir>       Output directory (default: ./api_discovery_results)
  -t <seconds>   curl timeout in seconds (default: 10)
  -q             Quiet mode (less verbose)
  -h             Show this help

Examples:
  $0 -u https://example.com
  $0 -u https://example.com -w api-wordlist.txt -o ./results

Safety: only run against systems you have permission to test.
EOF
  exit 1
}

while getopts ":u:w:o:t:qh" opt; do
  case ${opt} in
    u) TARGET="$OPTARG" ;;
    w) WORDLIST="$OPTARG" ;;
    o) OUTDIR="$OPTARG" ;;
    t) TIMEOUT="$OPTARG" ;;
    q) VERBOSE=0 ;;
    h) usage ;;
    \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
    :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  echo "Error: target URL is required." >&2
  usage
fi

# Ensure TARGET has scheme
if ! echo "$TARGET" | grep -qE '^https?://'; then
  echo "Adding https:// to target"
  TARGET="https://$TARGET"
fi

# Create output directory
mkdir -p "$OUTDIR"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

function log() {
  if [[ $VERBOSE -eq 1 ]]; then
    echo "$@"
  fi
}

function check_deps() {
  local missing=()
  for cmd in curl grep sed awk jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -ne 0 ]]; then
    echo "Warning: missing commands: ${missing[*]}" >&2
    echo "Script will try to continue, but install jq and grep with -P support for best results." >&2
  fi
}

check_deps

# Helpers for curl
CURL_COMMON=( -s -L --max-time "$TIMEOUT" -A "$USER_AGENT" )

# Fetch robots.txt
function fetch_robots() {
  log "[+] Fetching robots.txt"
  curl "${CURL_COMMON[@]}" "$TARGET/robots.txt" -o "$OUTDIR/robots.txt" || true
  if [[ -s "$OUTDIR/robots.txt" ]]; then
    grep -Eo "(/[^[:space:]]+)" "$OUTDIR/robots.txt" | sort -u > "$OUTDIR/robots_paths.txt" || true
  fi
}

# Fetch sitemap.xml and parse
function fetch_sitemap() {
  log "[+] Fetching sitemap.xml"
  curl "${CURL_COMMON[@]}" "$TARGET/sitemap.xml" -o "$OUTDIR/sitemap.xml" || true
  if [[ -s "$OUTDIR/sitemap.xml" ]]; then
    grep -Eo "https?://[^\"]+" "$OUTDIR/sitemap.xml" | sort -u > "$OUTDIR/sitemap_urls.txt" || true
  fi
}

# Try common swagger/openapi endpoints
function fetch_swagger() {
  log "[+] Checking common OpenAPI/Swagger locations"
  local paths=(/swagger.json /swagger/v1/swagger.json /v2/api-docs /api-docs /openapi.json /openapi.yaml /api/openapi.json)
  for p in "${paths[@]}"; do
    url="$TARGET$p"
    log "    -> $url"
    curl "${CURL_COMMON[@]}" "$url" -o "$TMPDIR/swagger_tmp" || true
    if [[ -s "$TMPDIR/swagger_tmp" ]]; then
      # Try to pretty print JSON if possible
      if command -v jq >/dev/null 2>&1 && jq -e . "$TMPDIR/swagger_tmp" >/dev/null 2>&1; then
        jq . "$TMPDIR/swagger_tmp" > "$OUTDIR/$(echo "$p" | sed 's/\//_/g' | sed 's/_$//')_swagger.json' || true
      else
        cp "$TMPDIR/swagger_tmp" "$OUTDIR/$(echo "$p" | sed 's/\//_/g' | sed 's/_$//')_swagger' || true
      fi
    fi
  done
}

# Scrape JS files from homepage and extract candidate endpoints
function scan_js_for_endpoints() {
  log "[+] Scanning HTML and JS for endpoints"
  local homepage="$TARGET"
  curl "${CURL_COMMON[@]}" "$homepage" -o "$TMPDIR/home.html" || true
  # extract JS urls
  grep -Eo 'src=["'"']?[^ >]+' "$TMPDIR/home.html" 2>/dev/null | sed -E 's/src=//g' | tr -d '"' | tr -d "'" | grep -E "\.js(\?|$)|\.mjs(\?|$)" | sort -u > "$TMPDIR/js_urls.txt" || true

  # Resolve relative paths
  while read -r js; do
    if [[ -z "$js" ]]; then continue; fi
    if echo "$js" | grep -qE '^https?://'; then
      full="$js"
    elif echo "$js" | grep -qE '^/'; then
      full="$TARGET${js}"
    else
      # relative
      full="$TARGET/${js}"
    fi
    echo "$full"
  done < "$TMPDIR/js_urls.txt" | sort -u > "$TMPDIR/js_urls_resolved.txt" || true

  # Download and extract endpoints
  > "$OUTDIR/js_candidate_endpoints.txt"
  while read -r url; do
    log "    -> fetching $url"
    curl "${CURL_COMMON[@]}" "$url" -o "$TMPDIR/js.tmp" || true
    # Find patterns like /api/... or https://.../api/... or /graphql etc
    grep -Eo "(https?:\\/\\/[A-Za-z0-9._:/%?=&+-]+|\\/[A-Za-z0-9/_\\-\\.]+)" "$TMPDIR/js.tmp" 2>/dev/null |
      grep -E "(/api/|/v[0-9]+/|graphql|/rest/|/internal/|/backend/)" || true >> "$OUTDIR/js_candidate_endpoints.txt"
  done < "$TMPDIR/js_urls_resolved.txt"

  sort -u "$OUTDIR/js_candidate_endpoints.txt" -o "$OUTDIR/js_candidate_endpoints.txt" || true
}

# Simple wordlist fuzzing using curl
function fuzz_wordlist() {
  if [[ -z "$WORDLIST" || ! -f "$WORDLIST" ]]; then
    log "[!] No valid wordlist provided, skipping fuzzing. Pass -w wordlist.txt to enable."
    return
  fi
  log "[+] Fuzzing with wordlist: $WORDLIST"
  > "$OUTDIR/fuzz_results.txt"
  while read -r path; do
    # skip empty and comments
    [[ -z "$path" || "$path" =~ ^# ]] && continue
    # Build candidate URL
    if echo "$path" | grep -qE '^https?://'; then
      url="$path"
    elif echo "$path" | grep -qE '^/'; then
      url="$TARGET$path"
    else
      url="$TARGET/$path"
    fi
    # Send a HEAD then fallback to GET if HEAD not allowed
    code=$(curl -s -o /dev/null -w "%{http_code}" -I --max-time "$TIMEOUT" -A "$USER_AGENT" "$url" || echo "000")
    if [[ "$code" != "404" && "$code" != "000" ]]; then
      echo "[$code] $url" >> "$OUTDIR/fuzz_results.txt"
      log "    [FOUND] [$code] $url"
    fi
  done < "$WORDLIST"
  sort -u "$OUTDIR/fuzz_results.txt" -o "$OUTDIR/fuzz_results.txt" || true
}

# Check GraphQL endpoint and attempt introspection
function check_graphql() {
  log "[+] Checking for GraphQL endpoints"
  local candidates=("/graphql" "/graphiql" "/api/graphql")
  for p in "${candidates[@]}"; do
    url="$TARGET$p"
    log "    -> Testing $url"
    code=$(curl -s -o /dev/null -w "%{http_code}" -I --max-time "$TIMEOUT" -A "$USER_AGENT" "$url" || echo "000")
    if [[ "$code" == "200" || "$code" == "405" ]]; then
      # Try a POST introspection query
      resp=$(curl -s -X POST "$url" -H 'Content-Type: application/json' -d '{"query":"{__schema{types{name}}}'}' --max-time "$TIMEOUT" -A "$USER_AGENT" || true)
      if echo "$resp" | grep -q "__schema" || echo "$resp" | grep -q "data" ; then
        echo "[GraphQL introspection enabled] $url" >> "$OUTDIR/graphql_introspection.txt"
        echo "$resp" > "$OUTDIR/graphql_schema.json"
        log "    [GraphQL] Introspection successful: $url"
      else
        log "    [GraphQL] No introspection at $url"
      fi
    fi
  done
}

# Subdomain discovery via crt.sh (public, simple)
function subdomain_crtsh() {
  log "[+] Querying crt.sh for subdomains (may be rate limited)"
  # extract hostname only
  host=$(echo "$TARGET" | sed -E 's@https?://@@' | sed -E 's@/.*@@')
  if command -v jq >/dev/null 2>&1; then
    curl -s "https://crt.sh/?q=%25.$host&output=json" | jq -r '.[].name_value' | sed 's/\*\.//g' | sort -u > "$OUTDIR/crtsh_subdomains.txt" || true
  else
    curl -s "https://crt.sh/?q=%25.$host" | grep -Eo "[a-zA-Z0-9._-]+\.$host" | sort -u > "$OUTDIR/crtsh_subdomains.txt" || true
  fi
}

# Inspect headers for clues
function inspect_headers() {
  log "[+] Inspecting headers from target base URL"
  curl -s -D - -o /dev/null --max-time "$TIMEOUT" -A "$USER_AGENT" "$TARGET" > "$OUTDIR/headers.txt" || true
  # extract any link or location headers
  grep -Ei "link:|location:|api|x-powered-by|server" "$OUTDIR/headers.txt" || true
}

# Aggregate all candidate endpoints into a final list
function aggregate_results() {
  log "[+] Aggregating results"
  > "$OUTDIR/all_candidates.txt"
  for f in "$OUTDIR/js_candidate_endpoints.txt" "$OUTDIR/robots_paths.txt" "$OUTDIR/sitemap_urls.txt" "$OUTDIR/fuzz_results.txt" "$OUTDIR/crtsh_subdomains.txt"; do
    if [[ -f "$f" ]]; then
      cat "$f" >> "$OUTDIR/all_candidates.txt"
    fi
  done
  # normalize some entries
  sed -E 's/"|\'"'"//g' "$OUTDIR/all_candidates.txt" | sed 's/\s//g' | sort -u > "$OUTDIR/all_candidates_normalized.txt" || true
  log "[+] Results saved to $OUTDIR/all_candidates_normalized.txt"
}

# Main flow
fetch_robots
fetch_sitemap
fetch_swagger
scan_js_for_endpoints
fuzz_wordlist
check_graphql
subdomain_crtsh
inspect_headers
aggregate_results

log "\nAll done. Results directory: $OUTDIR"
log "Files of interest:"
log "  - $OUTDIR/all_candidates_normalized.txt    (all discovered endpoints)"
log "  - $OUTDIR/js_candidate_endpoints.txt      (from JS files)"
log "  - $OUTDIR/fuzz_results.txt                (wordlist fuzzing findings)"
log "  - $OUTDIR/sitemap_urls.txt                (urls from sitemap)"
log "  - $OUTDIR/robots.txt                      (robots.txt)"
log "  - $OUTDIR/crtsh_subdomains.txt            (subdomains discovered via crt.sh)"

exit 0
