#!/bin/bash
clear
# Enable command-line editing
if [[ $- == *i* ]]; then
    bind '"\e[A": history-search-backward'
    bind '"\e[B": history-search-forward'
fi

# Set up history
HISTFILE="/tmp/.ez_plesk_transfer_history"
HISTFILESIZE=1000
HISTSIZE=1000
set -o history

VERSION="1.2.0"
SCRIPT_NAME="EZ-Plesk-Transfer-Bridge-Pro"
GITHUB_PAGE="https://github.com/LazyQuad/EZ-Plesk-Transfer-Bridge"

echo "========================================================"
echo "$SCRIPT_NAME v$VERSION"
echo "GitHub: $GITHUB_PAGE"
echo "========================================================"
echo

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CONFIG_FILE="$SCRIPT_DIR/config/Pro-Config.conf"
CONFIG_FILE="$DEFAULT_CONFIG_FILE"
LOG_FILE="$SCRIPT_DIR/logs/transfer_bridge_$(date +'%Y%m%d_%H%M%S').log"
DRY_RUN=false
COMPRESS_BACKUP=false
MIGRATE_SSL=false
COMPONENTS_TO_MIGRATE="all"
VERBOSE=false
USE_KEY_AUTH=false
SSH_KEY_PATH=""
CLEANUP_HISTORY=false


log_message() {
    local level="$1"
    local message="$2"
    echo "$(date +'%Y-%m-%d %H:%M:%S') [$level] - $message" | tee -a "$LOG_FILE"
    echo  # Add a newline for readability
}

setup_logging() {
    local log_dir="$SCRIPT_DIR/logs"
    
    if [ ! -d "$log_dir" ]; then
        echo "Log directory does not exist. Creating it now."
        mkdir -p "$log_dir"
        if [ $? -ne 0 ]; then
            echo "Failed to create log directory. Please check permissions."
            return 1
        fi
    fi

    if [ ! -w "$log_dir" ]; then
        echo "Log directory is not writable. Attempting to set correct permissions."
        chmod 755 "$log_dir"
        if [ $? -ne 0 ]; then
            echo "Failed to set permissions on log directory. Please check permissions."
            return 1
        fi
    fi

    LOG_FILE="$log_dir/transfer_bridge_$(date +'%Y%m%d_%H%M%S').log"

    touch "$LOG_FILE" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "Cannot write to log file. Please check permissions."
        return 1
    fi

    echo "Logging setup completed successfully. Log file: $LOG_FILE"
    return 0
}

verbose_log() {
    if [ "$VERBOSE" = true ]; then
        echo "$1"
    fi
}

prompt_input() {
    read -e -p "$1 [$2]: " input
    echo "${input:-$2}"
}

prompt_password() {
    read -s -p "$1: " password
    echo
    echo "$password"
}

check_ssh_connection() {
    local user_host=$1
    local port=$2
    local max_retries=3
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        if [ "$USE_KEY_AUTH" = true ]; then
            ssh -q -o BatchMode=yes -o ConnectTimeout=5 -p "$port" -i "$SSH_KEY_PATH" "$user_host" "echo 2>&1" >/dev/null
        else
            ssh -q -o BatchMode=yes -o ConnectTimeout=5 -p "$port" "$user_host" "echo 2>&1" >/dev/null
        fi

        if [ $? -eq 0 ]; then
            return 0
        fi
        retry_count=$((retry_count + 1))
        log_message "WARNING" "Failed to connect. Retrying in 5 seconds (Attempt $retry_count of $max_retries)..."
        sleep 5
    done

    log_message "ERROR" "Failed to establish SSH connection after $max_retries attempts."
    return 1
}

