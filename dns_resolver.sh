#!/bin/bash

# =============================================================================
# DNS Resolution Script
# 
# A comprehensive tool to identify the origin IP address of domains and URLs.
# Supports both IPv4 and IPv6 resolution with configurable timeouts and retries.
#
# Usage: ./dns_resolver.sh <domain_or_url> [options]
# =============================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Default configuration
DEFAULT_TIMEOUT=5
DEFAULT_RETRIES=2
RESOLVE_IPV4=true
RESOLVE_IPV6=false
VERBOSE=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage information
usage() {
    cat << EOF
Usage: $0 <domain_or_url> [OPTIONS]

OPTIONS:
    -4              Resolve IPv4 only (default)
    -6              Resolve IPv6 only
    -b              Resolve both IPv4 and IPv6
    -t <seconds>    Set timeout for DNS queries (default: $DEFAULT_TIMEOUT)
    -r <number>     Set number of retries (default: $DEFAULT_RETRIES)
    -v              Verbose output
    -h              Show this help message

EXAMPLES:
    $0 example.com
    $0 https://www.example.com/path -6
    $0 example.com -b -t 10 -r 3
EOF
}

# Function to log verbose messages
log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[VERBOSE]${NC} $*" >&2
    fi
}

# Function to extract domain from URL
extract_domain() {
    local input="$1"
    local domain
    
    # Remove protocol prefix (http://, https://, ftp://, etc.)
    domain=$(echo "$input" | sed -E 's|^[a-zA-Z]+://||')
    
    # Remove path and query parameters
    domain=$(echo "$domain" | sed 's|/.*$||')
    
    # Remove port number if present
    domain=$(echo "$domain" | sed 's|:[0-9]*$||')
    
    echo "$domain"
}

