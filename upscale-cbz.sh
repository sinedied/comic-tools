#!/bin/bash
# Script to upscale CBZ files using Real-ESRGAN-ncnn-vulkan
# Automatically downloads Real-ESRGAN-ncnn-vulkan if not available
# Upscales images and recompresses as JPEG with configurable quality
# Usage: ./upscale-cbz.sh [file_or_directory] [options]

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_JPG_QUALITY=90
DEFAULT_MODEL="realesrgan-x4plus"
DEFAULT_RESIZE_PERCENT=50
REALESRGAN_DIR=".model"
REALESRGAN_BIN=""

# Configuration variables
JPG_QUALITY=$DEFAULT_JPG_QUALITY
MODEL=$DEFAULT_MODEL
MODEL_SCALE=4
RESIZE_PERCENT=$DEFAULT_RESIZE_PERCENT
NORMALIZE=false
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
    echo "  -q, --quality NUM       JPEG quality (1-100, default: $DEFAULT_JPG_QUALITY)"
    echo "  -m, --model NAME        Real-ESRGAN model (default: $DEFAULT_MODEL)"
    echo "                          Available: realesrgan-x4plus, realesrgan-x4plus-anime, realesr-animevideov3"
    echo "  --model-scale NUM       Model's built-in scale factor (4 for most models, default: 4)"
    echo "  -r, --resize PERCENT    Resize final image to percentage (default: ${DEFAULT_RESIZE_PERCENT}%)"
    echo "  -n, --normalize         Apply ImageMagick normalize to enhance contrast"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 comic.cbz"
    echo "  $0 /path/to/comics/ --quality 85"
    echo "  $0 comic.cbz --model realesrgan-x4plus-anime"
    echo "  $0 comic.cbz --normalize --quality 95"
    echo "  $0 comic.cbz --resize 75 --model-scale 4"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -q|--quality)
                JPG_QUALITY="$2"
                if ! [[ "$JPG_QUALITY" =~ ^[0-9]+$ ]] || [ "$JPG_QUALITY" -lt 1 ] || [ "$JPG_QUALITY" -gt 100 ]; then
                    echo -e "${RED}Error:${NC} Quality must be a number between 1 and 100"
                    exit 1
                fi
                shift 2
                ;;
            -m|--model)
                MODEL="$2"
                shift 2
                ;;
            --model-scale)
                MODEL_SCALE="$2"
                if ! [[ "$MODEL_SCALE" =~ ^[0-9]+$ ]] || [ "$MODEL_SCALE" -lt 1 ]; then
                    echo -e "${RED}Error:${NC} Model scale must be a positive number"
                    exit 1
                fi
                shift 2
                ;;
            -r|--resize)
                RESIZE_PERCENT="$2"
                if ! [[ "$RESIZE_PERCENT" =~ ^[0-9]+$ ]] || [ "$RESIZE_PERCENT" -lt 1 ] || [ "$RESIZE_PERCENT" -gt 1000 ]; then
                    echo -e "${RED}Error:${NC} Resize percentage must be between 1 and 1000"
                    exit 1
                fi
                shift 2
                ;;
            -n|--normalize)
                NORMALIZE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -s|--scale)
                echo -e "${RED}Error:${NC} Option -s/--scale is deprecated. Use --model-scale instead."
                exit 1
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

# Detect platform
detect_platform() {
    case "$(uname -s)" in
        Darwin)
            echo "macos"
            ;;
        Linux)
            echo "ubuntu"
            ;;
        *)
            echo -e "${RED}Error:${NC} Unsupported platform: $(uname -s)"
            echo "Only macOS and Linux are supported"
            exit 1
            ;;
    esac
}

