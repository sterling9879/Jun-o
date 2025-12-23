#!/bin/bash
#===============================================================================
# Video Reverser - Processing Script
# Concatenates numbered video files in REVERSE order using FFMPEG
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_DIR="$SCRIPT_DIR/input"
OUTPUT_DIR="$SCRIPT_DIR/output"
TEMP_FILE="$SCRIPT_DIR/.filelist_temp.txt"
LOG_FILE="/var/log/video-reverser.log"

# Default options
OUTPUT_NAME="final.mp4"
CLEAN_INPUT=false
FORCE_PROCESS=false
REENCODE=false
VERBOSE=false

# Supported video extensions
VIDEO_EXTENSIONS=("mp4" "mov" "avi" "mkv" "webm" "m4v" "wmv" "flv")

# Processing stats
START_TIME=0
VIDEOS_COUNT=0
FINAL_SIZE=""
FINAL_DURATION=""

#===============================================================================
# Functions
#===============================================================================

print_header() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                    === Video Reverser ===                     ║"
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
        "DEBUG")
            if [ "$VERBOSE" = true ]; then
                echo -e "${MAGENTA}[DEBUG]${NC} $message"
            fi
            ;;
    esac

    # Log to file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
}

show_help() {
    echo -e "${BOLD}Video Reverser - Concatenate videos in reverse order${NC}"
    echo ""
    echo "Usage: ./process.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --output-name NAME   Set custom output filename (default: final.mp4)"
    echo "  --clean              Clean input folder after successful processing"
    echo "  --force              Ignore sequence gaps and process anyway"
    echo "  --reencode           Re-encode videos (slower, but ensures compatibility)"
    echo "  --verbose            Show detailed processing information"
    echo "  --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./process.sh"
    echo "  ./process.sh --output-name my_video.mp4 --clean"
    echo "  ./process.sh --force --reencode"
    echo ""
    echo "Supported formats: ${VIDEO_EXTENSIONS[*]}"
    echo ""
}

check_dependencies() {
    log_message "INFO" "Checking dependencies..."

    if ! command -v ffmpeg &> /dev/null; then
        log_message "ERROR" "FFMPEG is not installed!"
        log_message "INFO" "Run ./install.sh first or install FFMPEG manually."
        exit 1
    fi

    if ! command -v ffprobe &> /dev/null; then
        log_message "ERROR" "ffprobe is not installed!"
        log_message "INFO" "Run ./install.sh first or install FFMPEG manually."
        exit 1
    fi

    log_message "DEBUG" "All dependencies satisfied"
}

check_directories() {
    if [ ! -d "$INPUT_DIR" ]; then
        log_message "ERROR" "Input directory not found: $INPUT_DIR"
        log_message "INFO" "Run ./install.sh first to create directory structure."
        exit 1
    fi

    if [ ! -d "$OUTPUT_DIR" ]; then
        log_message "WARN" "Output directory not found, creating..."
        mkdir -p "$OUTPUT_DIR"
    fi
}

build_extension_pattern() {
    local pattern=""
    for ext in "${VIDEO_EXTENSIONS[@]}"; do
        if [ -n "$pattern" ]; then
            pattern="$pattern|"
        fi
        pattern="$pattern$ext"
    done
    echo "$pattern"
}

