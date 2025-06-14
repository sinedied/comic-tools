# Comic Tools

A collection of command-line tools for processing and converting digital comics into different formats.

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
- Extracts images from PDF files
- Creates organized CBZ archives
- Progress tracking and error reporting
- Handles various image formats within PDFs

**Requirements:**
- `pdfimages` (from poppler-utils) - for extracting images from PDFs
- `zip` - for creating ZIP archives

## Installation

### macOS (using Homebrew)
```bash
# For CBR to CBZ conversion
brew install rar

# For PDF to CBZ conversion
brew install poppler
```

### Ubuntu/Debian
```bash
# For CBR to CBZ conversion
sudo apt install unrar zip

# For PDF to CBZ conversion
sudo apt install poppler-utils zip
```

### CentOS/RHEL
```bash
# For CBR to CBZ conversion
sudo yum install unrar zip

# For PDF to CBZ conversion
sudo yum install poppler-utils zip
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

## Output

- Converted files are saved in a `converted/` subdirectory within each processed directory
- Original files are preserved (not deleted)
- Progress and statistics are displayed during conversion
- Error messages are shown for any files that fail to convert

## File Formats

- **CBR**: Comic Book RAR - RAR compressed archive containing comic images
- **CBZ**: Comic Book ZIP - ZIP compressed archive containing comic images
- **PDF**: Portable Document Format - may contain embedded comic images

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve these tools.
