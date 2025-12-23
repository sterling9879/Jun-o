#!/bin/bash
#===============================================================================
# Video Reverser - Installation Script
# Installs FFMPEG and configures the environment for video concatenation
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/video-reverser.log"

#===============================================================================
# Functions
#===============================================================================

print_header() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║           Video Reverser - Installation Script                ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
    esac

    # Log to file if possible
    if [ -w "$(dirname "$LOG_FILE")" ] || [ -w "$LOG_FILE" ]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        VERSION=$(cat /etc/debian_version)
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
    else
        OS=$(uname -s)
    fi

    echo "$OS"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_message "WARN" "Script not running as root. Some operations may require sudo."
        SUDO="sudo"
    else
        SUDO=""
    fi
}

install_ffmpeg_debian() {
    log_message "INFO" "Updating package lists..."
    $SUDO apt-get update -qq

    log_message "INFO" "Installing FFMPEG..."
    $SUDO apt-get install -y ffmpeg
}

install_ffmpeg_centos() {
    log_message "INFO" "Installing EPEL repository..."
    $SUDO yum install -y epel-release

    log_message "INFO" "Installing FFMPEG..."
    $SUDO yum install -y ffmpeg ffmpeg-devel
}

install_ffmpeg_fedora() {
    log_message "INFO" "Installing FFMPEG..."
    $SUDO dnf install -y ffmpeg
}

install_ffmpeg() {
    local os=$(detect_os)

    log_message "INFO" "Detected OS: $os"

    case $os in
        ubuntu|debian)
            install_ffmpeg_debian
            ;;
        centos|rhel)
            install_ffmpeg_centos
            ;;
        fedora)
            install_ffmpeg_fedora
            ;;
        *)
            log_message "ERROR" "Unsupported OS: $os"
            log_message "INFO" "Please install FFMPEG manually and re-run this script."
            exit 1
            ;;
    esac
}

check_ffmpeg() {
    if command -v ffmpeg &> /dev/null; then
        local version=$(ffmpeg -version | head -n1 | awk '{print $3}')
        log_message "INFO" "FFMPEG is installed (version: $version)"
        return 0
    else
        return 1
    fi
}

create_directories() {
    log_message "INFO" "Creating directory structure..."

    mkdir -p "$SCRIPT_DIR/input"
    mkdir -p "$SCRIPT_DIR/output"

    log_message "INFO" "Created: $SCRIPT_DIR/input"
    log_message "INFO" "Created: $SCRIPT_DIR/output"
}

set_permissions() {
    log_message "INFO" "Setting script permissions..."

    chmod +x "$SCRIPT_DIR/install.sh" 2>/dev/null || true
    chmod +x "$SCRIPT_DIR/process.sh" 2>/dev/null || true

    # Set directory permissions
    chmod 755 "$SCRIPT_DIR/input"
    chmod 755 "$SCRIPT_DIR/output"

    log_message "INFO" "Permissions configured successfully"
}

setup_log_file() {
    log_message "INFO" "Setting up log file..."

    # Try to create log file in /var/log
    if [ -w "/var/log" ] || [ "$EUID" -eq 0 ]; then
        $SUDO touch "$LOG_FILE" 2>/dev/null || true
        $SUDO chmod 666 "$LOG_FILE" 2>/dev/null || true
        log_message "INFO" "Log file created: $LOG_FILE"
    else
        # Fallback to local log
        LOG_FILE="$SCRIPT_DIR/video-reverser.log"
        touch "$LOG_FILE"
        log_message "WARN" "Cannot write to /var/log, using local log: $LOG_FILE"
    fi
}

validate_installation() {
    echo ""
    log_message "INFO" "Validating installation..."

    local errors=0

    # Check FFMPEG
    if check_ffmpeg; then
        echo -e "  ${GREEN}✓${NC} FFMPEG installed"
    else
        echo -e "  ${RED}✗${NC} FFMPEG not found"
        ((errors++))
    fi

    # Check directories
    if [ -d "$SCRIPT_DIR/input" ]; then
        echo -e "  ${GREEN}✓${NC} Input directory exists"
    else
        echo -e "  ${RED}✗${NC} Input directory missing"
        ((errors++))
    fi

    if [ -d "$SCRIPT_DIR/output" ]; then
        echo -e "  ${GREEN}✓${NC} Output directory exists"
    else
        echo -e "  ${RED}✗${NC} Output directory missing"
        ((errors++))
    fi

    # Check process.sh
    if [ -f "$SCRIPT_DIR/process.sh" ] && [ -x "$SCRIPT_DIR/process.sh" ]; then
        echo -e "  ${GREEN}✓${NC} Process script ready"
    else
        echo -e "  ${YELLOW}!${NC} Process script not found or not executable"
    fi

    echo ""

    if [ $errors -eq 0 ]; then
        log_message "INFO" "Installation validated successfully!"
        return 0
    else
        log_message "ERROR" "Installation validation failed with $errors error(s)"
        return 1
    fi
}

print_usage() {
    echo ""
    echo -e "${BLUE}=== Usage Instructions ===${NC}"
    echo ""
    echo "1. Place your numbered video files in the input/ folder:"
    echo "   cp /path/to/videos/*.mp4 $SCRIPT_DIR/input/"
    echo ""
    echo "2. Run the processing script:"
    echo "   ./process.sh"
    echo ""
    echo "3. Find your reversed video in the output/ folder"
    echo ""
    echo "Available options for process.sh:"
    echo "  --output-name NAME   Custom output filename"
    echo "  --clean              Clean input folder after success"
    echo "  --force              Ignore sequence gaps"
    echo "  --reencode           Re-encode videos (slower but compatible)"
    echo "  --help               Show help message"
    echo ""
}

#===============================================================================
# Main Installation
#===============================================================================

main() {
    print_header
    check_root
    setup_log_file

    log_message "INFO" "Starting installation..."

    # Check if FFMPEG is already installed
    if check_ffmpeg; then
        log_message "INFO" "FFMPEG already installed, skipping installation"
    else
        log_message "INFO" "FFMPEG not found, installing..."
        install_ffmpeg
    fi

    # Create directories
    create_directories

    # Set permissions
    set_permissions

    # Validate
    if validate_installation; then
        echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║              Installation completed successfully!             ║${NC}"
        echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
        print_usage
    else
        echo -e "${RED}Installation completed with errors. Please check the logs.${NC}"
        exit 1
    fi
}

# Run main function
main "$@"
