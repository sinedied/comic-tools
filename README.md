# Comic Tools

A collection of command-line tools for processing, converting, and validating digital comics in different formats.

> **Note:** These scripts were generated with the assistance of [GitHub Copilot](https://github.com/features/copilot), an AI-powered coding tool.

## Tools Included

### `cbr2cbz.sh` - CBR to CBZ Converter
Converts CBR (Comic Book RAR) files to CBZ (Comic Book ZIP) format recursively.

**Features:**
- Recursive directory processing
- Preserves original file structure
- Color-coded output with progress tracking
- Error handling and statistics reporting
- Automatic cleanup of temporary files

**Requirements:**
- `unrar` - for extracting RAR archives
- `zip` - for creating ZIP archives

### `pdf2cbz.sh` - PDF to CBZ Converter
Converts PDF files to CBZ format by extracting embedded images.

**Features:**
- Extracts images from PDF files (no loss of quality)
- Creates organized CBZ archives
- Progress tracking and error reporting
- Handles various image formats within PDFs

**Requirements:**
- `pdfimages` (from poppler-utils) - for extracting images from PDFs
- `zip` - for creating ZIP archives

### `upscale-cbz.sh` - CBZ Image Upscaler
Upscales images in CBZ files using AI-powered Real-ESRGAN-ncnn-vulkan and recompresses them as high-quality JPEG.

**Features:**
- Automatic download and setup of Real-ESRGAN-ncnn-vulkan (first run)
- AI-powered image upscaling with multiple models available
- Configurable scale factors and JPEG quality output
- Batch processing of directories
- Cross-platform support (macOS and Linux)
- High-quality JPEG output with customizable quality settings

**Requirements:**
- `unzip` - for extracting CBZ archives
- `zip` - for creating CBZ archives
- `curl` - for downloading Real-ESRGAN
- `imagemagick` (convert command) - for JPEG conversion with quality control
- Vulkan-compatible GPU (recommended for performance)

### `check-format.sh` - Comic Archive Format Validator
Validates that comic archive files have the correct headers matching their file extensions.

**Features:**
- Checks CBZ files for proper ZIP headers
- Checks CBR files for proper RAR headers
- Single file or recursive directory processing
- Case-insensitive file extension detection
- Clear categorization of mismatched formats
- Cross-platform compatibility (macOS and Linux)

**Requirements:**
- `hexdump` - for reading file headers (standard on Unix systems)
- `find` - for recursive directory search (standard on Unix systems)

## Installation

### macOS (using Homebrew)
```bash
# For CBR to CBZ conversion
brew install rar zip

# For PDF to CBZ conversion
brew install poppler zip

# For CBZ upscaling
brew install imagemagick
```

### Ubuntu/Debian
```bash
# For CBR to CBZ conversion
sudo apt install unrar zip

# For PDF to CBZ conversion
sudo apt install poppler-utils zip

# For CBZ upscaling
sudo apt install imagemagick
```

## Usage

### Convert CBR files to CBZ
```bash
# Convert all CBR files in current directory
./cbr2cbz.sh

# Convert all CBR files in a specific directory
./cbr2cbz.sh /path/to/comics/directory
```

### Convert PDF files to CBZ
```bash
# Convert all PDF files in current directory
./pdf2cbz.sh

# Convert all PDF files in a specific directory
./pdf2cbz.sh /path/to/pdf/directory
```

### Upscale CBZ files
```bash
# Upscale a single CBZ file (4x scale, 90% JPEG quality)
./upscale-cbz.sh comic.cbz

# Upscale all CBZ files in a directory with custom quality
./upscale-cbz.sh /path/to/comics/ --quality 85

# Use different AI model for anime-style art
./upscale-cbz.sh comic.cbz --model realesrgan-x4plus-anime

# High quality upscale
./upscale-cbz.sh comic.cbz --quality 95

# Show all available options
./upscale-cbz.sh --help
```

### Check comic archive formats
```bash
# Check all comic files in current directory
./check-format.sh

# Check all comic files in a specific directory
./check-format.sh /path/to/comics/

# Check a single CBZ file
./check-format.sh comic.cbz

# Check a single CBR file
./check-format.sh comic.cbr

# Show help and output format details
./check-format.sh --help
```

## Output

- **CBR/PDF conversion**: Converted files are saved in a `converted/` subdirectory
- **CBZ upscaling**: Upscaled files are saved in an `upscaled/` subdirectory with original filenames
- Original files are preserved (not deleted)
- Progress and statistics are displayed during conversion
- Error messages are shown for any files that fail to convert

## AI Upscaling Details

The upscaler uses [Real-ESRGAN-ncnn-vulkan](https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan) for high-quality image enhancement:

- **realesrgan-x4plus**: General purpose model, good for most images (4x upscale)
- **realesrgan-x4plus-anime**: Specialized for anime/artwork style images (4x upscale)
- **realesr-animevideov3**: Optimized for anime video frames (4x upscale)
- Automatic first-time download and setup
- GPU acceleration via Vulkan (falls back to CPU if needed)
- PNG intermediate output converted to JPEG with configurable quality
- Typically uses 4x scale factor (model-dependent)

## File Formats

- **CBR**: Comic Book RAR - RAR compressed archive containing comic images
- **CBZ**: Comic Book ZIP - ZIP compressed archive containing comic images
- **PDF**: Portable Document Format - may contain embedded comic images