extract_ip() {
    local server_input=$1
    local server_type=$2

    if [[ $server_input =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$server_input"
    else
        local ip=$(dig +short "$server_input" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1)
        if [[ -n $ip ]]; then
            echo "$ip:$server_input"
        else
            log_message "ERROR" "Failed to retrieve a valid IP address for $server_input ($server_type server). Please enter a valid IP address."
            return 1
        fi
    fi
}

check_plesk_version() {
    local user=$1
    local server_ip=$2
    local port=$3
    log_message "INFO" "Checking Plesk version on $server_ip..."
    if [ "$USE_KEY_AUTH" = true ]; then
        ssh -p "$port" -i "$SSH_KEY_PATH" "$user@$server_ip" "plesk version" 2>/dev/null || echo "Plesk not found"
    else
        ssh -p "$port" "$user@$server_ip" "plesk version" 2>/dev/null || echo "Plesk not found"
    fi
}

cleanup_backup() {
    local user=$1
    local server_ip=$2
    local port=$3
    local backup_file=$4
    log_message "INFO" "Cleaning up backup files on server $server_ip..."
    if [ "$DRY_RUN" = true ]; then
        log_message "INFO" "[DRY RUN] Would remove backup files $backup_file and ${backup_file}.gz on $server_ip"
    else
        ssh $([[ "$USE_KEY_AUTH" = true ]] && echo "-i $SSH_KEY_PATH") -p "$port" "$user@$server_ip" "rm -f $backup_file ${backup_file}.gz"
        if [ $? -eq 0 ]; then
            log_message "INFO" "Backup files cleaned up successfully on $server_ip"
        else
            log_message "ERROR" "Failed to clean up backup files on $server_ip"
        fi
    fi
}

compress_backup() {
    local user=$1
    local server_ip=$2
    local port=$3
    local backup_file=$4
    log_message "INFO" "Checking backup files on server $server_ip..."
    
    local ssh_cmd="ssh $([[ "$USE_KEY_AUTH" = true ]] && echo "-i $SSH_KEY_PATH") -p $port $user@$server_ip"
    
    if $ssh_cmd "[ -f ${backup_file}.gz ]" && $ssh_cmd "[ -f ${backup_file} ]"; then
        log_message "INFO" "Both compressed and uncompressed backups exist."
        read -p "Use compressed (c), uncompressed (u), or create new compressed (n) backup? [c/u/n]: " backup_choice
        case $backup_choice in
            c|C) echo "${backup_file}.gz" ;;
            u|U) echo "${backup_file}" ;;
            n|N)
                $ssh_cmd "gzip -f $backup_file"
                echo "${backup_file}.gz"
                ;;
            *) 
                log_message "WARNING" "Invalid choice. Using compressed backup by default."
                echo "${backup_file}.gz"
                ;;
        esac
    elif $ssh_cmd "[ -f ${backup_file}.gz ]"; then
        log_message "INFO" "Using existing compressed backup."
        echo "${backup_file}.gz"
    elif $ssh_cmd "[ -f ${backup_file} ]"; then
        log_message "INFO" "Compressing existing uncompressed backup."
        $ssh_cmd "gzip -f $backup_file"
        echo "${backup_file}.gz"
    else
        log_message "ERROR" "No backup file found on $server_ip."
        return 1
    fi
}

migrate_ssl() {
    local source_user=$1
    local source_ip=$2
    local source_port=$3
    local target_user=$4
    local target_ip=$5
    local target_port=$6
    local domain=$7

    log_message "INFO" "Migrating SSL certificate for domain $domain..."
    if [ "$DRY_RUN" = true ]; then
        log_message "INFO" "[DRY RUN] Would migrate SSL certificate for $domain"
    else
        local ssh_source_cmd
        local ssh_target_cmd
        if [ "$USE_KEY_AUTH" = true ]; then
            ssh_source_cmd="ssh -p $source_port -i $SSH_KEY_PATH $source_user@$source_ip"
            ssh_target_cmd="ssh -p $target_port -i $SSH_KEY_PATH $target_user@$target_ip"
        else
            ssh_source_cmd="ssh -p $source_port $source_user@$source_ip"
            ssh_target_cmd="ssh -p $target_port $target_user@$target_ip"
        fi

        # Export SSL from source
        $ssh_source_cmd "plesk bin certificate --export-file /tmp/${domain}_cert.tar $domain"
        
        # Transfer to target
        scp -P "$source_port" $([[ "$USE_KEY_AUTH" = true ]] && echo "-i $SSH_KEY_PATH") "$source_user@$source_ip:/tmp/${domain}_cert.tar" "/tmp/${domain}_cert.tar"
        scp -P "$target_port" $([[ "$USE_KEY_AUTH" = true ]] && echo "-i $SSH_KEY_PATH") "/tmp/${domain}_cert.tar" "$target_user@$target_ip:/tmp/${domain}_cert.tar"

        # Import on target
        $ssh_target_cmd "plesk bin certificate --import-file /tmp/${domain}_cert.tar"

        # Cleanup
        rm -f "/tmp/${domain}_cert.tar"
        $ssh_source_cmd "rm -f /tmp/${domain}_cert.tar"
        $ssh_target_cmd "rm -f /tmp/${domain}_cert.tar"

        log_message "INFO" "SSL certificate migrated for $domain"
    fi
}

