#!/bin/bash

# LFI Endpoint Extractor Toolkit
# Author: Security Tooling
# Version: 2.0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
INPUT_FILE=""
OUTPUT_FILE=""
OUTPUT_DIR=""
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# LFI patterns arrays
LFI_PARAMS=("file" "page" "path" "load" "template" "include" "doc" "view" "filename" "document" "folder" "style" "pdf" "template" "pg" "cat" "dir" "display" "locate" "show" "nav" "content" "root" "prefix" "include_path")
LFI_FILES=("/etc/passwd" "/etc/hosts" "/etc/shadow" "/proc/self" "/windows/win.ini" "/boot.ini" ".htpasswd" ".htaccess")
TRAVERSAL_PATTERNS=("../" "..\\" "%2e%2e%2f" "%2e%2e/" "..%2f" "%2e%2e%5c" "....//" "....\/")
PHP_WRAPPERS=("php://filter" "php://input" "zlib://" "data://" "expect://")

# Banner
show_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                                                          ║"
    echo "║   ███████╗██╗     ███████╗    ██╗  ██╗███████╗██████╗   ║"
    echo "║   ██╔════╝██║     ██╔════╝    ██║  ██║██╔════╝██╔══██╗  ║"
    echo "║   █████╗  ██║     █████╗      ███████║█████╗  ██║  ██║  ║"
    echo "║   ██╔══╝  ██║     ██╔══╝      ██╔══██║██╔══╝  ██║  ██║  ║"
    echo "║   ██║     ███████╗███████╗    ██║  ██║███████╗██████╔╝  ║"
    echo "║   ╚═╝     ╚══════╝╚══════╝    ╚═╝  ╚═╝╚══════╝╚═════╝   ║"
    echo "║                                                          ║"
    echo "║               LFI Endpoint Extractor Toolkit             ║"
    echo "║                     Version 2.0                          ║"
    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Help function
show_help() {
    echo -e "${YELLOW}"
    echo "LFI Endpoint Extractor Toolkit - Help"
    echo "======================================"
    echo -e "${NC}"
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  -h, --help              Show this help message"
    echo "  -i, --input FILE        Input file containing endpoints"
    echo "  -o, --output FILE       Output file for results"
    echo "  -m, --method NUMBER     Direct method execution (1-6)"
    echo "  -d, --directory DIR     Output directory for categorized results"
    echo ""
    echo "EXTRACTION METHODS:"
    echo "  1. Basic grep extraction"
    echo "  2. Advanced parameter analysis"
    echo "  3. Categorized extraction"
    echo "  4. Quick extraction (recommended)"
    echo "  5. AWK-based extraction"
    echo "  6. Comprehensive extraction (all methods)"
    echo ""
    echo "EXAMPLES:"
    echo "  $0 -i endpoints.txt                    # Interactive mode"
    echo "  $0 -i endpoints.txt -m 4               # Quick extraction"
    echo "  $0 -i endpoints.txt -m 3 -d results    # Categorized extraction"
    echo "  $0 -i urls.txt -o lfi_results.txt -m 1 # Specific output file"
    echo "  $0 --help                              # Show this help"
    echo ""
    echo "INPUT FORMAT:"
    echo "  Input file should contain one URL per line, collected from tools like:"
    echo "  - Katana"
    echo "  - waybackurls"
    echo "  - gau"
    echo "  - Other recon tools"
    echo ""
    echo "OUTPUT:"
    echo "  Results are saved with timestamp to prevent overwriting"
    echo "  Categorized results are saved in separate directories"
}

# Function to check dependencies
check_dependencies() {
    local deps=("grep" "sort" "awk" "mkdir" "head")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${RED}[ERROR] Required dependency '$dep' not found${NC}"
            exit 1
        fi
    done
    echo -e "${GREEN}[INFO] All dependencies satisfied${NC}"
}

