#!/bin/bash

# Information Disclosure Vulnerability Finder
# Author: Cybersecurity Expert
# Version: 1.0
# Description: Advanced tool for detecting information disclosure vulnerabilities
# Usage: ./vuln_finder.sh <URL or file_with_endpoints>

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}"
echo "=================================================="
echo "   Information Disclosure Vulnerability Finder   "
echo "           Ethical Hacking Tool v1.0            "
echo "=================================================="
echo -e "${NC}"

# Configuration variables
TIMEOUT=10
USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"
MAX_REDIRECTS=5
OUTPUT_FILE="disclosure_findings_$(date +%Y%m%d_%H%M%S).txt"

# Common information disclosure patterns
declare -a PATTERNS=(
    "API_KEY"
    "api_key"
    "SECRET"
    "secret"
    "PASSWORD"
    "password"
    "TOKEN"
    "token"
    "AWS_ACCESS_KEY"
    "aws_access_key_id"
    "PRIVATE_KEY"
    "private.key"
    "DATABASE_URL"
    "database.password"
    "CONNECTION_STRING"
    "Authorization:"
    "X-API-KEY"
    "ssh-rsa"
    "BEGIN RSA PRIVATE KEY"
    "BEGIN PRIVATE KEY"
)

# Common sensitive file extensions
declare -a SENSITIVE_FILES=(
    ".env"
    ".git/config"
    ".htpasswd"
    ".aws/credentials"
    "config/database.yml"
    "web.config"
    "phpinfo.php"
    "server-status"
    "backup.zip"
    "dump.sql"
    "traversaldemo.txt"
)

# Common sensitive directories
declare -a SENSITIVE_DIRS=(
    "/.git/"
    "/backup/"
    "/admin/"
    "/config/"
    "/database/"
    "/logs/"
    "/tmp/"
    "/cache/"
    "/private/"
)

# Function to display usage
usage() {
    echo -e "${YELLOW}Usage:${NC}"
    echo "  ./vuln_finder.sh <target>"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  ./vuln_finder.sh https://example.com"
    echo "  ./vuln_finder.sh endpoints.txt"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo "  <target>    Single URL or file containing list of endpoints"
    echo ""
    echo -e "${YELLOW}Output:${NC}"
    echo "  Results saved to: disclosure_findings_<timestamp>.txt"
    echo ""
    echo -e "${RED}IMPORTANT: Use responsibly and only on authorized targets${NC}"
}

# Function to check if required tools are available
check_dependencies() {
    local deps=("curl" "grep" "sed")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${RED}[ERROR] Required tool '$dep' not found. Please install it.${NC}"
            exit 1
        fi
    done
    echo -e "${GREEN}[INFO] All dependencies satisfied${NC}"
}