# Function to validate if input is a valid domain or URL
validate_input() {
    local input="$1"
    
    # Basic validation - should contain at least one dot and valid characters
    if [[ ! "$input" =~ ^[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$ ]] && 
       [[ ! "$input" =~ ^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$ ]]; then
        echo -e "${RED}Error: Invalid domain or URL format: $input${NC}" >&2
        return 1
    fi
    
    return 0
}

# Function to check if required tools are available
check_dependencies() {
    local missing_tools=()
    
    # Check for dig (preferred) or nslookup
    if ! command -v dig &> /dev/null; then
        log_verbose "dig not found, checking for nslookup..."
        if ! command -v nslookup &> /dev/null; then
            missing_tools+=("dig or nslookup")
        fi
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo -e "${RED}Error: Missing required tools: ${missing_tools[*]}${NC}" >&2
        echo "Please install the required packages:" >&2
        echo "  Ubuntu/Debian: sudo apt-get install dnsutils" >&2
        echo "  RHEL/CentOS: sudo yum install bind-utils" >&2
        return 1
    fi
    
    log_verbose "All required tools are available"
    return 0
}

# Function to resolve IP addresses using dig (preferred)
resolve_with_dig() {
    local domain="$1"
    local query_type="$2"
    local timeout="$3"
    local retries="$4"
    local results=()
    
    log_verbose "Resolving $query_type records for $domain using dig"
    
    # Use timeout command to enforce timeout
    if result=$(timeout "$timeout" dig +short +tries="$retries" "$query_type" "$domain" 2>/dev/null); then
        while IFS= read -r line; do
            if [ -n "$line" ]; then
                results+=("$line")
            fi
        done <<< "$result"
    fi
    
    printf '%s\n' "${results[@]}"
}

# Function to resolve IP addresses using nslookup (fallback)
resolve_with_nslookup() {
    local domain="$1"
    local query_type="$2"
    local timeout="$3"
    local results=()
    
    log_verbose "Resolving $query_type records for $domain using nslookup"
    
    # nslookup doesn't have built-in timeout/retry options, so we rely on system timeout
    if result=$(timeout "$timeout" nslookup -type="$query_type" "$domain" 2>/dev/null | grep -E "^Address: [0-9]" | awk '{print $2}'); then
        while IFS= read -r line; do
            if [ -n "$line" ] && [ "$line" != "127.0.0.1" ]; then
                results+=("$line")
            fi
        done <<< "$result"
    fi
    
    printf '%s\n' "${results[@]}"
}

# Function to perform DNS resolution
resolve_domain() {
    local domain="$1"
    local timeout="$2"
    local retries="$3"
    local ipv4_results=()
    local ipv6_results=()
    
    # Choose resolution method
    if command -v dig &> /dev/null; then
        RESOLVE_CMD="resolve_with_dig"
    else
        RESOLVE_CMD="resolve_with_nslookup"
    fi
    
    # Resolve IPv4 addresses if requested
    if [ "$RESOLVE_IPV4" = true ]; then
        log_verbose "Resolving IPv4 addresses (A records)"
        mapfile -t ipv4_results < <($RESOLVE_CMD "$domain" "A" "$timeout" "$retries")
    fi
    
    # Resolve IPv6 addresses if requested
    if [ "$RESOLVE_IPV6" = true ]; then
        log_verbose "Resolving IPv6 addresses (AAAA records)"
        mapfile -t ipv6_results < <($RESOLVE_CMD "$domain" "AAAA" "$timeout" "$retries")
    fi
    
    # Return results
    echo "IPV4:${ipv4_results[*]:-NONE}"
    echo "IPV6:${ipv6_results[*]:-NONE}"
}

# Function to display results in user-friendly format
display_results() {
    local domain="$1"
    local ipv4_results="$2"
    local ipv6_results="$3"
    
    echo
    echo -e "${GREEN}DNS Resolution Results for: $domain${NC}"
    echo "=========================================="
    
    if [ "$RESOLVE_IPV4" = true ]; then
        if [ "$ipv4_results" != "NONE" ]; then
            IFS=' ' read -ra ipv4_ips <<< "$ipv4_results"
            for ip in "${ipv4_ips[@]}"; do
                echo -e "IPv4 Address: ${YELLOW}$ip${NC}"
            done
        else
            echo -e "${RED}No IPv4 addresses found${NC}"
        fi
    fi
    
    if [ "$RESOLVE_IPV6" = true ]; then
        if [ "$ipv6_results" != "NONE" ]; then
            IFS=' ' read -ra ipv6_ips <<< "$ipv6_results"
            for ip in "${ipv6_ips[@]}"; do
                echo -e "IPv6 Address: ${YELLOW}$ip${NC}"
            done
        else
            echo -e "${RED}No IPv6 addresses found${NC}"
        fi
    fi
    
    # Show primary/origin IP
    if [ "$ipv4_results" != "NONE" ] && [ "$RESOLVE_IPV4" = true ]; then
        IFS=' ' read -ra ipv4_ips <<< "$ipv4_results"
        echo
        echo -e "${GREEN}The origin IP address of $domain is: ${YELLOW}${ipv4_ips[0]}${NC}"
    elif [ "$ipv6_results" != "NONE" ] && [ "$RESOLVE_IPV6" = true ]; then
        IFS=' ' read -ra ipv6_ips <<< "$ipv6_results"
        echo
        echo -e "${GREEN}The origin IP address of $domain is: ${YELLOW}${ipv6_ips[0]}${NC}"
    else
        echo
        echo -e "${RED}Could not resolve any IP addresses for: $domain${NC}"
    fi
}

# Main execution function
main() {
    local input_domain=""
    local timeout=$DEFAULT_TIMEOUT
    local retries=$DEFAULT_RETRIES
    
    # Parse command line arguments
    while getopts "46bt:r:vh" opt; do
        case $opt in
            4)
                RESOLVE_IPV4=true
                RESOLVE_IPV6=false
                ;;
            6)
                RESOLVE_IPV4=false
                RESOLVE_IPV6=true
                ;;
            b)
                RESOLVE_IPV4=true
                RESOLVE_IPV6=true
                ;;
            t)
                timeout="$OPTARG"
                ;;
            r)
                retries="$OPTARG"
                ;;
            v)
                VERBOSE=true
                ;;
            h)
                usage
                exit 0
                ;;
            \?)
                echo -e "${RED}Invalid option: -$OPTARG${NC}" >&2
                usage
                exit 1
                ;;
        esac
    done
    
    shift $((OPTIND - 1))
    
    # Check if domain argument is provided
    if [ $# -eq 0 ]; then
        echo -e "${RED}Error: No domain or URL specified${NC}" >&2
        usage
        exit 1
    fi
    
    input_domain="$1"
    
    # Validate input
    if ! validate_input "$input_domain"; then
        exit 1
    fi
    
    # Extract domain from URL if necessary
    domain=$(extract_domain "$input_domain")
    log_verbose "Input: $input_domain, Extracted domain: $domain"
    
    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi
    
    # Validate timeout and retries are positive numbers
    if ! [[ "$timeout" =~ ^[0-9]+$ ]] || [ "$timeout" -le 0 ]; then
        echo -e "${RED}Error: Timeout must be a positive integer${NC}" >&2
        exit 1
    fi
    
    if ! [[ "$retries" =~ ^[0-9]+$ ]] || [ "$retries" -le 0 ]; then
        echo -e "${RED}Error: Retries must be a positive integer${NC}" >&2
        exit 1
    fi
    
    log_verbose "Configuration: timeout=${timeout}s, retries=$retries, IPv4=$RESOLVE_IPV4, IPv6=$RESOLVE_IPV6"
    
    # Perform DNS resolution
    log_verbose "Starting DNS resolution..."
    mapfile -t resolution_results < <(resolve_domain "$domain" "$timeout" "$retries")
    
    # Parse results
    ipv4_results=""
    ipv6_results=""
    
    for result in "${resolution_results[@]}"; do
        if [[ "$result" == IPV4:* ]]; then
            ipv4_results="${result#IPV4:}"
        elif [[ "$result" == IPV6:* ]]; then
            ipv6_results="${result#IPV6:}"
        fi
    done
    
    # Display results
    display_results "$domain" "$ipv4_results" "$ipv6_results"
}

# Execute main function with all arguments
main "$@"
