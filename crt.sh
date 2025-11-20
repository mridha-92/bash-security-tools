#!/bin/bash

# =============================================
# CRT.SH All-in-One Bash Client
# Complete certificate search tool for crt.sh
# =============================================

VERSION="2.0"
SCRIPT_NAME="${0##*/}"
BASE_URL="https://crt.sh/"
USER_AGENT="CRT.sh-All-in-One/$VERSION"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
OUTPUT_FORMAT="table"
LIMIT=50
INCLUDE_EXPIRED=false
EXACT_MATCH=false
RAW_JSON=false
VERBOSE=false
BATCH_MODE=false
BATCH_DELAY=1

# Temporary files
TEMP_DIR="/tmp/crt-sh-$$"
TEMP_RESULTS="$TEMP_DIR/results.json"

# Cleanup function
cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Trap signals for cleanup
trap cleanup EXIT INT TERM

# Create temp directory
mkdir -p "$TEMP_DIR"

# Help function
show_help() {
    cat << EOF
${GREEN}CRT.SH All-in-One Bash Client${NC}
Query SSL certificates from crt.sh directly from your terminal

${YELLOW}USAGE:${NC}
  $SCRIPT_NAME [OPTIONS] <query>
  $SCRIPT_NAME [OPTIONS] -B <file> [batch_options]

${YELLOW}QUERY TYPES:${NC}
  <domain>                 Search by domain (default)
  -d, --domain <domain>    Search by domain name
  -o, --org <organization> Search by organization  
  -i, --id <cert_id>       Search by certificate ID
  -s, --serial <serial>    Search by certificate serial

${YELLOW}SEARCH OPTIONS:${NC}
  -e, --exact              Exact domain match only
  -x, --expired            Include expired certificates
  -l, --limit <number>     Limit results (default: 50)
  -f, --format <format>    Output: table, json, csv, list, domains (default: table)
  -r, --raw                Raw JSON output from API
  -v, --verbose            Verbose output

${YELLOW}BATCH PROCESSING:${NC}
  -B, --batch <file>       Batch process domains from file
  -D, --delay <seconds>    Delay between requests (default: 1)
  -O, --output-dir <dir>   Output directory for batch results

${YELLOW}OTHER OPTIONS:${NC}
  -h, --help               Show this help message
  -V, --version            Show version information
  --install                Install to /usr/local/bin

${YELLOW}EXAMPLES:${NC}
  ${SCRIPT_NAME} example.com
  ${SCRIPT_NAME} -d example.com -e -f json
  ${SCRIPT_NAME} -d example.com -l 10 -f csv
  ${SCRIPT_NAME} -o "Let's Encrypt" -l 5
  ${SCRIPT_NAME} -i 123456789
  ${SCRIPT_NAME} -B domains.txt -O ./results -D 2
  ${SCRIPT_NAME} --install

${YELLOW}BATCH FILE FORMAT:${NC}
  # Comment lines start with #
  google.com
  github.com
  # This is a comment
  microsoft.com
EOF
}

# Version function
show_version() {
    echo -e "${GREEN}CRT.SH All-in-One Bash Client v$VERSION${NC}"
    echo "License: MIT"
    echo "Author: Command Line Tool"
}

# Installation function
install_script() {
    local target_dir="/usr/local/bin"
    local target_name="crt-sh"
    
    echo -e "${YELLOW}Installing CRT.SH client...${NC}"
    
    if [[ ! -d "$target_dir" ]]; then
        echo "Creating $target_dir..."
        sudo mkdir -p "$target_dir"
    fi
    
    # Get the absolute path of this script
    local script_path
    if [[ -f "$0" ]]; then
        script_path="$(realpath "$0")"
    else
        # Fallback for when script is sourced
        script_path="./${SCRIPT_NAME}"
    fi
    
    if sudo cp "$script_path" "$target_dir/$target_name" && sudo chmod +x "$target_dir/$target_name"; then
        echo -e "${GREEN}Successfully installed to $target_dir/$target_name${NC}"
        echo -e "${CYAN}Usage: $target_name example.com${NC}"
    else
        echo -e "${RED}Installation failed!${NC}"
        return 1
    fi
}

# Error handling
error_exit() {
    echo -e "${RED}Error: $1${NC}" >&2
    cleanup
    exit 1
}

# Warning function
warning() {
    echo -e "${YELLOW}Warning: $1${NC}" >&2
}

# Info function
info() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}Info: $1${NC}" >&2
    fi
}

# Check dependencies
check_dependencies() {
    local deps=("curl" "jq")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error_exit "Missing dependencies: ${missing[*]}. Please install them first."
    fi
    
    # Optional dependencies
    if ! command -v "column" &> /dev/null; then
        warning "'column' command not found. Table formatting might be degraded."
    fi
}

