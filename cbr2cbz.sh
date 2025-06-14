#!/bin/bash
# Script to convert CBR files to CBZ format recursively
# CBR files are RAR archives, CBZ files are ZIP archives
# Requires unrar and zip
#   `brew install rar`
# Usage: ./cbr2cbz.sh [directory]

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default to current directory if no argument provided
SEARCH_DIR="${1:-.}"

# Statistics
PROCESSED_COUNT=0
SUCCESS_COUNT=0
ERROR_COUNT=0

# Check if required tools are installed
check_dependencies() {
    local missing_tools=()
    
    if ! command -v unrar &> /dev/null; then
        missing_tools+=("unrar")
    fi
    
    if ! command -v zip &> /dev/null; then
        missing_tools+=("zip")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${RED}Error: Missing required tools:${NC}"
        printf '%s\n' "${missing_tools[@]}"
        echo -e "\n${YELLOW}Install with:${NC}"
        echo "  macOS: brew install unrar zip"
        echo "  Ubuntu/Debian: sudo apt install unrar zip"
        exit 1
    fi
}

# Extract CBR and create CBZ
process_cbr() {
    local cbr_file="$1"
    local cbr_dir
    local cbr_name
    local temp_dir
    local converted_dir
    local cbz_file
    local original_dir
    
    cbr_dir=$(dirname "$cbr_file")
    cbr_name=$(basename "$cbr_file" .cbr)
    temp_dir=$(mktemp -d)
    converted_dir="$cbr_dir/converted"
    # Convert to absolute path
    cbz_file="$(cd "$cbr_dir" && pwd)/converted/${cbr_name}.cbz"
    original_dir=$(pwd)
    
    echo -e "${BLUE}Processing:${NC} $cbr_file"
    
    # Create converted directory if it doesn't exist
    mkdir -p "$converted_dir"
    
    # Check if CBZ already exists
    if [ -f "$cbz_file" ]; then
        echo -e "${YELLOW}  Skipping - CBZ already exists:${NC} $cbz_file"
        return 0
    fi
    
    # Change to temp directory
    cd "$temp_dir"
    
    # Extract CBR file
    echo -e "${BLUE}  Extracting CBR...${NC}"
    if ! unrar x -kb "$cbr_file" . > /dev/null 2>&1; then
        echo -e "${RED}  Error: Failed to extract CBR file${NC}"
        cd "$original_dir"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Check if any files were extracted
    if [ -z "$(find . -type f 2>/dev/null)" ]; then
        echo -e "${RED}  Error: No files extracted from CBR${NC}"
        cd "$original_dir"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Count extracted files
    local file_count
    file_count=$(find . -type f | wc -l | xargs)
    echo -e "${BLUE}  Found $file_count files${NC}"
    
    # Create CBZ file (ZIP archive)
    echo -e "${BLUE}  Creating CBZ...${NC}"
    if ! zip -r -0 "$cbz_file" . > /dev/null 2>&1; then
        echo -e "${RED}  Error: Failed to create CBZ file${NC}"
        cd "$original_dir"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Verify CBZ was created and has reasonable size
    if [ ! -f "$cbz_file" ] || [ ! -s "$cbz_file" ]; then
        echo -e "${RED}  Error: CBZ file was not created properly${NC}"
        cd "$original_dir"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Get file sizes for comparison
    local cbr_size
    local cbz_size
    cbr_size=$(stat -f%z "$cbr_file" 2>/dev/null || echo "0")
    cbz_size=$(stat -f%z "$cbz_file" 2>/dev/null || echo "0")
    
    # Format file sizes
    cbr_size_mb=$(echo "scale=2; $cbr_size / 1048576" | bc 2>/dev/null || echo "N/A")
    cbz_size_mb=$(echo "scale=2; $cbz_size / 1048576" | bc 2>/dev/null || echo "N/A")
    
    echo -e "${GREEN}  Success:${NC} $cbz_file"
    echo -e "${BLUE}  Size: ${cbr_size_mb}MB (CBR) → ${cbz_size_mb}MB (CBZ)${NC}"
    
    # Clean up
    cd "$original_dir"
    rm -rf "$temp_dir"
    
    return 0
}

# Main processing function
process_directory() {
    local dir="$1"
    
    echo -e "${BLUE}Searching for CBR files in: ${dir}${NC}\n"
    
    # Find all CBR files recursively
    while IFS= read -r -d '' cbr_file; do
        ((PROCESSED_COUNT++))
        
        if process_cbr "$cbr_file"; then
            ((SUCCESS_COUNT++))
        else
            ((ERROR_COUNT++))
        fi
        
        echo # Empty line for readability
        
    done < <(find "$dir" -type f -iname "*.cbr" -print0)
}

# Print usage information
print_usage() {
    echo "Usage: $0 [directory]"
    echo
    echo "Convert CBR (RAR comic book) files to CBZ (ZIP comic book) format recursively."
    echo "Converted files are placed in 'converted/' subfolders within each directory."
    echo
    echo "Arguments:"
    echo "  directory    Directory to search for CBR files (default: current directory)"
    echo
    echo "Examples:"
    echo "  $0                    # Convert CBR files in current directory"
    echo "  $0 /path/to/comics    # Convert CBR files in specified directory"
    echo
    echo "Requirements:"
    echo "  - unrar (for extracting CBR files)"
    echo "  - zip (for creating CBZ files)"
    echo "  - bc (for size calculations)"
    echo
    echo "Install requirements on macOS:"
    echo "  brew install unrar zip bc"
}

# Handle help option
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    print_usage
    exit 0
fi

# Main execution
main() {
    echo -e "${GREEN}CBR to CBZ Converter${NC}"
    echo -e "${GREEN}===================${NC}\n"
    
    # Check dependencies
    check_dependencies
    
    # Verify search directory exists
    if [ ! -d "$SEARCH_DIR" ]; then
        echo -e "${RED}Error: Directory '$SEARCH_DIR' does not exist${NC}"
        exit 1
    fi
    
    # Convert to absolute path
    SEARCH_DIR=$(cd "$SEARCH_DIR" && pwd)
    
    # Process directory
    process_directory "$SEARCH_DIR"
    
    # Print summary
    echo -e "${GREEN}Processing Complete${NC}"
    echo -e "${GREEN}==================${NC}"
    echo -e "${BLUE}Files processed: ${PROCESSED_COUNT}${NC}"
    echo -e "${GREEN}Successfully converted: ${SUCCESS_COUNT}${NC}"
    
    if [ $ERROR_COUNT -gt 0 ]; then
        echo -e "${RED}Errors encountered: ${ERROR_COUNT}${NC}"
    fi
    
    if [ $PROCESSED_COUNT -eq 0 ]; then
        echo -e "${YELLOW}No CBR files found in: ${SEARCH_DIR}${NC}"
    fi
}

# Run main function
main "$@"