# Function to validate input file
validate_input() {
    if [[ -z "$INPUT_FILE" ]]; then
        echo -e "${RED}[ERROR] Input file not specified${NC}"
        exit 1
    fi
    
    if [[ ! -f "$INPUT_FILE" ]]; then
        echo -e "${RED}[ERROR] Input file '$INPUT_FILE' not found${NC}"
        exit 1
    fi
    
    if [[ ! -s "$INPUT_FILE" ]]; then
        echo -e "${RED}[ERROR] Input file '$INPUT_FILE' is empty${NC}"
        exit 1
    fi
    
    local line_count=$(wc -l < "$INPUT_FILE")
    echo -e "${GREEN}[INFO] Input file validated: $line_count endpoints found${NC}"
}

# Method 1: Basic grep extraction
method1_basic_grep() {
    echo -e "${BLUE}[METHOD 1] Basic grep extraction${NC}"
    
    local output="${OUTPUT_FILE:-lfi_basic_${TIMESTAMP}.txt}"
    local pattern_file=$(mktemp)
    
    # Create pattern file
    {
        for pattern in "${LFI_PARAMS[@]}"; do echo "${pattern}="; done
        for pattern in "${LFI_FILES[@]}"; do echo "$pattern"; done
        for pattern in "${TRAVERSAL_PATTERNS[@]}"; do echo "$pattern"; done
        for pattern in "${PHP_WRAPPERS[@]}"; do echo "$pattern"; done
    } > "$pattern_file"
    
    grep -i -f "$pattern_file" "$INPUT_FILE" | sort -u > "$output"
    
    local count=$(wc -l < "$output")
    echo -e "${GREEN}[SUCCESS] Extracted $count endpoints to $output${NC}"
    
    rm -f "$pattern_file"
    show_sample "$output"
}

# Method 2: Advanced parameter analysis
method2_advanced_analysis() {
    echo -e "${BLUE}[METHOD 2] Advanced parameter analysis${NC}"
    
    local output="${OUTPUT_FILE:-lfi_advanced_${TIMESTAMP}.txt}"
    > "$output"
    
    echo -e "${YELLOW}[INFO] Analyzing parameters...${NC}"
    
    # Extract URLs with parameters
    grep "?" "$INPUT_FILE" | while read -r url; do
        local base_url=$(echo "$url" | cut -d'?' -f1)
        local query_string=$(echo "$url" | cut -d'?' -f2-)
        
        IFS='&' read -ra params <<< "$query_string"
        for param_pair in "${params[@]}"; do
            local param_name=$(echo "$param_pair" | cut -d'=' -f1)
            local param_value=$(echo "$param_pair" | cut -d'=' -f2-)
            
            # Check if parameter name matches LFI patterns
            for lfi_param in "${LFI_PARAMS[@]}"; do
                if [[ "$param_name" == *"$lfi_param"* ]]; then
                    echo "$url" >> "$output"
                    break 2
                fi
            done
            
            # Check if parameter value contains LFI patterns
            for pattern in "${LFI_FILES[@]}" "${TRAVERSAL_PATTERNS[@]}"; do
                if [[ "$param_value" == *"$pattern"* ]]; then
                    echo "$url" >> "$output"
                    break 2
                fi
            done
        done
    done
    
    # Remove duplicates
    sort -u "$output" -o "$output"
    
    local count=$(wc -l < "$output")
    echo -e "${GREEN}[SUCCESS] Analyzed parameters: $count endpoints to $output${NC}"
    show_sample "$output"
}