read_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        log_message "INFO" "Using configuration file: $CONFIG_FILE"
    else
        log_message "INFO" "No configuration file found at $CONFIG_FILE. Running in interactive mode."
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                verbose_log "Dry run mode enabled. No changes will be made."
                shift
                ;;
            --config)
                CONFIG_FILE="$2"
                verbose_log "Using custom configuration file: $CONFIG_FILE"
                shift 2
                ;;
            --compress)
                COMPRESS_BACKUP=true
                verbose_log "Backup compression enabled."
                shift
                ;;
            --migrate-ssl)
                MIGRATE_SSL=true
                verbose_log "SSL migration enabled."
                shift
                ;;
            --components)
                COMPONENTS_TO_MIGRATE="$2"
                verbose_log "Components to migrate: $COMPONENTS_TO_MIGRATE"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                verbose_log "Verbose mode enabled."
                shift
                ;;
            --use-key-auth)
                USE_KEY_AUTH=true
                SSH_KEY_PATH="$2"
                verbose_log "Using SSH key authentication with key: $SSH_KEY_PATH"
                shift 2
                ;;
            --cleanup-history)
                CLEANUP_HISTORY=true
                verbose_log "History file cleanup enabled."
                shift
                ;;
            *)
                log_message "WARNING" "Unknown option: $1"
                shift
                ;;
        esac
    done
}

