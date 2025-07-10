#!/usr/bin/env bash

# Erffy Dots Installer - Modern dotfiles management script
# Version: 2.0.0
# License: GNU GPLv3

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="2.0.0"
readonly BASE_URL="https://github.com/erffy-dots"
readonly CONFIG_DIR="${HOME}/.config"
readonly LOG_DIR="${HOME}/.local/share/erffy-dots"
readonly CACHE_DIR="${HOME}/.cache/erffy-dots"
readonly LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
readonly LOCK_FILE="${CACHE_DIR}/install.lock"

# Color constants
readonly C_RESET='\033[0m'
readonly C_BOLD='\033[1m'
readonly C_RED='\033[31m'
readonly C_GREEN='\033[32m'
readonly C_YELLOW='\033[33m'
readonly C_BLUE='\033[34m'
readonly C_MAGENTA='\033[35m'
readonly C_CYAN='\033[36m'

# Configuration repositories
declare -Ar REPOS=(
    ["hypr"]="hyprland"
    ["waybar"]="waybar"
    ["qt6ct"]="qt6ct"
    ["swaync"]="swaync"
    ["wlogout"]="wlogout"
    ["nvim"]="nvim"
    ["alacritty"]="alacritty"
    ["fish"]="fish"
    ["uwsm"]="uwsm"
    ["starship"]="starship"
    ["xdg-desktop-portal"]="xdp"
    ["fastfetch"]="fastfetch"
    ["rofi"]="rofi"
)

# Special repositories (with branches)
declare -Ar SPECIAL_REPOS=(
    ["gtk-3.0"]="gtk:gtk-3.0"
    ["gtk-4.0"]="gtk:gtk-4.0"
)

# Default options
VERBOSE=false
DRY_RUN=false
FORCE_CLONE=false
BACKUP_ENABLED=true
INSTALL_DEPS=true
PARALLEL_JOBS=4
SELECTED_CONFIGS=()
CHECK_UPDATES=true

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local color=""
    local prefix=""

    case "$level" in
        "ERROR")   color="$C_RED"; prefix="✗" ;;
        "SUCCESS") color="$C_GREEN"; prefix="✓" ;;
        "INFO")    color="$C_BLUE"; prefix="ℹ" ;;
        "WARN")    color="$C_YELLOW"; prefix="⚠" ;;
        "DEBUG")   color="$C_CYAN"; prefix="→" ;;
        "SKIP")    color="$C_MAGENTA"; prefix="⊝" ;;
    esac

    # Console output
    if [[ "$level" != "DEBUG" || "$VERBOSE" == true ]]; then
        echo -e "${color}${prefix} ${message}${C_RESET}"
    fi

    # Log file output
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handler
error_handler() {
    local exit_code=$?
    local line_number=$1

    log "ERROR" "Script failed at line $line_number (exit code: $exit_code)"

    # Show recent log entries
    if [[ -f "$LOG_FILE" ]]; then
        echo -e "\n${C_RED}Recent log entries:${C_RESET}"
        tail -n 5 "$LOG_FILE" | sed 's/^/  /'
    fi

    cleanup
    exit $exit_code
}

# Set up error trap
trap 'error_handler $LINENO' ERR

# Cleanup function
cleanup() {
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
    fi
}

# Set up exit trap
trap cleanup EXIT

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Create directories
ensure_directories() {
    local dirs=("$LOG_DIR" "$CACHE_DIR")

    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log "DEBUG" "Created directory: $dir"
        fi
    done
}

# Check for lock file
check_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")

        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            log "ERROR" "Another instance is already running (PID: $lock_pid)"
            exit 1
        else
            log "WARN" "Removing stale lock file"
            rm -f "$LOCK_FILE"
        fi
    fi

    echo $$ > "$LOCK_FILE"
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# Check system requirements
check_requirements() {
    local missing_commands=()
    local required_commands=("git" "curl" "grep" "sed" "awk")

    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log "ERROR" "Missing required commands: ${missing_commands[*]}"
        log "INFO" "Please install missing commands and try again"
        exit 1
    fi

    log "DEBUG" "All required commands are available"
}