# Download and setup Real-ESRGAN-ncnn-vulkan
setup_realesrgan() {
    local platform
    platform=$(detect_platform)
    local github_api="https://api.github.com/repos/xinntao/Real-ESRGAN/releases/tags/v0.2.5.0"
    
    echo -e "${BLUE}Setting up Real-ESRGAN (with models)...${NC}"
    
    # Create model directory
    mkdir -p "$REALESRGAN_DIR"
    
    # Get release info for v0.2.5.0
    echo "  Fetching Real-ESRGAN v0.2.5.0 release information..."
    local release_info
    if ! release_info=$(curl -s "$github_api"); then
        echo -e "${RED}Error:${NC} Failed to fetch release information from GitHub"
        exit 1
    fi
    
    # Extract download URL based on platform
    local download_url
    if [ "$platform" = "macos" ]; then
        download_url=$(echo "$release_info" | grep -o '"browser_download_url": "[^"]*macos[^"]*"' | head -1 | cut -d'"' -f4)
    else
        download_url=$(echo "$release_info" | grep -o '"browser_download_url": "[^"]*linux[^"]*"' | head -1 | cut -d'"' -f4)
    fi
    
    if [ -z "$download_url" ]; then
        echo -e "${RED}Error:${NC} Could not find download URL for $platform"
        exit 1
    fi
    
    local filename
    filename=$(basename "$download_url")
    local archive_path="$REALESRGAN_DIR/$filename"
    
    echo "  Downloading $filename..."
    if ! curl -L -o "$archive_path" "$download_url"; then
        echo -e "${RED}Error:${NC} Failed to download Real-ESRGAN-ncnn-vulkan"
        exit 1
    fi
    
    echo "  Extracting archive..."
    local original_dir
    original_dir=$(pwd)
    cd "$REALESRGAN_DIR"
    
    if [[ "$filename" == *.zip ]]; then
        # Use -O UTF-8 to handle special characters in filenames properly
        if ! unzip -q -O UTF-8 "$filename" 2>/dev/null; then
            # Fallback: try without UTF-8 option if it fails
            if ! unzip -q "$filename"; then
                echo -e "${RED}Error:${NC} Failed to extract ZIP archive"
                cd "$original_dir"
                exit 1
            fi
        fi
    elif [[ "$filename" == *.tar.gz ]]; then
        if ! tar -xzf "$filename"; then
            echo -e "${RED}Error:${NC} Failed to extract TAR.GZ archive"
            cd "$original_dir"
            exit 1
        fi
    else
        echo -e "${RED}Error:${NC} Unsupported archive format: $filename"
        cd "$original_dir"
        exit 1
    fi
    
    # Find the extracted directory and binary
    local binary_name="realesrgan-ncnn-vulkan"
    
    # Check if binary is directly in the extraction directory
    if [ -f "./$binary_name" ]; then
        REALESRGAN_BIN="$(pwd)/$binary_name"
    else
        # Look for binary in subdirectories
        local extracted_dir
        extracted_dir=$(find . -maxdepth 1 -type d -name "*Real-ESRGAN*" -o -name "*realesrgan*" | head -1)
        if [ -n "$extracted_dir" ]; then
            if [ -f "$extracted_dir/$binary_name" ]; then
                REALESRGAN_BIN="$(pwd)/$extracted_dir/$binary_name"
            else
                # Look for .app bundle on macOS
                if [ "$platform" = "macos" ]; then
                    local app_bundle
                    for app_bundle in "$extracted_dir"/*.app; do
                        if [ -f "$app_bundle/Contents/MacOS/$binary_name" ]; then
                            REALESRGAN_BIN="$(pwd)/$app_bundle/Contents/MacOS/$binary_name"
                            break
                        fi
                    done
                fi
            fi
        fi
    fi
    
    if [ -z "$REALESRGAN_BIN" ]; then
        echo -e "${RED}Error:${NC} Could not find Real-ESRGAN binary in extracted files"
        cd "$original_dir"
        exit 1
    fi
    
    # Make binary executable
    chmod +x "$REALESRGAN_BIN"
    
    # Test if binary runs (check for macOS security issues)
    echo "  Testing Real-ESRGAN binary..."
    local test_output
    test_output=$("$REALESRGAN_BIN" -h 2>&1) || true
    if [[ "$test_output" != *"Usage: realesrgan-ncnn-vulkan"* ]]; then
        echo -e "${RED}Error:${NC} Real-ESRGAN binary cannot run due to macOS security restrictions"
        echo ""
        echo -e "${YELLOW}To fix this issue:${NC}"
        echo "1. Open System Preferences > Security & Privacy"
        echo "2. Click 'Allow Anyway' for the blocked Real-ESRGAN binary"
        echo "3. Or run this command in terminal:"
        echo "   sudo xattr -rd com.apple.quarantine \"$REALESRGAN_BIN\""
        echo ""
        echo "Then run the script again."
        cd "$original_dir"
        exit 1
    fi
    
    # Clean up archive
    rm -f "$filename"
    
    cd "$original_dir"
    echo -e "${GREEN}  Real-ESRGAN-ncnn-vulkan setup complete${NC}"
}

# Check if Real-ESRGAN is available
check_realesrgan() {
    # First check if it's in PATH
    if command -v realesrgan-ncnn-vulkan &> /dev/null; then
        REALESRGAN_BIN="realesrgan-ncnn-vulkan"
        return 0
    fi
    
    # Check if it's in our local directory
    if [ -d "$REALESRGAN_DIR" ]; then
        local binary_name="realesrgan-ncnn-vulkan"
        local current_dir
        current_dir=$(pwd)
        
        # Check if binary is directly in the model directory
        if [ -f "$REALESRGAN_DIR/$binary_name" ]; then
            REALESRGAN_BIN="$current_dir/$REALESRGAN_DIR/$binary_name"
            # Test if binary actually works (check for macOS security issues)
            local test_output
            test_output=$("$REALESRGAN_BIN" -h 2>&1) || true
            if [[ "$test_output" == *"Usage: realesrgan-ncnn-vulkan"* ]]; then
                return 0
            else
                echo -e "${RED}Error:${NC} Real-ESRGAN binary is blocked by macOS security"
                echo ""
                echo -e "${YELLOW}To fix this issue:${NC}"
                echo "1. Open System Preferences > Security & Privacy"
                echo "2. Click 'Allow Anyway' for the blocked Real-ESRGAN binary"
                echo "3. Or run this command in terminal:"
                echo "   sudo xattr -rd com.apple.quarantine \"$REALESRGAN_BIN\""
                echo ""
                echo "Then run the script again."
                exit 1
            fi
        fi
        
        # Check in subdirectories (fallback)
        local extracted_dir
        extracted_dir=$(find "$REALESRGAN_DIR" -maxdepth 1 -type d -name "*Real-ESRGAN*" -o -name "*realesrgan*" | head -1)
        
        if [ -n "$extracted_dir" ]; then
            if [ -f "$extracted_dir/$binary_name" ]; then
                REALESRGAN_BIN="$current_dir/$extracted_dir/$binary_name"
                # Test if binary actually works (check for macOS security issues)
                local test_output
                test_output=$("$REALESRGAN_BIN" -h 2>&1) || true
                if [[ "$test_output" == *"Usage: realesrgan-ncnn-vulkan"* ]]; then
                    return 0
                else
                    echo -e "${RED}Error:${NC} Real-ESRGAN binary is blocked by macOS security"
                    echo ""
                    echo -e "${YELLOW}To fix this issue:${NC}"
                    echo "1. Open System Preferences > Security & Privacy"
                    echo "2. Click 'Allow Anyway' for the blocked Real-ESRGAN binary"
                    echo "3. Or run this command in terminal:"
                    echo "   sudo xattr -rd com.apple.quarantine \"$REALESRGAN_BIN\""
                    echo ""
                    echo "Then run the script again."
                    exit 1
                fi
            else
                # Look for .app bundle
                local app_bundle
                for app_bundle in "$extracted_dir"/*.app; do
                    if [ -f "$app_bundle/Contents/MacOS/$binary_name" ]; then
                        REALESRGAN_BIN="$current_dir/$app_bundle/Contents/MacOS/$binary_name"
                        # Test if binary actually works (check for macOS security issues)
                        local test_output
                        test_output=$("$REALESRGAN_BIN" -h 2>&1) || true
                        if [[ "$test_output" == *"Usage: realesrgan-ncnn-vulkan"* ]]; then
                            return 0
                        else
                            echo -e "${RED}Error:${NC} Real-ESRGAN binary is blocked by macOS security"
                            echo ""
                            echo -e "${YELLOW}To fix this issue:${NC}"
                            echo "1. Open System Preferences > Security & Privacy"
                            echo "2. Click 'Allow Anyway' for the blocked Real-ESRGAN binary"
                            echo "3. Or run this command in terminal:"
                            echo "   sudo xattr -rd com.apple.quarantine \"$REALESRGAN_BIN\""
                            echo ""
                            echo "Then run the script again."
                            exit 1
                        fi
                    fi
                done
            fi
        fi
    fi
    
    return 1
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
    
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi
    
    # Check for ImageMagick convert command for JPEG conversion
    if ! command -v convert &> /dev/null; then
        missing_tools+=("imagemagick")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${RED}Error: Missing required tools:${NC}"
        printf '%s\n' "${missing_tools[@]}"
        echo -e "\n${YELLOW}Install with:${NC}"
        echo "  macOS: brew install unzip zip curl imagemagick"
        echo "  Ubuntu/Debian: sudo apt install unzip zip curl imagemagick"
        exit 1
    fi
}

# Upscale and convert a single CBZ file
process_cbz() {
    local cbz_file="$1"
    local cbz_dir
    local cbz_name
    local temp_dir
    cbz_dir=$(dirname "$cbz_file")
    cbz_name=$(basename "$cbz_file" .cbz)
    temp_dir=$(mktemp -d)
    
    # Determine output directory - avoid nested "upscaled" directories
    local upscaled_dir
    if [[ "$cbz_dir" =~ /upscaled$ ]]; then
        # If input is already in an upscaled directory, use the parent directory's upscaled folder
        # but add a suffix to distinguish from the original
        upscaled_dir="$cbz_dir"
        cbz_name="${cbz_name}_upscaled"
    else
        # Otherwise, create upscaled subdirectory
        upscaled_dir="$cbz_dir/upscaled"
    fi
    
    local output_file="$upscaled_dir/${cbz_name}.cbz"
    local original_dir
    original_dir=$(pwd)
    
    # Convert output path to absolute path
    local abs_output_file
    abs_output_file="$original_dir/$output_file"
    
    # Convert to absolute path
    local abs_cbz_file
    abs_cbz_file=$(realpath "$cbz_file")
    
    echo -e "${YELLOW}Processing:${NC} $cbz_file"
    
    # Create upscaled directory if it doesn't exist
    if ! mkdir -p "$upscaled_dir"; then
        echo -e "${RED}  Error:${NC} Cannot create directory $upscaled_dir"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Skip if upscaled CBZ already exists
    if [ -f "$abs_output_file" ]; then
        echo -e "${YELLOW}  Skipping:${NC} Upscaled CBZ already exists"
        rm -rf "$temp_dir"
        return 0
    fi
    
    # Extract CBZ to temporary directory
    echo "  Extracting CBZ..."
    cd "$temp_dir"
    
    # Try different approaches to handle special characters in filenames
    extracted=false
    
    # Method 1: Try with jq option to flatten directory structure (avoids some encoding issues)
    if ! $extracted && unzip -j -q "$abs_cbz_file" 2>/dev/null; then
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
    
    # Find image files
    local image_files=()
    while IFS= read -r -d '' file; do
        image_files+=("$file")
    done < <(find . -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.bmp" -o -iname "*.webp" \) -print0 | sort -z)
    
    if [ ${#image_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}  Warning:${NC} No image files found in $cbz_file"
        cd "$original_dir"
        rm -rf "$temp_dir"
        return 0
    fi
    
    echo "  Found ${#image_files[@]} images to upscale"
    
    # Create upscaled directory
    mkdir -p upscaled
    
    # Process each image
    local processed=0
    for image_file in "${image_files[@]}"; do
        local basename
        basename=$(basename "$image_file")
        local name="${basename%.*}"
        local upscaled_png="upscaled/${name}.png"
        local final_jpg="upscaled/${name}.jpg"
        
        echo "    Upscaling: $basename"
        
        # Get absolute path to models directory
        local models_dir="$original_dir/$REALESRGAN_DIR/models"
        
        # Run Real-ESRGAN upscaling to PNG with model path
        if ! "$REALESRGAN_BIN" -i "$image_file" -o "$upscaled_png" -n "$MODEL" -s "$MODEL_SCALE" -m "$models_dir" > /dev/null 2>&1; then
            echo -e "${RED}    Error:${NC} Failed to upscale $basename"
            echo -e "${RED}  Error:${NC} Stopping processing of $cbz_file due to upscaling failure"
            cd "$original_dir"
            rm -rf "$temp_dir"
            return 1
        fi
        
        # Convert PNG to JPEG with specified quality
        local magick_cmd="magick \"$upscaled_png\""
        if [ "$NORMALIZE" = true ]; then
            magick_cmd="$magick_cmd -normalize"
        fi
        if [ "$RESIZE_PERCENT" -ne 100 ]; then
            magick_cmd="$magick_cmd -resize ${RESIZE_PERCENT}%"
        fi
        magick_cmd="$magick_cmd -quality \"$JPG_QUALITY\" \"$final_jpg\""
        
        if ! eval "$magick_cmd"; then
            echo -e "${RED}    Error:${NC} Failed to convert $basename to JPEG"
            echo -e "${RED}  Error:${NC} Stopping processing of $cbz_file due to conversion failure"
            rm -f "$upscaled_png"
            cd "$original_dir"
            rm -rf "$temp_dir"
            return 1
        fi
        
        # Remove intermediate PNG file
        rm -f "$upscaled_png"
        
        ((processed++))
    done
    
    if [ "$processed" -eq 0 ]; then
        echo -e "${RED}  Error:${NC} No images were successfully processed"
        cd "$original_dir"
        rm -rf "$temp_dir"
        return 1
    fi
    
    echo "  Successfully upscaled $processed images"
    
    # Create new CBZ archive
    echo "  Creating upscaled CBZ..."
    cd upscaled
    
    # Create the archive with a relative path first, then move it
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
        echo -e "${RED}  Debug:${NC} Trying to move from $(pwd)/$temp_cbz to $abs_output_file"
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
    
    # Find all CBZ files, excluding those in upscaled directories
    local cbz_files=()
    while IFS= read -r -d '' file; do
        cbz_files+=("$file")
    done < <(find "$dir" -type f -iname "*.cbz" -not -path "*/upscaled/*" -print0)
    
    if [ ${#cbz_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}No CBZ files found in $dir${NC}"
        return 0
    fi
    
    echo "Found ${#cbz_files[@]} CBZ file(s) to process"
    echo ""
    
    # Process each CBZ file
    for cbz_file in "${cbz_files[@]}"; do
        ((PROCESSED_COUNT++))
        
        if process_cbz "$cbz_file"; then
            ((SUCCESS_COUNT++))
        else
            ((ERROR_COUNT++))
        fi
        
        echo ""
    done
}

# Print statistics
print_statistics() {
    echo -e "${BLUE}Processing complete!${NC}"
    echo "Files processed: $PROCESSED_COUNT"
    echo -e "Successful: ${GREEN}$SUCCESS_COUNT${NC}"
    if [ $ERROR_COUNT -gt 0 ]; then
        echo -e "Errors: ${RED}$ERROR_COUNT${NC}"
    fi
}

# Main function
main() {
    echo -e "${BLUE}CBZ Upscaler (Real-ESRGAN)${NC}"
    local config_msg="Quality: $JPG_QUALITY, Model: $MODEL, Model-Scale: ${MODEL_SCALE}x, Resize: ${RESIZE_PERCENT}%"
    if [ "$NORMALIZE" = true ]; then
        config_msg="$config_msg, Normalize: enabled"
    fi
    echo "$config_msg"
    echo ""
    
    # Check dependencies
    check_dependencies
    
    # Check and setup Real-ESRGAN
    if ! check_realesrgan; then
        echo -e "${YELLOW}Real-ESRGAN-ncnn-vulkan not found, downloading...${NC}"
        setup_realesrgan
    else
        echo -e "${GREEN}Real-ESRGAN-ncnn-vulkan found${NC}"
    fi
    
    echo ""
    
    # Determine if input is a file or directory
    if [ -f "$SEARCH_DIR" ]; then
        # Single file
        if [[ "$SEARCH_DIR" =~ \.cbz$ ]]; then
            ((PROCESSED_COUNT++))
            if process_cbz "$SEARCH_DIR"; then
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