# Method 3: Categorized extraction
method3_categorized() {
    echo -e "${BLUE}[METHOD 3] Categorized extraction${NC}"
    
    local output_dir="${OUTPUT_DIR:-lfi_categorized_${TIMESTAMP}}"
    mkdir -p "$output_dir"
    
    echo -e "${YELLOW}[INFO] Creating categorized output in: $output_dir${NC}"
    
    # Create category files
    local categories=(
        "file_parameters:file="
        "page_parameters:page="
        "path_parameters:path="
        "include_parameters:include="
        "template_parameters:template="
        "document_parameters:doc="
        "view_parameters:view="
        "etc_passwd:etc/passwd"
        "etc_hosts:etc/hosts"
        "win_ini:win.ini"
        "proc_self:proc/self"
        "path_traversal:\.\./"
        "php_wrappers:php://"
        "encoding_patterns:%2e%2e"
    )
    
    for category in "${categories[@]}"; do
        local name="${category%:*}"
        local pattern="${category#*:}"
        grep -i "$pattern" "$INPUT_FILE" | sort -u > "$output_dir/${name}.txt"
    done
    
    # Combine all categories
    cat "$output_dir"/*.txt | sort -u > "$output_dir/ALL_LFI_ENDPOINTS.txt"
    
    # Show summary
    echo -e "${GREEN}[SUCCESS] Categorized extraction complete${NC}"
    echo -e "${CYAN}[SUMMARY]${NC}"
    for file in "$output_dir"/*.txt; do
        local count=$(wc -l < "$file" 2>/dev/null || echo 0)
        if [[ $count -gt 0 ]]; then
            echo -e "  - $(basename "$file"): $count endpoints"
        fi
    done
    
    local total_count=$(wc -l < "$output_dir/ALL_LFI_ENDPOINTS.txt")
    echo -e "${GREEN}[TOTAL] $total_count unique LFI endpoints found${NC}"
}

# Method 4: Quick extraction (recommended)
method4_quick_extraction() {
    echo -e "${BLUE}[METHOD 4] Quick extraction${NC}"
    
    local output="${OUTPUT_FILE:-lfi_quick_${TIMESTAMP}.txt}"
    
    # Single efficient grep command
    grep -E -i "(file=|page=|path=|include=|template=|doc=|view=|filename=|document=|load=|etc/passwd|etc/hosts|win\.ini|proc/self|\.\./|\.\.\\|%2e%2e|php://)" "$INPUT_FILE" | sort -u > "$output"
    
    local count=$(wc -l < "$output")
    echo -e "${GREEN}[SUCCESS] Quick extraction: $count endpoints to $output${NC}"
    show_sample "$output"
}

# Method 5: AWK-based extraction
method5_awk_extraction() {
    echo -e "${BLUE}[METHOD 5] AWK-based extraction${NC}"
    
    local output="${OUTPUT_FILE:-lfi_awk_${TIMESTAMP}.txt}"
    
    awk '
    BEGIN {
        IGNORECASE = 1
        # Build patterns array
        patterns["file="] = 1
        patterns["page="] = 1
        patterns["path="] = 1
        patterns["include="] = 1
        patterns["template="] = 1
        patterns["doc="] = 1
        patterns["view="] = 1
        patterns["etc/passwd"] = 1
        patterns["etc/hosts"] = 1
        patterns["win.ini"] = 1
        patterns["proc/self"] = 1
        patterns["../"] = 1
        patterns["..\\"] = 1
        patterns["%2e%2e"] = 1
        patterns["php://"] = 1
    }
    {
        url = $0
        for (pattern in patterns) {
            if (index(url, pattern) > 0) {
                print url
                next
            }
        }
    }
    ' "$INPUT_FILE" | sort -u > "$output"
    
    local count=$(wc -l < "$output")
    echo -e "${GREEN}[SUCCESS] AWK extraction: $count endpoints to $output${NC}"
    show_sample "$output"
}

# Method 6: Comprehensive extraction
method6_comprehensive() {
    echo -e "${BLUE}[METHOD 6] Comprehensive extraction${NC}"
    
    local output_dir="${OUTPUT_DIR:-lfi_comprehensive_${TIMESTAMP}}"
    mkdir -p "$output_dir"
    
    echo -e "${YELLOW}[INFO] Running comprehensive analysis...${NC}"
    
    # Run all methods
    OUTPUT_FILE="$output_dir/method1_basic.txt" method1_basic_grep > /dev/null 2>&1
    OUTPUT_FILE="$output_dir/method2_advanced.txt" method2_advanced_analysis > /dev/null 2>&1
    OUTPUT_DIR="$output_dir/method3_categorized" method3_categorized > /dev/null 2>&1
    OUTPUT_FILE="$output_dir/method4_quick.txt" method4_quick_extraction > /dev/null 2>&1
    OUTPUT_FILE="$output_dir/method5_awk.txt" method5_awk_extraction > /dev/null 2>&1
    
    # Combine all results
    cat "$output_dir"/*.txt 2>/dev/null | sort -u > "$output_dir/COMPREHENSIVE_LFI_ENDPOINTS.txt"
    
    local total_count=$(wc -l < "$output_dir/COMPREHENSIVE_LFI_ENDPOINTS.txt")
    echo -e "${GREEN}[SUCCESS] Comprehensive extraction complete${NC}"
    echo -e "${CYAN}[RESULTS] $total_count total unique LFI endpoints found${NC}"
    echo -e "${CYAN}[OUTPUT] All results saved in: $output_dir${NC}"
}

# Show sample of results
show_sample() {
    local file="$1"
    local count=$(wc -l < "$file" 2>/dev/null || echo 0)
    
    if [[ $count -gt 0 ]]; then
        echo -e "${YELLOW}[SAMPLE] First 3 endpoints:${NC}"
        head -3 "$file" | while read -r line; do
            echo -e "  ${GREEN}✓${NC} $line"
        done
    fi
}

# Interactive menu
show_menu() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                   SELECT EXTRACTION METHOD              ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    echo "║  1. Basic grep extraction                               ║"
    echo "║  2. Advanced parameter analysis                         ║"
    echo "║  3. Categorized extraction                              ║"
    echo "║  4. Quick extraction (Recommended)                      ║"
    echo "║  5. AWK-based extraction                                ║"
    echo "║  6. Comprehensive extraction (All methods)              ║"
    echo "║  7. Exit                                                ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Process command line arguments
process_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -i|--input)
                INPUT_FILE="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -m|--method)
                METHOD="$2"
                shift 2
                ;;
            -d|--directory)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            *)
                echo -e "${RED}[ERROR] Unknown option: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
}

# Main execution function
main() {
    show_banner
    check_dependencies
    
    # Process command line arguments
    process_arguments "$@"
    
    # If method is specified via command line, execute directly
    if [[ -n "$METHOD" ]]; then
        if [[ -z "$INPUT_FILE" ]]; then
            echo -e "${RED}[ERROR] Input file required with -i option${NC}"
            exit 1
        fi
        validate_input
        execute_method "$METHOD"
        exit 0
    fi
    
    # Interactive mode
    if [[ -z "$INPUT_FILE" ]]; then
        echo -e "${YELLOW}[INPUT] Enter path to endpoints file:${NC}"
        read -r INPUT_FILE
    fi
    
    validate_input
    
    while true; do
        show_menu
        echo -e "${YELLOW}[CHOICE] Select method (1-7):${NC}"
        read -r choice
        
        case $choice in
            1) execute_method 1 ;;
            2) execute_method 2 ;;
            3) execute_method 3 ;;
            4) execute_method 4 ;;
            5) execute_method 5 ;;
            6) execute_method 6 ;;
            7) 
                echo -e "${GREEN}[INFO] Thank you for using LFI Extractor Toolkit!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}[ERROR] Invalid choice. Please select 1-7${NC}"
                ;;
        esac
        
        echo ""
        echo -e "${YELLOW}[ACTION] Press any key to continue or 'q' to quit...${NC}"
        read -r -n1 input
        if [[ $input == "q" ]]; then
            echo -e "${GREEN}[INFO] Thank you for using LFI Extractor Toolkit!${NC}"
            exit 0
        fi
        echo ""
    done
}

# Execute selected method
execute_method() {
    local method="$1"
    
    case $method in
        1) method1_basic_grep ;;
        2) method2_advanced_analysis ;;
        3) method3_categorized ;;
        4) method4_quick_extraction ;;
        5) method5_awk_extraction ;;
        6) method6_comprehensive ;;
        *)
            echo -e "${RED}[ERROR] Invalid method: $method${NC}"
            return 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"