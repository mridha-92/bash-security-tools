#!/bin/bash

# Configuration
CONCURRENT_LIMIT=10
TIMEOUT=5
DNS_SERVER="8.8.8.8"  # Google DNS

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print usage
usage() {
    echo "Usage: $0 [OPTIONS] <subdomains_file>"
    echo ""
    echo "Options:"
    echo "  -o, --output FILE     Output file (default: ips_<timestamp>.txt)"
    echo "  -t, --threads NUM     Number of concurrent threads (default: $CONCURRENT_LIMIT)"
    echo "  -d, --dns-server IP   DNS server to use (default: $DNS_SERVER)"
    echo "  -c, --csv             Output in CSV format (subdomain,ip)"
    echo "  -j, --json            Output in JSON format"
    echo "  -s, --summary         Show summary only (no detailed output)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 subdomains.txt"
    echo "  $0 -t 20 -o results.txt subdomains.txt"
    echo "  $0 -c -d 1.1.1.1 subdomains.txt"
}

# Check if dig is installed
check_dig() {
    if ! command -v dig &> /dev/null; then
        echo -e "${RED}Error: 'dig' command not found. Please install dnsutils/bind-tools${NC}" >&2
        exit 1
    fi
}

# Resolve a single subdomain
resolve_subdomain() {
    local subdomain="$1"
    local dns_server="$2"
    local timeout="$3"
    
    # Try to resolve A records
    ips=$(timeout "$timeout" dig +short "@$dns_server" "$subdomain" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
    
    # Also try CNAME resolution
    if [[ -z "$ips" ]]; then
        cname=$(timeout "$timeout" dig +short "@$dns_server" "$subdomain" CNAME 2>/dev/null)
        if [[ -n "$cname" ]]; then
            ips=$(timeout "$timeout" dig +short "@$dns_server" "$cname" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
        fi
    fi
    
    echo "$ips"
}

# Process subdomains in parallel
process_subdomains() {
    local input_file="$1"
    local output_file="$2"
    local csv_output="$3"
    local json_output="$4"
    local show_summary="$5"
    local dns_server="$6"
    local timeout="$7"
    
    local total=$(wc -l < "$input_file" 2>/dev/null || echo 0)
    local count=0
    local found=0
    local csv_data=""
    local json_data=""
    
    # Create temporary files
    tmp_output=$(mktemp)
    tmp_csv=$(mktemp)
    tmp_json=$(mktemp)
    
    # Initialize JSON if needed
    if [[ "$json_output" == "true" ]]; then
        echo "[" > "$tmp_json"
    fi
    
    # Process each subdomain
    while IFS= read -r subdomain || [[ -n "$subdomain" ]]; do
        # Remove leading/trailing whitespace and comments
        subdomain=$(echo "$subdomain" | sed 's/#.*//' | xargs)
        [[ -z "$subdomain" ]] && continue
        
        # Wait if we have too many concurrent processes
        while [[ $(jobs -r | wc -l) -ge $CONCURRENT_LIMIT ]]; do
            sleep 0.1
        done
        
        # Process in background
        {
            ips=$(resolve_subdomain "$subdomain" "$dns_server" "$timeout")
            
            if [[ -n "$ips" ]]; then
                # Write to output file
                echo "$ips" >> "$tmp_output"
                
                # Show progress if not in summary mode
                if [[ "$show_summary" != "true" ]]; then
                    echo -e "${GREEN}[+]${NC} $subdomain -> $(echo "$ips" | tr '\n' ' ')"
                fi
                
                # Prepare CSV data
                if [[ "$csv_output" == "true" ]]; then
                    echo "$ips" | while read -r ip; do
                        echo "\"$subdomain\",\"$ip\"" >> "$tmp_csv"
                    done
                fi
                
                # Prepare JSON data
                if [[ "$json_output" == "true" ]]; then
                    ips_array=$(echo "$ips" | awk '{printf "\"%s\",", $0}' | sed 's/,$//')
                    echo "  {\"subdomain\": \"$subdomain\", \"ips\": [$ips_array]}," >> "$tmp_json"
                fi
                
                ((found++))
            elif [[ "$show_summary" != "true" ]]; then
                echo -e "${RED}[-]${NC} $subdomain -> No IP found"
            fi
            
            # Update counter
            ((count++))
            if [[ "$show_summary" != "true" ]]; then
                echo -ne "${YELLOW}Progress: $count/$total${NC}\r" >&2
            fi
        } &
        
    done < "$input_file"
    
    # Wait for all background jobs to finish
    wait
    
    # Finalize JSON
    if [[ "$json_output" == "true" ]]; then
        # Remove trailing comma
        sed -i '$ s/,$//' "$tmp_json"
        echo "]" >> "$tmp_json"
    fi
    
    # Process results
    if [[ -s "$tmp_output" ]]; then
        # Sort and remove duplicates
        sort -u "$tmp_output" -o "$output_file"
        
        # Add CSV header if needed
        if [[ "$csv_output" == "true" ]]; then
            echo '"subdomain","ip"' > "${output_file%.*}.csv"
            sort -u "$tmp_csv" >> "${output_file%.*}.csv"
        fi
        
        # Save JSON if needed
        if [[ "$json_output" == "true" ]]; then
            cp "$tmp_json" "${output_file%.*}.json"
        fi
    fi
    
    # Cleanup
    rm -f "$tmp_output" "$tmp_csv" "$tmp_json"
    
    # Return statistics
    echo "$count $found"
}

main() {
    # Default values
    OUTPUT_FILE=""
    CONCURRENT_LIMIT=10
    DNS_SERVER="8.8.8.8"
    CSV_OUTPUT="false"
    JSON_OUTPUT="false"
    SHOW_SUMMARY="false"
    INPUT_FILE=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -t|--threads)
                CONCURRENT_LIMIT="$2"
                shift 2
                ;;
            -d|--dns-server)
                DNS_SERVER="$2"
                shift 2
                ;;
            -c|--csv)
                CSV_OUTPUT="true"
                shift
                ;;
            -j|--json)
                JSON_OUTPUT="true"
                shift
                ;;
            -s|--summary)
                SHOW_SUMMARY="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                echo -e "${RED}Error: Unknown option $1${NC}" >&2
                usage
                exit 1
                ;;
            *)
                INPUT_FILE="$1"
                shift
                ;;
        esac
    done
    
    # Check input file
    if [[ -z "$INPUT_FILE" ]]; then
        echo -e "${RED}Error: No input file specified${NC}" >&2
        usage
        exit 1
    fi
    
    if [[ ! -f "$INPUT_FILE" ]]; then
        echo -e "${RED}Error: Input file '$INPUT_FILE' not found${NC}" >&2
        exit 1
    fi
    
    # Set default output file if not specified
    if [[ -z "$OUTPUT_FILE" ]]; then
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        if [[ "$CSV_OUTPUT" == "true" ]]; then
            OUTPUT_FILE="ips_${TIMESTAMP}.csv"
        elif [[ "$JSON_OUTPUT" == "true" ]]; then
            OUTPUT_FILE="ips_${TIMESTAMP}.json"
        else
            OUTPUT_FILE="ips_${TIMESTAMP}.txt"
        fi
    fi
    
    # Check for dig
    check_dig
    
    # Show banner
    if [[ "$SHOW_SUMMARY" != "true" ]]; then
        echo -e "${GREEN}Subdomains to IPs Extractor${NC}"
        echo "================================"
        echo "Input file:    $INPUT_FILE"
        echo "Output file:   $OUTPUT_FILE"
        echo "DNS server:    $DNS_SERVER"
        echo "Threads:       $CONCURRENT_LIMIT"
        echo "Timeout:       ${TIMEOUT}s"
        echo "================================"
        echo ""
    fi
    
    # Process subdomains
    stats=$(process_subdomains "$INPUT_FILE" "$OUTPUT_FILE" "$CSV_OUTPUT" "$JSON_OUTPUT" "$SHOW_SUMMARY" "$DNS_SERVER" "$TIMEOUT")
    processed=$(echo "$stats" | awk '{print $1}')
    found=$(echo "$stats" | awk '{print $2}')
    
    # Show summary
    echo ""
    echo -e "${GREEN}Summary:${NC}"
    echo "  Subdomains processed: $processed"
    echo "  Subdomains with IPs:  $found"
    
    if [[ -f "$OUTPUT_FILE" ]]; then
        if [[ "$CSV_OUTPUT" == "true" ]] && [[ -f "${OUTPUT_FILE%.*}.csv" ]]; then
            echo "  Unique IPs found:    $(tail -n +2 "${OUTPUT_FILE%.*}.csv" | cut -d',' -f2 | sort -u | wc -l)"
            echo "  CSV output:          ${OUTPUT_FILE%.*}.csv"
        elif [[ "$JSON_OUTPUT" == "true" ]] && [[ -f "${OUTPUT_FILE%.*}.json" ]]; then
            echo "  JSON output:         ${OUTPUT_FILE%.*}.json"
        else
            echo "  Unique IPs found:    $(wc -l < "$OUTPUT_FILE")"
            echo "  Results saved to:    $OUTPUT_FILE"
        fi
    else
        echo -e "${YELLOW}No IP addresses found.${NC}"
    fi
}

# Handle script interrupt
trap 'echo -e "\n${YELLOW}Interrupted. Cleaning up...${NC}"; exit 1' INT

main "$@"