scan_videos() {
    log_message "INFO" "Escaneando pasta input/..."

    local ext_pattern=$(build_extension_pattern)

    # Find all video files and sort them
    mapfile -t VIDEO_FILES < <(find "$INPUT_DIR" -maxdepth 1 -type f -regextype posix-extended \
        -iregex ".*\.($ext_pattern)$" 2>/dev/null | sort -V)

    VIDEOS_COUNT=${#VIDEO_FILES[@]}

    if [ "$VIDEOS_COUNT" -eq 0 ]; then
        log_message "ERROR" "Nenhum video encontrado na pasta input/"
        log_message "INFO" "Formatos suportados: ${VIDEO_EXTENSIONS[*]}"
        exit 1
    fi

    log_message "DEBUG" "Found $VIDEOS_COUNT video files"
}

detect_numbering_pattern() {
    local first_file=$(basename "${VIDEO_FILES[0]}")
    local last_file=$(basename "${VIDEO_FILES[-1]}")

    # Extract numbers from filenames
    FIRST_NUM=$(echo "$first_file" | grep -oE '^[0-9]+' | head -1)
    LAST_NUM=$(echo "$last_file" | grep -oE '^[0-9]+' | head -1)

    # Detect padding (number of digits)
    if [ -n "$FIRST_NUM" ]; then
        NUM_PADDING=${#FIRST_NUM}
    else
        NUM_PADDING=0
    fi

    log_message "DEBUG" "Numbering pattern: $NUM_PADDING digits, range $FIRST_NUM to $LAST_NUM"
}

validate_sequence() {
    log_message "INFO" "Validando sequencia..."

    local missing_files=()
    local expected_count=0

    if [ -n "$FIRST_NUM" ] && [ -n "$LAST_NUM" ]; then
        # Convert to integer (remove leading zeros)
        local first_int=$((10#$FIRST_NUM))
        local last_int=$((10#$LAST_NUM))

        expected_count=$((last_int - first_int + 1))

        # Check for gaps
        for ((i=first_int; i<=last_int; i++)); do
            local padded_num=$(printf "%0${NUM_PADDING}d" $i)
            local found=false

            for video in "${VIDEO_FILES[@]}"; do
                local basename=$(basename "$video")
                if [[ "$basename" =~ ^${padded_num}\. ]]; then
                    found=true
                    break
                fi
            done

            if [ "$found" = false ]; then
                missing_files+=("$padded_num")
            fi
        done
    fi

    # Report findings
    local first_basename=$(basename "${VIDEO_FILES[0]}")
    local last_basename=$(basename "${VIDEO_FILES[-1]}")

    echo -e "Encontrados: ${BOLD}${CYAN}$VIDEOS_COUNT${NC} videos (${first_basename} ate ${last_basename})"

    if [ ${#missing_files[@]} -gt 0 ]; then
        echo -e "Sequencia: ${YELLOW}incompleta${NC} (faltando ${#missing_files[@]} arquivos)"
        echo -e "${YELLOW}Arquivos faltando:${NC} ${missing_files[*]}"

        if [ "$FORCE_PROCESS" = false ]; then
            echo ""
            read -p "Deseja continuar mesmo assim? (s/N) " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Ss]$ ]]; then
                log_message "INFO" "Processamento cancelado pelo usuario."
                exit 0
            fi
        else
            log_message "WARN" "Gaps na sequencia ignorados (--force)"
        fi
    else
        echo -e "Sequencia: ${GREEN}completa${NC} ${GREEN}✓${NC}"
    fi
}

generate_reversed_list() {
    echo ""
    log_message "INFO" "Gerando ordem inversa..."

    # Clear temp file
    > "$TEMP_FILE"

    # Reverse the array
    local reversed_files=()
    for ((i=${#VIDEO_FILES[@]}-1; i>=0; i--)); do
        reversed_files+=("${VIDEO_FILES[$i]}")
    done

    # Generate file list for FFMPEG concat demuxer
    for video in "${reversed_files[@]}"; do
        echo "file '$video'" >> "$TEMP_FILE"
    done

    # Display order preview
    local preview_count=5
    echo -n -e "${CYAN}"

    local total=${#reversed_files[@]}
    if [ "$total" -le $((preview_count * 2 + 1)) ]; then
        # Show all files if not too many
        local names=()
        for video in "${reversed_files[@]}"; do
            names+=("$(basename "$video")")
        done
        echo "${names[*]}" | sed 's/ / → /g'
    else
        # Show first few, ..., last few
        local preview=""
        for ((i=0; i<preview_count; i++)); do
            if [ $i -gt 0 ]; then
                preview+=" → "
            fi
            preview+="$(basename "${reversed_files[$i]}")"
        done
        preview+=" → ... → "
        for ((i=total-2; i<total; i++)); do
            preview+="$(basename "${reversed_files[$i]}")"
            if [ $i -lt $((total-1)) ]; then
                preview+=" → "
            fi
        done
        echo "$preview"
    fi
    echo -e "${NC}"

    log_message "DEBUG" "File list generated: $TEMP_FILE"
}

get_video_duration() {
    local file="$1"
    ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "0"
}

format_duration() {
    local seconds="$1"
    local hours=$((${seconds%.*} / 3600))
    local minutes=$(((${seconds%.*} % 3600) / 60))
    local secs=$((${seconds%.*} % 60))
    printf "%02d:%02d:%02d" $hours $minutes $secs
}

format_size() {
    local bytes="$1"
    if [ "$bytes" -ge 1073741824 ]; then
        echo "$(echo "scale=2; $bytes/1073741824" | bc) GB"
    elif [ "$bytes" -ge 1048576 ]; then
        echo "$(echo "scale=2; $bytes/1048576" | bc) MB"
    elif [ "$bytes" -ge 1024 ]; then
        echo "$(echo "scale=2; $bytes/1024" | bc) KB"
    else
        echo "$bytes bytes"
    fi
}

show_progress_bar() {
    local current="$1"
    local total="$2"
    local width=50

    local progress=$((current * width / total))
    local remaining=$((width - progress))

    printf "\r["
    printf "%${progress}s" | tr ' ' '█'
    printf "%${remaining}s" | tr ' ' ' '
    printf "] %3d%%" $((current * 100 / total))
}

concatenate_videos() {
    echo ""
    log_message "INFO" "Concatenando com FFMPEG..."

    local output_file="$OUTPUT_DIR/$OUTPUT_NAME"
    local ffmpeg_log="$SCRIPT_DIR/.ffmpeg_log.txt"

    # Remove existing output if exists
    rm -f "$output_file"

    # Calculate total duration for progress
    local total_duration=0
    for video in "${VIDEO_FILES[@]}"; do
        local dur=$(get_video_duration "$video")
        total_duration=$(echo "$total_duration + $dur" | bc 2>/dev/null || echo "$total_duration")
    done

    if [ "$REENCODE" = true ]; then
        log_message "INFO" "Re-encoding enabled (this may take a while)..."

        # Re-encode with common settings
        ffmpeg -y -f concat -safe 0 -i "$TEMP_FILE" \
            -c:v libx264 -preset medium -crf 23 \
            -c:a aac -b:a 192k \
            -movflags +faststart \
            -progress pipe:1 \
            "$output_file" 2>"$ffmpeg_log" | \
        while IFS='=' read -r key value; do
            if [ "$key" = "out_time_us" ]; then
                local current_us="$value"
                local current_sec=$((current_us / 1000000))
                if [ "${total_duration%.*}" -gt 0 ]; then
                    show_progress_bar "$current_sec" "${total_duration%.*}"
                fi
            fi
        done
    else
        # Stream copy (fast, no re-encoding)
        ffmpeg -y -f concat -safe 0 -i "$TEMP_FILE" \
            -c copy \
            -movflags +faststart \
            -progress pipe:1 \
            "$output_file" 2>"$ffmpeg_log" | \
        while IFS='=' read -r key value; do
            if [ "$key" = "out_time_us" ]; then
                local current_us="$value"
                local current_sec=$((current_us / 1000000))
                if [ "${total_duration%.*}" -gt 0 ]; then
                    show_progress_bar "$current_sec" "${total_duration%.*}"
                fi
            fi
        done
    fi

    # Complete progress bar
    echo -e "\r[${GREEN}██████████████████████████████████████████████████${NC}] 100%"

    # Check if output was created
    if [ ! -f "$output_file" ]; then
        echo ""
        log_message "ERROR" "Falha ao criar o arquivo de saida!"
        if [ -f "$ffmpeg_log" ]; then
            log_message "ERROR" "Log do FFMPEG:"
            tail -20 "$ffmpeg_log"
        fi
        cleanup
        exit 1
    fi

    # Get output stats
    FINAL_SIZE=$(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file" 2>/dev/null || echo "0")
    FINAL_DURATION=$(get_video_duration "$output_file")

    # Cleanup ffmpeg log
    rm -f "$ffmpeg_log"

    log_message "DEBUG" "Concatenation completed: $output_file"
}

cleanup() {
    log_message "DEBUG" "Cleaning up temporary files..."
    rm -f "$TEMP_FILE"
    rm -f "$SCRIPT_DIR/.ffmpeg_log.txt"
}

clean_input() {
    if [ "$CLEAN_INPUT" = true ]; then
        log_message "INFO" "Limpando pasta input/..."
        for video in "${VIDEO_FILES[@]}"; do
            rm -f "$video"
        done
        log_message "INFO" "Pasta input/ limpa com sucesso"
    fi
}

show_summary() {
    local end_time=$(date +%s)
    local elapsed=$((end_time - START_TIME))
    local output_file="$OUTPUT_DIR/$OUTPUT_NAME"

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                       ${BOLD}✓ Concluido!${NC}${GREEN}                            ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  - Videos processados:     ${CYAN}$VIDEOS_COUNT${NC}"
    echo -e "  - Arquivo final:          ${CYAN}$output_file${NC}"
    echo -e "  - Tamanho:                ${CYAN}$(format_size $FINAL_SIZE)${NC}"
    echo -e "  - Duracao:                ${CYAN}$(format_duration $FINAL_DURATION)${NC}"
    echo -e "  - Tempo de processamento: ${CYAN}${elapsed}s${NC}"
    echo ""

    # Log final summary
    log_message "INFO" "Processing completed: $VIDEOS_COUNT videos -> $output_file"
    log_message "INFO" "Final size: $(format_size $FINAL_SIZE), Duration: $(format_duration $FINAL_DURATION)"
}

#===============================================================================
# Parse Arguments
#===============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --output-name)
                OUTPUT_NAME="$2"
                shift 2
                ;;
            --clean)
                CLEAN_INPUT=true
                shift
                ;;
            --force)
                FORCE_PROCESS=true
                shift
                ;;
            --reencode)
                REENCODE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_message "ERROR" "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done

    # Ensure output name has extension
    if [[ ! "$OUTPUT_NAME" =~ \.[a-zA-Z0-9]+$ ]]; then
        OUTPUT_NAME="${OUTPUT_NAME}.mp4"
    fi
}

#===============================================================================
# Main Processing
#===============================================================================

main() {
    START_TIME=$(date +%s)

    print_header
    parse_args "$@"

    # Pre-flight checks
    check_dependencies
    check_directories

    # Scan and validate
    scan_videos
    detect_numbering_pattern
    validate_sequence

    # Process
    generate_reversed_list
    concatenate_videos

    # Cleanup
    cleanup
    clean_input

    # Done!
    show_summary
}

# Trap for cleanup on exit
trap cleanup EXIT

# Run main function with all arguments
main "$@"
