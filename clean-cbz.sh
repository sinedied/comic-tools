#!/usr/bin/env bash
# Script to clean CBZ files by removing system files (.DS_Store, Thumbs.db, ._* files)
# Usage: ./clean-cbz.sh [file_or_directory] [options]

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
SEARCH_DIR=""

# Statistics
PROCESSED_COUNT=0
SUCCESS_COUNT=0
ERROR_COUNT=0

# Show usage information
show_usage() {
    echo "Usage: $0 [file_or_directory] [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Description:"
    echo "  Removes unwanted system files from CBZ archives:"
    echo "  - .DS_Store (macOS folder metadata)"
    echo "  - Thumbs.db (Windows thumbnail cache)"
    echo "  - ._* files (macOS resource forks and metadata)"
    echo "  - __MACOSX/ folders (macOS archive metadata)"
    echo ""
    echo "Examples:"
    echo "  $0 comic.cbz"
    echo "  $0 /path/to/comics/"
    echo "  $0 .  # Clean all CBZ files in current directory"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                echo -e "${RED}Error:${NC} Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [ -z "$SEARCH_DIR" ]; then
                    SEARCH_DIR="$1"
                else
                    echo -e "${RED}Error:${NC} Multiple input paths specified"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Default to current directory if no argument provided
    if [ -z "$SEARCH_DIR" ]; then
        SEARCH_DIR="."
    fi
}

# Check dependencies
check_dependencies() {
    local missing_tools=()
    
    if ! command -v unzip &> /dev/null; then
        missing_tools+=("unzip")
    fi
    
    if ! command -v zip &> /dev/null; then
        missing_tools+=("zip")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${RED}Error: Missing required tools:${NC}"
        printf '%s\n' "${missing_tools[@]}"
        echo -e "\n${YELLOW}Install with:${NC}"
        echo "  macOS: brew install unzip zip"
        echo "  Ubuntu/Debian: sudo apt install unzip zip"
        exit 1
    fi
}

# Check if a file should be removed based on patterns
should_remove_file() {
    local filename="$1"
    local basename
    basename=$(basename "$filename")
    
    # Remove .DS_Store files
    if [[ "$basename" == ".DS_Store" ]]; then
        return 0
    fi
    
    # Remove Thumbs.db files
    if [[ "$basename" == "Thumbs.db" ]]; then
        return 0
    fi
    
    # Remove ._* files (AppleDouble files)
    if [[ "$basename" =~ ^\._.*$ ]]; then
        return 0
    fi
    
    # Remove files in __MACOSX folders
    if [[ "$filename" =~ __MACOSX/ ]]; then
        return 0
    fi
    
    return 1
}

