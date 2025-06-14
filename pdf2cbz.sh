#!/bin/bash
# Script to convert PDF files to CBZ format by extracting images
# Requires pdfimages (from poppler-utils) and zip
#   `brew install poppler`
# Usage: ./pdf2cbz.sh [directory]

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default to current directory if no argument provided
SEARCH_DIR="${1:-.}"

# Check if required tools are installed
check_dependencies() {
    local missing_tools=()
    
    if ! command -v pdfimages &> /dev/null; then
        missing_tools+=("pdfimages (poppler-utils)")
    fi
    
    if ! command -v zip &> /dev/null; then
        missing_tools+=("zip")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${RED}Error: Missing required tools:${NC}"
        printf '%s\n' "${missing_tools[@]}"
        echo -e "\n${YELLOW}Install with:${NC}"
        echo "  macOS: brew install poppler zip"
        echo "  Ubuntu/Debian: sudo apt install poppler-utils zip"
        echo "  CentOS/RHEL: sudo yum install poppler-utils zip"
        exit 1
    fi
}

# Extract images from PDF and create CBZ
process_pdf() {
    local pdf_file="$1"
    local pdf_dir=$(dirname "$pdf_file")
    local pdf_name=$(basename "$pdf_file" .pdf)
    local temp_dir=$(mktemp -d)
    local converted_dir="$pdf_dir/converted"
    # Convert to absolute path
    local cbz_file="$(cd "$pdf_dir" && pwd)/converted/${pdf_name}.cbz"
    local original_dir=$(pwd)
    
    echo -e "${YELLOW}Processing:${NC} $pdf_file"
    
    # Create converted directory if it doesn't exist
    if ! mkdir -p "$converted_dir"; then
        echo -e "${RED}  Error:${NC} Cannot create directory $converted_dir"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Skip if CBZ already exists
    if [ -f "$cbz_file" ]; then
        echo -e "${YELLOW}  Skipping:${NC} CBZ already exists"
        rm -rf "$temp_dir"
        return 0
    fi
    
    # Extract images to temporary directory
    echo "  Extracting images..."
    if ! pdfimages -all "$pdf_file" "$temp_dir/image" 2>/dev/null; then
        echo -e "${RED}  Error:${NC} Failed to extract images from $pdf_file"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Change to temp directory
    cd "$temp_dir"
    
    # Check if any JPEG images were extracted using wildcards
    local has_jpg=false
    local has_jpeg=false
    
    # Check for .jpg files
    if ls *.jpg 1> /dev/null 2>&1; then
        has_jpg=true
    fi
    
    # Check for .jpeg files
    if ls *.jpeg 1> /dev/null 2>&1; then
        has_jpeg=true
    fi
    
    if [ "$has_jpg" = false ] && [ "$has_jpeg" = false ]; then
        echo -e "${YELLOW}  Warning:${NC} No JPEG images found in $pdf_file"
        cd "$original_dir"
        rm -rf "$temp_dir"
        return 0
    fi
    
    # Count images
    local jpeg_count=0
    if [ "$has_jpg" = true ]; then
        jpeg_count=$((jpeg_count + $(ls -1 *.jpg 2>/dev/null | wc -l)))
    fi
    if [ "$has_jpeg" = true ]; then
        jpeg_count=$((jpeg_count + $(ls -1 *.jpeg 2>/dev/null | wc -l)))
    fi
    
    echo "  Found $jpeg_count JPEG image(s)"
    
    # Create CBZ file using wildcards
    echo "  Creating CBZ archive..."
    echo "  CBZ file path: $cbz_file"
    
    local zip_success=false
    
    # Try to zip files - handle different combinations of file extensions
    if [ "$has_jpg" = true ] && [ "$has_jpeg" = true ]; then
        # Both .jpg and .jpeg files exist
        if zip -q "$cbz_file" *.jpg *.jpeg 2>/dev/null; then
            zip_success=true
        fi
    elif [ "$has_jpg" = true ]; then
        # Only .jpg files exist
        if zip -q "$cbz_file" *.jpg 2>/dev/null; then
            zip_success=true
        fi
    elif [ "$has_jpeg" = true ]; then
        # Only .jpeg files exist
        if zip -q "$cbz_file" *.jpeg 2>/dev/null; then
            zip_success=true
        fi
    fi
    
    if [ "$zip_success" = true ]; then
        echo -e "${GREEN}  Success:${NC} Created $cbz_file"
    else
        echo -e "${RED}  Error:${NC} Failed to create CBZ file"
        cd "$original_dir"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Return to original directory and clean up
    cd "$original_dir"
    rm -rf "$temp_dir"
    
    return 0
}

# Main execution
main() {
    echo "PDF to CBZ Converter"
    echo "===================="
    echo "Searching for PDF files in: $SEARCH_DIR"
    echo ""
    
    # Check dependencies
    check_dependencies
    
    # Find all PDF files recursively - using temporary file instead of process substitution
    local temp_file=$(mktemp)
    find "$SEARCH_DIR" -type f -iname "*.pdf" > "$temp_file"
    
    local pdf_files=()
    while IFS= read -r file; do
        [ -n "$file" ] && pdf_files+=("$file")
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    if [ ${#pdf_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}No PDF files found in $SEARCH_DIR${NC}"
        exit 0
    fi
    
    echo "Found ${#pdf_files[@]} PDF file(s) to process"
    echo ""
    
    # Process each PDF file
    local success_count=0
    local error_count=0
    
    for pdf_file in "${pdf_files[@]}"; do
        if process_pdf "$pdf_file"; then
            ((success_count++))
        else
            ((error_count++))
        fi
        echo ""
    done
    
    # Summary
    echo "===================="
    echo -e "${GREEN}Successfully processed: $success_count${NC}"
    if [ "$error_count" -gt 0 ]; then
        echo -e "${RED}Errors encountered: $error_count${NC}"
    fi
}

# Run main function
main "$@"
