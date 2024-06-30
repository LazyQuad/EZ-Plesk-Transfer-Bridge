#!/bin/bash
clear 

SCRIPT_NAME="EZ-Plesk-Transfer-Bridge-Log-Cleaner"
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"

echo "========================================================"
echo "$SCRIPT_NAME v$VERSION"
echo "========================================================"
echo

# Function to delete old log files
cleanup_logs() {
    local days=$1
    local count=0
    
    echo "Cleaning up log files older than $days days..."
    
    if [ ! -d "$LOG_DIR" ]; then
        echo "Log directory not found: $LOG_DIR"
        return 1
    fi
    
    while IFS= read -r file; do
        rm -f "$file"
        ((count++))
    done < <(find "$LOG_DIR" -type f -name "*.log" -mtime +$days)
    
    echo "Cleaned up $count log file(s)."
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -d, --days NUMBER   Delete log files older than NUMBER days (default: 30)"
    echo "  -a, --all           Delete all log files"
    echo "  -h, --help          Show this help message"
}

# Main script execution
main() {
    local days=30
    local delete_all=false

    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--days)
                days="$2"
                shift 2
                ;;
            -a|--all)
                delete_all=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    if [ "$delete_all" = true ]; then
        echo "Deleting all log files..."
        rm -f "$LOG_DIR"/*.log
        echo "All log files have been deleted."
    else
        cleanup_logs "$days"
    fi
}

main "$@"