main() {
    parse_args "$@"

    if ! setup_logging; then
        echo "Failed to set up logging. Exiting."
        return 1
    fi

    read_config

    log_message "INFO" "Starting EZ-Plesk-Transfer-Bridge-Pro v$VERSION"
    if [ "$DRY_RUN" = true ]; then
        log_message "INFO" "Running in dry run mode. No changes will be made."
    fi

    # Authentication method explanation
    echo "Authentication Methods:"
    echo "1. Password Authentication (default)"
    echo "2. SSH Key Authentication"
    echo "SSH Key Authentication is more secure as it doesn't require transmitting passwords over the network."
    echo "However, it requires setting up SSH keys on the servers beforehand."
    echo

    if [ "$USE_KEY_AUTH" = false ]; then
        read -p "Do you want to use SSH Key Authentication? (yes/no) [no]: " use_key_auth
        if [[ "$use_key_auth" =~ ^[Yy]es$ ]]; then
            USE_KEY_AUTH=true
            SSH_KEY_PATH=$(prompt_input "Enter the path to your SSH private key" "~/.ssh/id_rsa")
        fi
    fi

    # Gather server information if not provided in config
    [ -z "$SOURCE_SERVER" ] && SOURCE_SERVER=$(prompt_input "Enter the source server IP or domain" "")
    SOURCE_SERVER_INFO=$(extract_ip "$SOURCE_SERVER" "source")
    IFS=':' read -r SOURCE_SERVER_IP SOURCE_SERVER_DOMAIN <<< "$SOURCE_SERVER_INFO"

    [ -z "$SOURCE_PORT" ] && SOURCE_PORT=$(prompt_input "Enter the SSH port for the source server" "22")
    [ -z "$SOURCE_USER" ] && SOURCE_USER=$(prompt_input "Enter the username for the source server" "root")

    [ -z "$TARGET_SERVER" ] && TARGET_SERVER=$(prompt_input "Enter the target server IP or domain" "")
    TARGET_SERVER_INFO=$(extract_ip "$TARGET_SERVER" "target")
    IFS=':' read -r TARGET_SERVER_IP TARGET_SERVER_DOMAIN <<< "$TARGET_SERVER_INFO"

    [ -z "$TARGET_PORT" ] && TARGET_PORT=$(prompt_input "Enter the SSH port for the target server" "22")
    [ -z "$TARGET_USER" ] && TARGET_USER=$(prompt_input "Enter the username for the target server" "root")

    echo  # Add a newline for readability

    if [ -n "$SOURCE_SERVER_DOMAIN" ]; then
        log_message "INFO" "Source Server: $SOURCE_SERVER_DOMAIN (IP: $SOURCE_SERVER_IP)"
    else
        log_message "INFO" "Source Server IP: $SOURCE_SERVER_IP"
    fi

    if [ -n "$TARGET_SERVER_DOMAIN" ]; then
        log_message "INFO" "Target Server: $TARGET_SERVER_DOMAIN (IP: $TARGET_SERVER_IP)"
    else
        log_message "INFO" "Target Server IP: $TARGET_SERVER_IP"
    fi

    echo  # Add a newline for readability

    # Test SSH connections
    verbose_log "Testing SSH connection to source server..."
    if ! check_ssh_connection "$SOURCE_USER@$SOURCE_SERVER_IP" "$SOURCE_PORT"; then
        log_message "ERROR" "Cannot connect to source server. Please check your credentials and try again."
        return 1
    fi
    verbose_log "SSH connection to source server successful."

    verbose_log "Testing SSH connection to target server..."
    if ! check_ssh_connection "$TARGET_USER@$TARGET_SERVER_IP" "$TARGET_PORT"; then
        log_message "ERROR" "Cannot connect to target server. Please check your credentials and try again."
        return 1
    fi
    verbose_log "SSH connection to target server successful."

    echo  # Add a newline for readability

    # Check Plesk versions
    SOURCE_PLESK_VERSION=$(check_plesk_version "$SOURCE_USER" "$SOURCE_SERVER_IP" "$SOURCE_PORT")
    TARGET_PLESK_VERSION=$(check_plesk_version "$TARGET_USER" "$TARGET_SERVER_IP" "$TARGET_PORT")

    log_message "INFO" "Source Plesk version: $SOURCE_PLESK_VERSION"
    log_message "INFO" "Target Plesk version: $TARGET_PLESK_VERSION"

    if [ "$SOURCE_PLESK_VERSION" != "$TARGET_PLESK_VERSION" ] || [ "$SOURCE_PLESK_VERSION" = "Plesk not found" ] || [ "$TARGET_PLESK_VERSION" = "Plesk not found" ]; then
        log_message "WARNING" "Plesk versions on the source and target servers do not match or Plesk is not installed on one of the servers."
        read -p "Do you want to use the -ignore-sign option for restoring backups? (yes/no) [yes]: " IGNORE_SIGN
        IGNORE_SIGN=${IGNORE_SIGN:-yes}
    else
        IGNORE_SIGN="no"
    fi

    echo  # Add a newline for readability

    # Main migration loop
    while true; do
        DOMAIN=$(prompt_input "Enter the domain to migrate (or press Enter to finish)" "")
        [ -z "$DOMAIN" ] && break

        log_message "INFO" "Starting migration for domain: $DOMAIN"

        # Check if domain exists on source
        verbose_log "Checking if domain exists on source server..."
        if ! ssh $([[ "$USE_KEY_AUTH" = true ]] && echo "-i $SSH_KEY_PATH") -p "$SOURCE_PORT" "$SOURCE_USER@$SOURCE_SERVER_IP" "plesk bin domain --info $DOMAIN" &>/dev/null; then
            log_message "WARNING" "Domain $DOMAIN does not exist on source server. Skipping."
            continue
        fi
        verbose_log "Domain exists on source server."

        # Check if domain exists on target
        verbose_log "Checking if domain exists on target server..."
        if ssh $([[ "$USE_KEY_AUTH" = true ]] && echo "-i $SSH_KEY_PATH") -p "$TARGET_PORT" "$TARGET_USER@$TARGET_SERVER_IP" "plesk bin domain --info $DOMAIN" &>/dev/null; then
            log_message "WARNING" "Domain $DOMAIN already exists on target server. Skipping."
            continue
        fi
        verbose_log "Domain does not exist on target server. Proceeding with migration."

        # Backup domain on source server
        BACKUP_FILE="/tmp/${DOMAIN}_backup.tar"
        if [ "$COMPRESS_BACKUP" = true ]; then
            verbose_log "Checking and potentially compressing backup file..."
            TRANSFER_FILE=$(compress_backup "$SOURCE_USER" "$SOURCE_SERVER_IP" "$SOURCE_PORT" "$BACKUP_FILE")
            if [ $? -ne 0 ]; then
                log_message "ERROR" "Failed to prepare backup for domain $DOMAIN. Skipping."
                continue
            fi
            verbose_log "Backup file to transfer: $TRANSFER_FILE"
        else
            TRANSFER_FILE="$BACKUP_FILE"
        fi

        # Transfer backup to target server
        log_message "INFO" "Transferring backup to target server..."
        if [ "$DRY_RUN" = true ]; then
            log_message "INFO" "[DRY RUN] Would transfer $TRANSFER_FILE of $DOMAIN to target server"
        else
            verbose_log "Starting file transfer..."
            if ! scp -P "$SOURCE_PORT" $([[ "$USE_KEY_AUTH" = true ]] && echo "-i $SSH_KEY_PATH") "$SOURCE_USER@$SOURCE_SERVER_IP:$TRANSFER_FILE" "$TARGET_USER@$TARGET_SERVER_IP:$TRANSFER_FILE"; then
                log_message "ERROR" "Failed to transfer backup for domain $DOMAIN. Skipping."
                cleanup_backup "$SOURCE_USER" "$SOURCE_SERVER_IP" "$SOURCE_PORT" "$BACKUP_FILE"
                continue
            fi
            verbose_log "Backup file transferred successfully."
        fi

        # Restore backup on target server
        log_message "INFO" "Restoring backup on target server..."
        RESTORE_CMD="plesk bin pleskrestore --restore $BACKUP_FILE -level domains -domain-name $DOMAIN"
        if [ "$IGNORE_SIGN" = "yes" ]; then
            RESTORE_CMD="$RESTORE_CMD -ignore-sign"
            verbose_log "Using -ignore-sign option for restoration."
        fi
        if [ "$DRY_RUN" = true ]; then
            log_message "INFO" "[DRY RUN] Would restore backup of $DOMAIN on target server"
        else
            verbose_log "Executing restore command..."
            if ! ssh $([[ "$USE_KEY_AUTH" = true ]] && echo "-i $SSH_KEY_PATH") -p "$TARGET_PORT" "$TARGET_USER@$TARGET_SERVER_IP" "$RESTORE_CMD"; then
                log_message "ERROR" "Failed to restore backup for domain $DOMAIN on target server."
            else
                log_message "INFO" "Successfully migrated domain $DOMAIN"
                verbose_log "Domain restored successfully on target server."
            fi
        fi

        # Migrate SSL if option is set
        if [ "$MIGRATE_SSL" = true ]; then
            verbose_log "Starting SSL migration for $DOMAIN..."
            migrate_ssl "$SOURCE_USER" "$SOURCE_SERVER_IP" "$SOURCE_PORT" \
                        "$TARGET_USER" "$TARGET_SERVER_IP" "$TARGET_PORT" \
                        "$DOMAIN"
            verbose_log "SSL migration completed for $DOMAIN."
        fi

        # Clean up
        verbose_log "Cleaning up temporary files..."
        cleanup_backup "$SOURCE_USER" "$SOURCE_SERVER_IP" "$SOURCE_PORT" "$BACKUP_FILE"
        cleanup_backup "$TARGET_USER" "$TARGET_SERVER_IP" "$TARGET_PORT" "$BACKUP_FILE"
        verbose_log "Cleanup completed."

        echo  # Add a newline for readability
    done

    if [ "$CLEANUP_HISTORY" = true ]; then
        rm -f "$HISTFILE"
        log_message "INFO" "History file cleaned up."
    else
        log_message "INFO" "History file retained at $HISTFILE"
    fi    
    
    log_message "INFO" "EZ-Plesk-Transfer-Bridge-Pro process completed. Check the log for details."
    return 0
}

main "$@"