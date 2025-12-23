#!/bin/bash
#===============================================================================
# Video Reverser - Web Interface Installation Script
#===============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║       Video Reverser - Web Interface Installation             ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_message() {
    local level="$1"
    local message="$2"

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
}

check_python() {
    log_message "INFO" "Checking Python..."

    if command -v python3 &> /dev/null; then
        PYTHON=python3
        PIP="python3 -m pip"
        log_message "INFO" "Found Python 3: $(python3 --version)"
    elif command -v python &> /dev/null; then
        PYTHON=python
        PIP="python -m pip"
        log_message "INFO" "Found Python: $(python --version)"
    else
        log_message "ERROR" "Python not found!"
        log_message "INFO" "Please install Python 3.8 or higher"
        exit 1
    fi
}

install_dependencies() {
    log_message "INFO" "Installing Python dependencies..."

    $PIP install --upgrade pip
    $PIP install -r "$SCRIPT_DIR/requirements.txt"

    log_message "INFO" "Dependencies installed successfully"
}

check_ffmpeg() {
    log_message "INFO" "Checking FFMPEG..."

    if command -v ffmpeg &> /dev/null; then
        log_message "INFO" "FFMPEG found: $(ffmpeg -version | head -n1)"
    else
        log_message "WARN" "FFMPEG not found!"
        log_message "INFO" "Run the main install.sh first: cd .. && ./install.sh"
    fi
}

set_permissions() {
    log_message "INFO" "Setting permissions..."

    chmod +x "$SCRIPT_DIR/start.sh"
    chmod +x "$SCRIPT_DIR/app.py"

    mkdir -p "$PARENT_DIR/input"
    mkdir -p "$PARENT_DIR/output"

    log_message "INFO" "Permissions set"
}

print_usage() {
    echo ""
    echo -e "${BLUE}=== Usage Instructions ===${NC}"
    echo ""
    echo "Start the web server:"
    echo "  ./start.sh"
    echo ""
    echo "With options:"
    echo "  ./start.sh --port 8080"
    echo "  ./start.sh --production"
    echo ""
    echo "Then open in your browser:"
    echo "  http://localhost:5000"
    echo ""
}

# Main
print_header
check_python
install_dependencies
check_ffmpeg
set_permissions

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          Web Interface installed successfully!               ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"

print_usage
