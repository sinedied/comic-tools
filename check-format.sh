#!/usr/bin/env bash
# Script to check if comic archive files have correct headers
# Checks .cbz files for ZIP headers and .cbr files for RAR headers
# Only prints the names of files that don't have the expected headers
# Usage: ./check-format.sh [file_or_directory]

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if a file has a ZIP header
check_zip_header() {
    local file="$1"
    
    # Check if file exists and is readable
    if [[ ! -r "$file" ]]; then
        echo -e "${RED}Error: Cannot read file: $file${NC}" >&2
        return 1
    fi
    
    # Get the first 4 bytes of the file
    local header
    header=$(hexdump -n 4 -e '4/1 "%02x"' "$file" 2>/dev/null)
    
    # ZIP files start with "504b0304" (PK..) or "504b0506" (PK.. for empty archive) or "504b0708" (PK.. for spanned archive)
    # RAR files start with "52617221" (Rar!) for RAR 1.5+ or "526172211a0700" for RAR 5.0+
    case "$header" in
        504b0304|504b0506|504b0708)
            # Valid ZIP header
            return 0
            ;;
        52617221)
            # RAR header detected
            return 1
            ;;
        *)
            # Unknown or invalid header
            return 1
            ;;
    esac
}

# Function to check if a file is actually a RAR archive
is_rar_file() {
    local file="$1"
    
    # Check if file exists and is readable
    if [[ ! -r "$file" ]]; then
        return 1
    fi
    
    # Get the first 4 bytes for RAR signature
    local header
    header=$(hexdump -n 4 -e '4/1 "%02x"' "$file" 2>/dev/null)
    
    # Check for RAR signature
    if [[ "$header" == "52617221" ]]; then
        return 0
    fi
    
    # Also check for newer RAR 5.0+ signature (first 7 bytes: 526172211a0700)
    local extended_header
    extended_header=$(hexdump -n 7 -e '7/1 "%02x"' "$file" 2>/dev/null)
    
    if [[ "$extended_header" == "526172211a0700"* ]]; then
        return 0
    fi
    
    return 1
}

# Function to process a single comic archive file
process_file() {
    local file="$1"
    
    # Check if file exists
    if [[ ! -f "$file" ]]; then
        echo -e "${RED}Error: File does not exist: $file${NC}" >&2
        return 1
    fi
    
    # Check if it's a comic archive file (case insensitive)
    local filename_lower
    filename_lower=$(echo "$file" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$filename_lower" == *.cbz ]]; then
        # CBZ file should have ZIP header
        if ! check_zip_header "$file"; then
            if is_rar_file "$file"; then
                echo -e "${YELLOW}CBZ-RAR:${NC} $file"
            else
                echo -e "${RED}CBZ-INVALID:${NC} $file"
            fi
        fi
    elif [[ "$filename_lower" == *.cbr ]]; then
        # CBR file should have RAR header
        if ! is_rar_file "$file"; then
            if check_zip_header "$file"; then
                echo -e "${YELLOW}CBR-ZIP:${NC} $file"
            else
                echo -e "${RED}CBR-INVALID:${NC} $file"
            fi
        fi
    else
        echo -e "${RED}Error: File is not a .cbz or .cbr file: $file${NC}" >&2
        return 1
    fi
    
    return 0
}

# Function to process files recursively in a directory
process_directory() {
    local search_dir="$1"
    
    # Find all .cbz and .cbr files recursively
    while IFS= read -r -d '' file; do
        local filename_lower
        filename_lower=$(echo "$file" | tr '[:upper:]' '[:lower:]')
        
        if [[ "$filename_lower" == *.cbz ]]; then
            # CBZ file should have ZIP header
            if ! check_zip_header "$file"; then
                if is_rar_file "$file"; then
                    echo -e "${YELLOW}CBZ-RAR:${NC} $file"
                else
                    echo -e "${RED}CBZ-INVALID:${NC} $file"
                fi
            fi
        elif [[ "$filename_lower" == *.cbr ]]; then
            # CBR file should have RAR header
            if ! is_rar_file "$file"; then
                if check_zip_header "$file"; then
                    echo -e "${YELLOW}CBR-ZIP:${NC} $file"
                else
                    echo -e "${RED}CBR-INVALID:${NC} $file"
                fi
            fi
        fi
    done < <(find "$search_dir" -type f \( -iname "*.cbz" -o -iname "*.cbr" \) -print0 2>/dev/null)
    
    return 0
}

# Main function
main() {
    local target="${1:-.}"
    
    # Check if target exists
    if [[ ! -e "$target" ]]; then
        echo -e "${RED}Error: File or directory does not exist: $target${NC}" >&2
        exit 1
    fi
    
    # Check if it's a file or directory
    if [[ -f "$target" ]]; then
        # Process single file
        process_file "$target"
    elif [[ -d "$target" ]]; then
        # Process directory
        process_directory "$target"
    else
        echo -e "${RED}Error: Target is neither a file nor a directory: $target${NC}" >&2
        exit 1
    fi
}

# Show usage if --help is passed
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [file_or_directory]"
    echo ""
    echo "Checks comic archive files to verify they have the correct headers:"
    echo "  - .cbz files should have ZIP headers"
    echo "  - .cbr files should have RAR headers"
    echo "Can check a single file or recursively search a directory."
    echo "Only prints the names of files that don't have the expected headers."
    echo ""
    echo "Arguments:"
    echo "  file_or_directory    Comic file (.cbz/.cbr) or directory to search (default: current directory)"
    echo ""
    echo "Output format:"
    echo "  CBZ-RAR: filename      - CBZ file that actually contains RAR data"
    echo "  CBZ-INVALID: filename  - CBZ file with unknown/invalid header"
    echo "  CBR-ZIP: filename      - CBR file that actually contains ZIP data"
    echo "  CBR-INVALID: filename  - CBR file with unknown/invalid header"
    echo ""
    echo "Examples:"
    echo "  $0                       # Check current directory"
    echo "  $0 /path/to/comics       # Check specific directory"
    echo "  $0 comic.cbz             # Check single CBZ file"
    echo "  $0 comic.cbr             # Check single CBR file"
    echo "  $0 /path/to/comic.cbz    # Check single file with full path"
    exit 0
fi

# Run the main function
main "$@"