# Clean a single CBZ file
clean_cbz() {
    local cbz_file="$1"
    local cbz_dir
    local cbz_name
    local temp_dir
    cbz_dir=$(dirname "$cbz_file")
    cbz_name=$(basename "$cbz_file" .cbz)
    temp_dir=$(mktemp -d)
    
    # Determine output directory - avoid nested "cleaned" directories
    local cleaned_dir
    if [[ "$cbz_dir" =~ /cleaned$ ]]; then
        # If input is already in a cleaned directory, use the parent directory's cleaned folder
        # but add a suffix to distinguish from the original
        cleaned_dir="$cbz_dir"
        cbz_name="${cbz_name}_cleaned"
    else
        # Otherwise, create cleaned subdirectory
        cleaned_dir="$cbz_dir/cleaned"
    fi
    
    local output_file="$cleaned_dir/${cbz_name}.cbz"
    local original_dir
    original_dir=$(pwd)
    
    # Convert output path to absolute path
    local abs_output_file
    abs_output_file="$original_dir/$output_file"
    
    # Convert to absolute path
    local abs_cbz_file
    abs_cbz_file=$(realpath "$cbz_file")
    
    echo -e "${YELLOW}Processing:${NC} $cbz_file"
    
    # Create cleaned directory if it doesn't exist
    if ! mkdir -p "$cleaned_dir"; then
        echo -e "${RED}  Error:${NC} Cannot create directory $cleaned_dir"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Skip if cleaned CBZ already exists
    if [ -f "$abs_output_file" ]; then
        echo -e "${YELLOW}  Skipping:${NC} Cleaned CBZ already exists"
        rm -rf "$temp_dir"
        return 0
    fi
    
    # Extract CBZ to temporary directory
    echo "  Extracting CBZ..."
    cd "$temp_dir"
    
    # Try different approaches to handle special characters in filenames
    extracted=false
    
    # Method 1: Try with UTF-8 encoding
    if ! $extracted && unzip -q -O UTF-8 "$abs_cbz_file" 2>/dev/null; then
        extracted=true
    fi
    
    # Method 2: Try with different locale settings
    if ! $extracted; then
        for locale in "en_US.UTF-8" "C" "POSIX"; do
            if LC_ALL="$locale" LANG="$locale" unzip -q "$abs_cbz_file" 2>/dev/null; then
                extracted=true
                break
            fi
        done
    fi
    
    # Method 3: Try with Python as fallback (better Unicode support)
    if ! $extracted && command -v python3 >/dev/null; then
        if python3 -c "
import zipfile
import sys
try:
    with zipfile.ZipFile('$abs_cbz_file', 'r') as zip_ref:
        zip_ref.extractall('.')
    sys.exit(0)
except Exception as e:
    sys.exit(1)
" 2>/dev/null; then
            extracted=true
        fi
    fi
    
    # Method 4: Final fallback - allow unzip errors but continue if some files were extracted
    if ! $extracted; then
        unzip -q "$abs_cbz_file" 2>/dev/null || true
        # Check if any files were actually extracted
        if [ "$(find . -type f | wc -l)" -gt 0 ]; then
            extracted=true
        fi
    fi
    
    if ! $extracted; then
        echo -e "${RED}  Error:${NC} Failed to extract $cbz_file"
        cd "$original_dir"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Count total files before cleaning
    local total_files
    total_files=$(find . -type f | wc -l)
    
    # Find and remove unwanted files
    local removed_files=()
    while IFS= read -r -d '' file; do
        # Convert to relative path (remove leading ./)
        local rel_file="${file#./}"
        if should_remove_file "$rel_file"; then
            removed_files+=("$rel_file")
            rm -f "$file"
        fi
    done < <(find . -type f -print0)
    
    # Also remove empty __MACOSX directories
    while IFS= read -r -d '' dir; do
        if [[ "$(basename "$dir")" == "__MACOSX" ]]; then
            rmdir "$dir" 2>/dev/null || true
        fi
    done < <(find . -type d -name "__MACOSX" -print0)
    
    # Count remaining files
    local remaining_files
    remaining_files=$(find . -type f | wc -l)
    
    if [ ${#removed_files[@]} -eq 0 ]; then
        echo "  No unwanted files found - CBZ is already clean"
    else
        echo "  Removed ${#removed_files[@]} unwanted file(s):"
        for removed_file in "${removed_files[@]}"; do
            echo "    - $removed_file"
        done
    fi
    
    echo "  Files: $total_files → $remaining_files"
    
    # Check if we have any files left
    if [ "$remaining_files" -eq 0 ]; then
        echo -e "${RED}  Error:${NC} No files remaining after cleaning"
        cd "$original_dir"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Create new CBZ archive
    echo "  Creating cleaned CBZ..."
    
    # Create the archive
    local temp_cbz="${cbz_name}.cbz"
    if ! zip -r "$temp_cbz" . > /dev/null 2>&1; then
        echo -e "${RED}  Error:${NC} Failed to create CBZ archive"
        cd "$original_dir"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Ensure the output directory exists
    if ! mkdir -p "$(dirname "$abs_output_file")"; then
        echo -e "${RED}  Error:${NC} Failed to create output directory: $(dirname "$abs_output_file")"
        cd "$original_dir"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Move the archive to the final location
    if ! mv "$temp_cbz" "$abs_output_file"; then
        echo -e "${RED}  Error:${NC} Failed to move CBZ archive to output location"
        cd "$original_dir"
        rm -rf "$temp_dir"
        return 1
    fi
    
    cd "$original_dir"
    rm -rf "$temp_dir"
    
    echo -e "${GREEN}  Success:${NC} Created $abs_output_file"
    return 0
}

# Process all CBZ files in a directory
process_directory() {
    local dir="$1"
    
    if [ ! -d "$dir" ]; then
        echo -e "${RED}Error:${NC} Directory does not exist: $dir"
        return 1
    fi
    
    echo -e "${BLUE}Searching for CBZ files in:${NC} $dir"
    
    # Find all CBZ files, excluding those in cleaned directories
    local cbz_files=()
    while IFS= read -r -d '' file; do
        cbz_files+=("$file")
    done < <(find "$dir" -type f -iname "*.cbz" -not -path "*/cleaned/*" -print0)
    
    if [ ${#cbz_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}No CBZ files found in $dir${NC}"
        return 0
    fi
    
    echo "Found ${#cbz_files[@]} CBZ file(s) to process"
    echo ""
    
    # Process each CBZ file
    for cbz_file in "${cbz_files[@]}"; do
        ((PROCESSED_COUNT++))
        
        if clean_cbz "$cbz_file"; then
            ((SUCCESS_COUNT++))
        else
            ((ERROR_COUNT++))
        fi
        
        echo ""
    done
}

# Print statistics
print_statistics() {
    echo -e "${BLUE}Cleaning complete!${NC}"
    echo "Files processed: $PROCESSED_COUNT"
    echo -e "Successful: ${GREEN}$SUCCESS_COUNT${NC}"
    if [ $ERROR_COUNT -gt 0 ]; then
        echo -e "Errors: ${RED}$ERROR_COUNT${NC}"
    fi
}

# Main function
main() {
    echo -e "${BLUE}CBZ Cleaner${NC}"
    echo "Removes: .DS_Store, Thumbs.db, ._* files, __MACOSX/ folders"
    echo ""
    
    # Check dependencies
    check_dependencies
    
    # Determine if input is a file or directory
    if [ -f "$SEARCH_DIR" ]; then
        # Single file
        if [[ "$SEARCH_DIR" =~ \.cbz$ ]]; then
            ((PROCESSED_COUNT++))
            if clean_cbz "$SEARCH_DIR"; then
                ((SUCCESS_COUNT++))
            else
                ((ERROR_COUNT++))
            fi
        else
            echo -e "${RED}Error:${NC} File is not a CBZ: $SEARCH_DIR"
            exit 1
        fi
    elif [ -d "$SEARCH_DIR" ]; then
        # Directory
        process_directory "$SEARCH_DIR"
    else
        echo -e "${RED}Error:${NC} Path does not exist: $SEARCH_DIR"
        exit 1
    fi
    
    echo ""
    print_statistics
}

# Parse arguments and run main function
parse_arguments "$@"
main