# Make HTTP request to crt.sh
http_request() {
    local params="$1"
    local url="${BASE_URL}?${params}&output=json"
    
    info "Querying: $url"
    
    local response
    response=$(curl -s -A "$USER_AGENT" --connect-timeout 30 --max-time 60 "$url" 2>"$TEMP_DIR/curl_error")
    
    local curl_exit=$?
    
    if [[ $curl_exit -ne 0 ]]; then
        local error_msg
        error_msg=$(cat "$TEMP_DIR/curl_error")
        error_exit "Network error: $error_msg"
    fi
    
    if [[ -z "$response" ]]; then
        error_exit "Empty response from server"
    fi
    
    echo "$response"
}

# Query domain
query_domain() {
    local domain="$1"
    local params="q=$domain"
    
    if [[ "$EXACT_MATCH" == "true" ]]; then
        params="q=%25.$domain"
    fi
    
    if [[ "$INCLUDE_EXPIRED" != "true" ]]; then
        params="$params&exclude=expired"
    fi
    
    http_request "$params"
}

# Query organization
query_organization() {
    local org="$1"
    local params="O=$(echo "$org" | sed 's/ /%20/g')"
    
    if [[ "$INCLUDE_EXPIRED" != "true" ]]; then
        params="$params&exclude=expired"
    fi
    
    http_request "$params"
}

# Query certificate by ID
query_certificate_id() {
    local cert_id="$1"
    http_request "id=$cert_id"
}

# Query certificate by serial
query_certificate_serial() {
    local serial="$1"
    http_request "serial=$serial"
}

# Validate JSON and check if results are empty
validate_results() {
    local json_data="$1"
    
    if ! echo "$json_data" | jq -e . >/dev/null 2>&1; then
        error_exit "Invalid JSON response from server"
    fi
    
    local result_count
    result_count=$(echo "$json_data" | jq 'length')
    
    if [[ "$result_count" -eq 0 ]]; then
        echo -e "${YELLOW}No certificates found.${NC}" >&2
        return 1
    fi
    
    info "Found $result_count certificate(s)"
    return 0
}

# Format table output
format_table() {
    local json_data="$1"
    
    echo "$json_data" | jq -r '
    ["ID", "Name Value", "Common Name", "Not Before", "Not After", "Issuer"],
    (.[] | [
        .id // "N/A",
        (.name_value | if . then split("\n") | first else "N/A" end),
        .common_name // "N/A",
        (.not_before // "N/A" | fromdateiso8601? // . | strftime("%Y-%m-%d")),
        (.not_after // "N/A" | fromdateiso8601? // . | strftime("%Y-%m-%d")),
        (.issuer_name // "N/A" | split(",")[0] | split("=")[1] // .)
    ]) | @tsv
    ' | column -t -s $'\t' 2>/dev/null || \
    echo "$json_data" | jq -r '
    ["ID", "Name Value", "Common Name", "Not Before", "Not After", "Issuer"],
    (.[] | [
        .id // "N/A",
        (.name_value | if . then split("\n") | first else "N/A" end),
        .common_name // "N/A",
        .not_before // "N/A",
        .not_after // "N/A",
        (.issuer_name // "N/A" | split(",")[0] | split("=")[1] // .)
    ]) | @tsv
    '
}

# Format CSV output
format_csv() {
    local json_data="$1"
    
    echo "$json_data" | jq -r '
    ["id", "name_value", "common_name", "not_before", "not_after", "issuer_name"],
    (.[] | [
        .id // "",
        .name_value // "",
        .common_name // "",
        .not_before // "",
        .not_after // "",
        .issuer_name // ""
    ]) | @csv
    '
}

# Format list output
format_list() {
    local json_data="$1"
    
    echo "$json_data" | jq -r '.[] | "\(.id // "N/A")\t\(.name_value // "N/A")\t\(.common_name // "N/A")\t\(.not_before // "N/A")\t\(.not_after // "N/A")"' | 
    column -t -s $'\t' 2>/dev/null
}

# Format domains only output
format_domains() {
    local json_data="$1"
    
    echo "$json_data" | jq -r '.[] | .name_value // empty' | tr ',' '\n' | sed 's/^\s*//;s/\s*$//' | grep -v '^$' | sort -u
}

# Process and format output
process_output() {
    local json_data="$1"
    
    if ! validate_results "$json_data"; then
        return 1
    fi
    
    # Apply limit
    if [[ "$LIMIT" -gt 0 ]]; then
        json_data=$(echo "$json_data" | jq ".[:$LIMIT]")
    fi
    
    if [[ "$RAW_JSON" == "true" ]]; then
        echo "$json_data" | jq '.'
        return 0
    fi
    
    case "$OUTPUT_FORMAT" in
        json)
            echo "$json_data" | jq '.'
            ;;
        csv)
            format_csv "$json_data"
            ;;
        list)
            format_list "$json_data"
            ;;
        domains)
            format_domains "$json_data"
            ;;
        table|*)
            format_table "$json_data"
            ;;
    esac
}

