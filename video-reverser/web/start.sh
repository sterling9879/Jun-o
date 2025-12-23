#!/bin/bash
#===============================================================================
# Video Reverser - Web Interface Startup Script
#===============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default port
PORT=${PORT:-5000}
HOST=${HOST:-0.0.0.0}
MODE=${MODE:-development}

print_header() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║            Video Reverser - Web Interface                     ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_python() {
    if command -v python3 &> /dev/null; then
        PYTHON=python3
    elif command -v python &> /dev/null; then
        PYTHON=python
    else
        echo -e "${YELLOW}Python not found. Please install Python 3.${NC}"
        exit 1
    fi
}

check_dependencies() {
    echo -e "${GREEN}[INFO]${NC} Checking dependencies..."

    if ! $PYTHON -c "import flask" 2>/dev/null; then
        echo -e "${YELLOW}[WARN]${NC} Flask not installed. Installing..."
        $PYTHON -m pip install -r "$SCRIPT_DIR/requirements.txt"
    fi

    if ! command -v ffmpeg &> /dev/null; then
        echo -e "${YELLOW}[WARN]${NC} FFMPEG not found. Please run install.sh first."
        exit 1
    fi
}

create_directories() {
    mkdir -p "$PARENT_DIR/input"
    mkdir -p "$PARENT_DIR/output"
}

start_server() {
    echo -e "${GREEN}[INFO]${NC} Starting server..."
    echo ""
    echo -e "  Mode:   ${BLUE}$MODE${NC}"
    echo -e "  Host:   ${BLUE}$HOST${NC}"
    echo -e "  Port:   ${BLUE}$PORT${NC}"
    echo -e "  URL:    ${BLUE}http://$HOST:$PORT${NC}"
    echo ""

    cd "$SCRIPT_DIR"

    if [ "$MODE" = "production" ]; then
        # Production mode with Gunicorn
        if command -v gunicorn &> /dev/null; then
            gunicorn -w 4 -b "$HOST:$PORT" app:app
        else
            echo -e "${YELLOW}[WARN]${NC} Gunicorn not found, using Flask development server"
            $PYTHON app.py
        fi
    else
        # Development mode
        export FLASK_ENV=development
        export FLASK_DEBUG=1
        $PYTHON app.py
    fi
}

show_help() {
    echo "Usage: ./start.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --port PORT       Set server port (default: 5000)"
    echo "  --host HOST       Set server host (default: 0.0.0.0)"
    echo "  --production      Run in production mode with Gunicorn"
    echo "  --help            Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  PORT              Server port"
    echo "  HOST              Server host"
    echo "  MODE              'development' or 'production'"
    echo ""
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --port)
            PORT="$2"
            shift 2
            ;;
        --host)
            HOST="$2"
            shift 2
            ;;
        --production)
            MODE="production"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main
print_header
check_python
check_dependencies
create_directories
start_server