# Function to normalize URL
normalize_url() {
    local url="$1"
    # Remove trailing slash
    url="${url%/}"
    # Ensure it starts with http:// or https://
    if [[ ! "$url" =~ ^https?:// ]]; then
        url="https://$url"
    fi
    echo "$url"
}

# Function to test a single endpoint for information disclosure
test_endpoint() {
    local url="$1"
    local output_file="$2"
    
    echo -e "${BLUE}[TESTING]${NC} $url"
    
    # Make the request with appropriate headers and follow redirects
    response=$(curl -s -L --max-redirs $MAX_REDIRECTS \
        -H "User-Agent: $USER_AGENT" \
        -w "\\n%{http_code}\\n%{content_type}" \
        --connect-timeout $TIMEOUT \
        "$url" 2>/dev/null)
    
    # Extract status code and content type
    status_code=$(echo "$response" | tail -2 | head -1)
    content_type=$(echo "$response" | tail -1)
    content=$(echo "$response" | head -n -2)
    
    # Check for common information disclosure indicators
    local found_vulnerability=false
    
    # Test 1: Check status code (2xx generally means accessible)
    if [[ "$status_code" =~ ^2[0-9][0-9]$ ]]; then
        # Test 2: Check for sensitive patterns in content
        for pattern in "${PATTERNS[@]}"; do
            if echo "$content" | grep -q -i "$pattern"; then
                echo -e "${RED}[DISCLOSURE]${NC} Sensitive pattern '$pattern' found in: $url" | tee -a "$output_file"
                found_vulnerability=true
            fi
        done
        
        # Test 3: Check for error messages that might leak information
        if echo "$content" | grep -q -i -E "(error|exception|stack trace|debug|warning):"; then
            echo -e "${YELLOW}[WARNING]${NC} Potential error information disclosure in: $url" | tee -a "$output_file"
            found_vulnerability=true
        fi
        
        # Test 4: Check for directory listing
        if echo "$content" | grep -q -i -E "(index of|parent directory|directory listing)"; then
            echo -e "${RED}[DISCLOSURE]${NC} Directory listing enabled: $url" | tee -a "$output_file"
            found_vulnerability=true
        fi
    fi
    
    # Test 5: Check for backup files (common extensions)
    if [[ "$status_code" =~ ^2[0-9][0-9]$ ]] || [[ "$status_code" =~ ^3[0-9][0-9]$ ]]; then
        for file in "${SENSITIVE_FILES[@]}"; do
            if [[ "$url" == *"$file"* ]]; then
                echo -e "${RED}[DISCLOSURE]${NC} Sensitive file accessible: $url" | tee -a "$output_file"
                found_vulnerability=true
                break
            fi
        done
    fi
    
    if [[ "$found_vulnerability" == false ]]; then
        echo -e "${GREEN}[SAFE]${NC} No obvious information disclosure found: $url"
    fi
}

# Function to test common sensitive paths
test_sensitive_paths() {
    local base_url="$1"
    local output_file="$2"
    
    echo -e "${YELLOW}[INFO] Testing common sensitive paths...${NC}"
    
    # Test sensitive files
    for file in "${SENSITIVE_FILES[@]}"; do
        test_endpoint "${base_url}/${file}" "$output_file"
    done
    
    # Test sensitive directories
    for dir in "${SENSITIVE_DIRS[@]}"; do
        test_endpoint "${base_url}${dir}" "$output_file"
    done
}

# Function to process single URL
process_single_url() {
    local url="$1"
    local output_file="$2"
    
    url=$(normalize_url "$url")
    
    echo -e "${GREEN}[STARTING]${NC} Scanning single URL: $url"
    echo -e "${YELLOW}[INFO]${NC} Output will be saved to: $output_file"
    
    # Test the main URL first
    test_endpoint "$url" "$output_file"
    
    # Test common sensitive paths
    test_sensitive_paths "$url" "$output_file"
}

# Function to process file with endpoints
process_endpoint_file() {
    local file="$1"
    local output_file="$2"
    
    if [[ ! -f "$file" ]]; then
        echo -e "${RED}[ERROR] File '$file' not found${NC}"
        exit 1
    fi
    
    local count=0
    while IFS= read -r endpoint || [[ -n "$endpoint" ]]; do
        # Skip empty lines and comments
        if [[ -z "$endpoint" || "$endpoint" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Remove leading/trailing whitespace
        endpoint=$(echo "$endpoint" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Test the endpoint
        test_endpoint "$endpoint" "$output_file"
        
        ((count++))
    done < "$file"
    
    echo -e "${GREEN}[COMPLETED]${NC} Processed $count endpoints"
}

# Main function
main() {
    # Check if target is provided
    if [[ $# -ne 1 ]]; then
        echo -e "${RED}[ERROR] No target specified${NC}"
        usage
        exit 1
    fi
    
    local target="$1"
    
    # Check dependencies
    check_dependencies
    
    # Create output file
    touch "$OUTPUT_FILE"
    echo "# Information Disclosure Scan Results" > "$OUTPUT_FILE"
    echo "# Date: $(date)" >> "$OUTPUT_FILE"
    echo "# Target: $target" >> "$OUTPUT_FILE"
    echo "==========================================" >> "$OUTPUT_FILE"
    
    # Determine if target is URL or file
    if [[ -f "$target" ]]; then
        echo -e "${GREEN}[MODE]${NC} Batch processing from file: $target"
        process_endpoint_file "$target" "$OUTPUT_FILE"
    else
        echo -e "${GREEN}[MODE]${NC} Single URL scanning: $target"
        process_single_url "$target" "$OUTPUT_FILE"
    fi
    
    # Final summary
    echo ""
    echo -e "${GREEN}==================================================${NC}"
    echo -e "${GREEN}[SCAN COMPLETE]${NC}"
    echo -e "${GREEN}Results saved to: $OUTPUT_FILE${NC}"
    echo ""
    echo -e "${YELLOW}ETHICAL REMINDER:${NC}"
    echo -e "${YELLOW}- Only test systems you are authorized to test${NC}"
    echo -e "${YELLOW}- Follow responsible disclosure practices${NC}"
    echo -e "${YELLOW}- Respect privacy and applicable laws${NC}"
    echo -e "${GREEN}==================================================${NC}"
}

# Error handling
set -eEuo pipefail
trap 'echo -e "${RED}[FATAL ERROR] Script failed at line $LINENO${NC}"' ERR

# Start the script
main "$@"