# Validate configuration names
validate_configs() {
    local invalid_configs=()

    for config in "${SELECTED_CONFIGS[@]}"; do
        if [[ -z "${REPOS[$config]:-}" && -z "${SPECIAL_REPOS[$config]:-}" ]]; then
            invalid_configs+=("$config")
        fi
    done

    if [[ ${#invalid_configs[@]} -gt 0 ]]; then
        log "ERROR" "Invalid configuration(s): ${invalid_configs[*]}"
        log "INFO" "Use --list to see available configurations"
        exit 1
    fi
}

# =============================================================================
# PACKAGE MANAGEMENT
# =============================================================================

# Detect package manager
detect_package_manager() {
    local managers=("paru" "yay" "pacman")

    for mgr in "${managers[@]}"; do
        if command_exists "$mgr"; then
            echo "$mgr"
            return 0
        fi
    done

    log "ERROR" "No supported package manager found"
    exit 1
}

# Install missing packages
install_dependencies() {
    if [[ "$INSTALL_DEPS" == false ]]; then
        log "SKIP" "Dependency installation disabled"
        return 0
    fi

    local pkg_manager
    pkg_manager=$(detect_package_manager)

    log "INFO" "Using package manager: $pkg_manager"

    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "Would install dependencies using $pkg_manager"
        return 0
    fi

    local packages_url="${BASE_URL}/.generic/raw/main/packages"
    local package_list

    if ! package_list=$(curl -s "$packages_url"); then
        log "WARN" "Failed to fetch package list, skipping dependency installation"
        return 0
    fi

    local missing_packages=()

    while IFS= read -r package; do
        # Skip empty lines and comments
        [[ -z "$package" || "$package" =~ ^[[:space:]]*# ]] && continue

        package=$(echo "$package" | xargs) # Trim whitespace

        if ! $pkg_manager -Q "$package" &>/dev/null; then
            missing_packages+=("$package")
        fi
    done <<< "$package_list"

    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        log "SUCCESS" "All dependencies are already installed"
        return 0
    fi

    log "INFO" "Installing ${#missing_packages[@]} missing package(s)"

    local install_cmd="$pkg_manager -S --needed --noconfirm"

    if [[ "$VERBOSE" == true ]]; then
        install_cmd="$pkg_manager -S --needed"
    fi

    for package in "${missing_packages[@]}"; do
        log "INFO" "Installing: $package"
        if $install_cmd "$package" >> "$LOG_FILE" 2>&1; then
            log "SUCCESS" "Installed: $package"
        else
            log "WARN" "Failed to install: $package"
        fi
    done
}

# =============================================================================
# REPOSITORY MANAGEMENT
# =============================================================================

# Backup existing configuration
backup_config() {
    local config_path="$1"
    local backup_dir="${HOME}/.config-backup-$(date +%Y%m%d-%H%M%S)"

    if [[ ! -d "$config_path" ]]; then
        return 0
    fi

    if [[ "$BACKUP_ENABLED" == false ]]; then
        log "DEBUG" "Backup disabled, removing existing config: $config_path"
        rm -rf "$config_path"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "Would backup: $config_path"
        return 0
    fi

    mkdir -p "$backup_dir"
    local backup_target="$backup_dir/$(basename "$config_path")"

    if cp -r "$config_path" "$backup_target"; then
        log "SUCCESS" "Backed up: $config_path → $backup_target"
        rm -rf "$config_path"
    else
        log "ERROR" "Failed to backup: $config_path"
        return 1
    fi
}

# Clone repository
clone_repository() {
    local config_name="$1"
    local repo_info="$2"
    local target_path="${CONFIG_DIR}/${config_name}"

    # Parse repository info (format: "repo_name" or "repo_name:branch")
    local repo_name="${repo_info%%:*}"
    local branch="${repo_info#*:}"
    [[ "$branch" == "$repo_name" ]] && branch=""

    local repo_url="${BASE_URL}/${repo_name}"

    log "INFO" "Processing: $config_name"

    # Check if already exists
    if [[ -d "$target_path" ]]; then
        if [[ "$FORCE_CLONE" == false ]]; then
            log "SKIP" "$config_name already exists"
            return 0
        fi

        backup_config "$target_path"
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "Would clone: $repo_url → $target_path"
        [[ -n "$branch" ]] && log "DEBUG" "Branch: $branch"
        return 0
    fi

    # Clone repository
    local git_cmd="git clone --quiet"
    [[ "$VERBOSE" == true ]] && git_cmd="git clone"

    if [[ -n "$branch" ]]; then
        git_cmd+=" --branch $branch"
    fi

    if $git_cmd "$repo_url" "$target_path" >> "$LOG_FILE" 2>&1; then
        log "SUCCESS" "Cloned: $config_name"
    else
        log "ERROR" "Failed to clone: $config_name"
        return 1
    fi
}

# Process single configuration
process_config() {
    local config="$1"

    if [[ -n "${REPOS[$config]:-}" ]]; then
        clone_repository "$config" "${REPOS[$config]}"
    elif [[ -n "${SPECIAL_REPOS[$config]:-}" ]]; then
        clone_repository "$config" "${SPECIAL_REPOS[$config]}"
    else
        log "ERROR" "Unknown configuration: $config"
        return 1
    fi
}

# Process configurations in parallel
process_configs_parallel() {
    local configs=("$@")
    local pids=()
    local failed_configs=()

    log "INFO" "Processing ${#configs[@]} configuration(s) in parallel"

    for config in "${configs[@]}"; do
        if [[ ${#pids[@]} -ge $PARALLEL_JOBS ]]; then
            # Wait for one job to complete
            wait "${pids[0]}" || failed_configs+=("$config")
            pids=("${pids[@]:1}")
        fi

        process_config "$config" &
        pids+=($!)
    done

    # Wait for remaining jobs
    for pid in "${pids[@]}"; do
        wait "$pid" || failed_configs+=("unknown")
    done

    if [[ ${#failed_configs[@]} -gt 0 ]]; then
        log "WARN" "Some configurations failed to process"
        return 1
    fi

    return 0
}

# =============================================================================
# MAIN FUNCTIONS
# =============================================================================

# Display help
show_help() {
    cat << EOF
${C_BOLD}erffy-dots installer v${SCRIPT_VERSION}${C_RESET}
Modern dotfiles configuration installer

${C_BOLD}USAGE:${C_RESET}
    $SCRIPT_NAME [OPTIONS] [CONFIGS...]

${C_BOLD}OPTIONS:${C_RESET}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -d, --dry-run           Show what would be done without making changes
    -f, --force             Force overwrite existing configurations
    -n, --no-backup         Don't create backups of existing configurations
    -s, --skip-deps         Skip dependency installation
    -j, --jobs N            Number of parallel jobs (default: $PARALLEL_JOBS)
    -l, --list              List available configurations
    --no-updates            Skip checking for script updates
    --update                Update script to latest version

${C_BOLD}EXAMPLES:${C_RESET}
    $SCRIPT_NAME                    # Install all configurations
    $SCRIPT_NAME nvim fish          # Install specific configurations
    $SCRIPT_NAME --force --verbose  # Force reinstall with verbose output
    $SCRIPT_NAME --dry-run          # Preview what would be installed

${C_BOLD}LOGS:${C_RESET}
    Installation logs are saved to: $LOG_DIR
EOF
}

# List available configurations
list_configs() {
    echo -e "${C_BOLD}Available configurations:${C_RESET}"

    echo -e "\n${C_BLUE}Standard configurations:${C_RESET}"
    for config in "${!REPOS[@]}"; do
        echo "  • $config"
    done | sort

    echo -e "\n${C_BLUE}Special configurations:${C_RESET}"
    for config in "${!SPECIAL_REPOS[@]}"; do
        echo "  • $config"
    done | sort

    echo -e "\n${C_YELLOW}Total: $((${#REPOS[@]} + ${#SPECIAL_REPOS[@]})) configurations${C_RESET}"
}

# Check for script updates
check_for_updates() {
    if [[ "$CHECK_UPDATES" == false ]]; then
        log "DEBUG" "Update check disabled"
        return 0
    fi

    log "INFO" "Checking for updates..."

    local latest_url="${BASE_URL}/.github/raw/main/install.sh"
    local latest_version

    if ! latest_version=$(curl -s "$latest_url" | grep -o 'readonly SCRIPT_VERSION="[^"]*"' | cut -d'"' -f2); then
        log "WARN" "Failed to check for updates"
        return 0
    fi

    if [[ "$latest_version" != "$SCRIPT_VERSION" ]]; then
        log "INFO" "New version available: $latest_version (current: $SCRIPT_VERSION)"
        echo -e "${C_YELLOW}Run '$SCRIPT_NAME --update' to update${C_RESET}"
    else
        log "DEBUG" "Script is up to date"
    fi
}

# Update script
update_script() {
    log "INFO" "Updating script to latest version..."

    local latest_url="${BASE_URL}/.github/raw/main/install.sh"
    local temp_file="/tmp/erffy-dots-install-new.sh"
    local backup_file="${0}.backup-$(date +%Y%m%d-%H%M%S)"

    # Download latest version
    if ! curl -s -o "$temp_file" "$latest_url"; then
        log "ERROR" "Failed to download latest version"
        exit 1
    fi

    # Backup current version
    cp "$0" "$backup_file"

    # Replace current script
    if mv "$temp_file" "$0" && chmod +x "$0"; then
        log "SUCCESS" "Script updated successfully"
        log "INFO" "Backup saved to: $backup_file"
    else
        log "ERROR" "Failed to update script"
        mv "$backup_file" "$0"
        exit 1
    fi
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE_CLONE=true
                shift
                ;;
            -n|--no-backup)
                BACKUP_ENABLED=false
                shift
                ;;
            -s|--skip-deps)
                INSTALL_DEPS=false
                shift
                ;;
            -j|--jobs)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            -l|--list)
                list_configs
                exit 0
                ;;
            --no-updates)
                CHECK_UPDATES=false
                shift
                ;;
            --update)
                update_script
                exit 0
                ;;
            -*)
                log "ERROR" "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                SELECTED_CONFIGS+=("$1")
                shift
                ;;
        esac
    done
}

# Main function
main() {
    echo -e "${C_BOLD}erffy-dots installer v${SCRIPT_VERSION}${C_RESET}"
    echo -e "${C_BLUE}Modern dotfiles configuration installer${C_RESET}\n"

    parse_arguments "$@"

    ensure_directories
    check_lock
    check_requirements

    # Initialize log file
    {
        echo "# erffy-dots installer log"
        echo "# Date: $(date)"
        echo "# Version: $SCRIPT_VERSION"
        echo "# Options: verbose=$VERBOSE, dry-run=$DRY_RUN, force=$FORCE_CLONE"
        echo "# Selected configs: ${SELECTED_CONFIGS[*]:-all}"
        echo ""
    } > "$LOG_FILE"

    log "INFO" "Starting installation..."

    if [[ "$DRY_RUN" == true ]]; then
        log "INFO" "Running in dry-run mode - no changes will be made"
    fi

    check_for_updates

    # Determine configurations to process
    local configs_to_process=()

    if [[ ${#SELECTED_CONFIGS[@]} -eq 0 ]]; then
        # Install all configurations
        configs_to_process=("${!REPOS[@]}" "${!SPECIAL_REPOS[@]}")
        log "INFO" "Installing all configurations (${#configs_to_process[@]} total)"
    else
        # Install selected configurations
        configs_to_process=("${SELECTED_CONFIGS[@]}")
        validate_configs
        log "INFO" "Installing selected configurations: ${configs_to_process[*]}"
    fi

    # Process configurations
    if [[ $PARALLEL_JOBS -gt 1 ]]; then
        process_configs_parallel "${configs_to_process[@]}"
    else
        for config in "${configs_to_process[@]}"; do
            process_config "$config"
        done
    fi

    # Install dependencies
    install_dependencies

    # Final summary
    if [[ "$DRY_RUN" == true ]]; then
        log "SUCCESS" "Dry run completed successfully"
        echo -e "\n${C_GREEN}✓ Dry run completed!${C_RESET}"
        echo -e "${C_BLUE}Run without --dry-run to apply changes${C_RESET}"
    else
        log "SUCCESS" "Installation completed successfully"
        echo -e "\n${C_GREEN}✓ Installation completed!${C_RESET}"
        echo -e "${C_BLUE}Log file: $LOG_FILE${C_RESET}"
        echo -e "\n${C_YELLOW}Next steps:${C_RESET}"
        echo -e "  1. Restart your desktop environment"
        echo -e "  2. Check the log file for any warnings"
        echo -e "  3. Customize configurations as needed"
    fi
}

# Run main function with all arguments
main "$@"