# Batch processing function
batch_process() {
    local input_file="$1"
    local output_dir="${2:-./crt-sh-results}"
    local delay="$BATCH_DELAY"
    
    if [[ ! -f "$input_file" ]]; then
        error_exit "Batch file not found: $input_file"
    fi
    
    mkdir -p "$output_dir"
    
    local total_domains=0
    local processed=0
    
    # Count total domains
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | sed 's/^\s*//;s/\s*$//')
        [[ -z "$line" || "$line" == \#* ]] && continue
        ((total_domains++))
    done < "$input_file"
    
    echo -e "${CYAN}Batch processing $total_domains domains...${NC}"
    echo -e "${CYAN}Output directory: $output_dir${NC}"
    echo -e "${CYAN}Delay between requests: ${delay}s${NC}"
    echo
    
    # Process each domain
    while IFS= read -r domain || [[ -n "$domain" ]]; do
        domain=$(echo "$domain" | sed 's/^\s*//;s/\s*$//')
        
        # Skip empty lines and comments
        [[ -z "$domain" || "$domain" == \#* ]] && continue
        
        ((processed++))
        echo -e "${BLUE}[$processed/$total_domains] Processing: $domain${NC}"
        
        # Query the domain
        local results
        results=$(query_domain "$domain")
        
        if [[ $? -eq 0 ]] && validate_results "$results"; then
            # Save JSON results
            echo "$results" | jq '.' > "$output_dir/${domain}.json"
            
            # Save CSV results
            format_csv "$results" > "$output_dir/${domain}.csv"
            
            # Save domains list
            format_domains "$results" > "$output_dir/${domain}-domains.txt"
            
            local result_count
            result_count=$(echo "$results" | jq 'length')
            echo -e "  ${GREEN}✓ Found $result_count certificates${NC}"
        else
            echo -e "  ${RED}✗ No results found${NC}"
            # Create empty files to indicate processing occurred
            touch "$output_dir/${domain}.json"
            touch "$output_dir/${domain}.csv" 
            touch "$output_dir/${domain}-domains.txt"
        fi
        
        # Delay between requests
        if [[ $processed -lt $total_domains ]]; then
            info "Waiting ${delay}s before next request..."
            sleep "$delay"
        fi
        
    done < "$input_file"
    
    echo
    echo -e "${GREEN}Batch processing complete!${NC}"
    echo -e "Results saved to: $output_dir"
}

# Main function
main() {
    local query_type="domain"
    local query_value=""
    local batch_file=""
    local output_dir="./crt-sh-results"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--domain)
                query_type="domain"
                query_value="$2"
                shift 2
                ;;
            -o|--org)
                query_type="organization" 
                query_value="$2"
                shift 2
                ;;
            -i|--id)
                query_type="certificate_id"
                query_value="$2"
                shift 2
                ;;
            -s|--serial)
                query_type="certificate_serial"
                query_value="$2"
                shift 2
                ;;
            -e|--exact)
                EXACT_MATCH=true
                shift
                ;;
            -x|--expired)
                INCLUDE_EXPIRED=true
                shift
                ;;
            -l|--limit)
                LIMIT="$2"
                shift 2
                ;;
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -r|--raw)
                RAW_JSON=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -B|--batch)
                BATCH_MODE=true
                batch_file="$2"
                shift 2
                ;;
            -D|--delay)
                BATCH_DELAY="$2"
                shift 2
                ;;
            -O|--output-dir)
                output_dir="$2"
                shift 2
                ;;
            --install)
                install_script
                exit 0
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -V|--version)
                show_version
                exit 0
                ;;
            -*)
                error_exit "Unknown option: $1"
                ;;
            *)
                # If no specific type provided, assume domain
                if [[ -z "$query_value" ]]; then
                    query_value="$1"
                fi
                shift
                ;;
        esac
    done
    
    # Check dependencies
    check_dependencies
    
    # Handle batch mode
    if [[ "$BATCH_MODE" == "true" ]]; then
        if [[ -z "$batch_file" ]]; then
            error_exit "Batch file required when using --batch"
        fi
        batch_process "$batch_file" "$output_dir"
        exit 0
    fi
    
    # Validate single query mode
    if [[ -z "$query_value" ]]; then
        show_help
        error_exit "No query specified"
    fi
    
    if [[ "$LIMIT" -lt 1 ]]; then
        error_exit "Limit must be a positive number"
    fi
    
    # Perform query
    info "Querying crt.sh for ${query_type}: ${query_value}"
    
    local result=""
    case "$query_type" in
        domain)
            result=$(query_domain "$query_value")
            ;;
        organization)
            result=$(query_organization "$query_value")
            ;;
        certificate_id)
            result=$(query_certificate_id "$query_value")
            ;;
        certificate_serial)
            result=$(query_certificate_serial "$query_value")
            ;;
    esac
    
    # Process and display results
    process_output "$result"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi