#!/usr/bin/env bash

# Erffy Dots Installer - Subconfig management script
# Version: 2.0.0
# License: GNU GPLv3

set -euo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="2.0.0"

# Default values
DEFAULT_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
GITHUB_USER="erffy-dots"
VERBOSE=false
DRY_RUN=false
FORCE=false

# Function to display usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Downloads and installs configuration files from a GitHub repository.

Required Environment Variables:
    CONFIG_NAME     Name of the configuration repository
    CONFIG_DIR_NAME Directory name for the configuration (defaults to CONFIG_NAME)

Options:
    -h, --help      Show this help message
    -v, --verbose   Enable verbose output
    -n, --dry-run   Show what would be done without executing
    -f, --force     Force installation without confirmation prompts
    -u, --user      GitHub username (default: $GITHUB_USER)
    -d, --config-dir Custom configuration directory path
    --version       Show script version

Examples:
    CONFIG_NAME=nvim $SCRIPT_NAME
    CONFIG_NAME=tmux CONFIG_DIR_NAME=tmux-config $SCRIPT_NAME --verbose
    CONFIG_NAME=awesome $SCRIPT_NAME --force --user myuser

EOF
}

# Function to log messages
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    case "$level" in
        ERROR)
            echo "[$timestamp] ERROR: $message" >&2
            ;;
        WARN)
            echo "[$timestamp] WARNING: $message" >&2
            ;;
        INFO)
            echo "[$timestamp] INFO: $message"
            ;;
        DEBUG)
            if [[ "$VERBOSE" == true ]]; then
                echo "[$timestamp] DEBUG: $message"
            fi
            ;;
    esac
}

# Function to prompt for confirmation
confirm() {
    local prompt="$1"
    local default="${2:-n}"

    if [[ "$FORCE" == true ]]; then
        log DEBUG "Force mode enabled, skipping confirmation"
        return 0
    fi

    while true; do
        if [[ "$default" == "y" ]]; then
            read -p "$prompt [Y/n]: " -r response
            response="${response:-y}"
        else
            read -p "$prompt [y/N]: " -r response
            response="${response:-n}"
        fi

        case "$response" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Function to check prerequisites
check_prerequisites() {
    log DEBUG "Checking prerequisites"

    if ! command -v git &>/dev/null; then
        log ERROR "Git is not installed. Please install Git first."
        exit 1
    fi

    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        log WARN "Neither curl nor wget found. Repository existence check will be skipped."
    fi

    log DEBUG "Prerequisites check completed"
}

# Function to validate environment variables
validate_environment() {
    log DEBUG "Validating environment variables"

    if [[ -z "${CONFIG_NAME:-}" ]]; then
        log ERROR "CONFIG_NAME environment variable is not set"
        log INFO "Please set CONFIG_NAME before running this script:"
        log INFO "  export CONFIG_NAME=your-config-name"
        exit 1
    fi

    # Use CONFIG_NAME as default for CONFIG_DIR_NAME
    CONFIG_DIR_NAME="${CONFIG_DIR_NAME:-$CONFIG_NAME}"

    log DEBUG "CONFIG_NAME: $CONFIG_NAME"
    log DEBUG "CONFIG_DIR_NAME: $CONFIG_DIR_NAME"
}

# Function to check if repository exists
check_repository_exists() {
    local repo_url="$1"

    log DEBUG "Checking if repository exists: $repo_url"

    if command -v curl &>/dev/null; then
        if curl -s --head "$repo_url" | head -1 | grep -q "200 OK"; then
            return 0
        fi
    elif command -v wget &>/dev/null; then
        if wget -q --spider "$repo_url" 2>/dev/null; then
            return 0
        fi
    fi

    log WARN "Could not verify repository existence. Proceeding anyway."
    return 0
}

# Function to create backup
create_backup() {
    local config_dir="$1"
    local backup_dir="$2"

    log INFO "Creating backup of existing configuration"

    if [[ "$DRY_RUN" == true ]]; then
        log INFO "[DRY RUN] Would create backup: $config_dir -> $backup_dir"
        return 0
    fi

    if [[ -d "$backup_dir" ]]; then
        log WARN "Existing backup found at '$backup_dir'"
        if confirm "Remove existing backup?"; then
            log DEBUG "Removing existing backup"
            rm -rf "$backup_dir"
        else
            log ERROR "Cannot proceed with existing backup present"
            exit 1
        fi
    fi

    log DEBUG "Copying $config_dir to $backup_dir"
    if ! cp -a "$config_dir" "$backup_dir"; then
        log ERROR "Failed to create backup"
        exit 1
    fi

    log INFO "Backup created successfully at '$backup_dir'"
}

# Function to clone repository
clone_repository() {
    local repo_url="$1"
    local config_dir="$2"

    log INFO "Cloning repository from $repo_url"

    if [[ "$DRY_RUN" == true ]]; then
        log INFO "[DRY RUN] Would clone: $repo_url -> $config_dir"
        return 0
    fi

    if ! git clone "$repo_url" "$config_dir"; then
        log ERROR "Failed to clone repository"
        exit 1
    fi

    if [[ ! -d "$config_dir" ]]; then
        log ERROR "Configuration directory '$config_dir' does not exist after clone"
        exit 1
    fi

    log INFO "Repository cloned successfully"
}

# Function to clean up repository files
cleanup_repository() {
    local config_dir="$1"

    log INFO "Cleaning up repository files"

    local files_to_remove=(.git README.md LICENSE assets install.sh .gitignore .github)

    if [[ "$DRY_RUN" == true ]]; then
        log INFO "[DRY RUN] Would remove files: ${files_to_remove[*]}"
        return 0
    fi

    for file in "${files_to_remove[@]}"; do
        local file_path="$config_dir/$file"
        if [[ -e "$file_path" ]]; then
            log DEBUG "Removing $file_path"
            rm -rf "$file_path"
        fi
    done

    log INFO "Repository cleanup completed"
}

# Function to display final message
display_completion_message() {
    local config_name="$1"
    local config_dir="$2"

    log INFO "Configuration setup completed successfully!"
    echo
    echo "Next steps:"
    echo "1. Review the files in '$config_dir'"
    echo "2. Install any additional dependencies for $config_name"
    echo "3. Refer to the $config_name documentation for configuration details"
    echo "4. If issues arise, visit the GitHub repository for troubleshooting"
    echo
    echo "Repository: https://github.com/$GITHUB_USER/$config_name"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -u|--user)
                if [[ -n "${2:-}" ]]; then
                    GITHUB_USER="$2"
                    shift 2
                else
                    log ERROR "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            -d|--config-dir)
                if [[ -n "${2:-}" ]]; then
                    DEFAULT_CONFIG_HOME="$2"
                    shift 2
                else
                    log ERROR "Option $1 requires an argument"
                    exit 1
                fi
                ;;
            --version)
                echo "$SCRIPT_NAME version $SCRIPT_VERSION"
                exit 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                log ERROR "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                log ERROR "Unexpected argument: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    parse_arguments "$@"

    log INFO "Starting configuration setup (version $SCRIPT_VERSION)"

    if [[ "$DRY_RUN" == true ]]; then
        log INFO "DRY RUN MODE - No changes will be made"
    fi

    check_prerequisites
    validate_environment

    # Set up paths
    local repo_url="https://github.com/$GITHUB_USER/$CONFIG_NAME.git"
    local config_dir="$DEFAULT_CONFIG_HOME/$CONFIG_DIR_NAME"
    local backup_dir="${config_dir}.bak"

    log DEBUG "Repository URL: $repo_url"
    log DEBUG "Configuration directory: $config_dir"
    log DEBUG "Backup directory: $backup_dir"

    # Check if repository exists
    check_repository_exists "$repo_url"

    # Handle existing configuration
    if [[ -d "$config_dir" ]]; then
        log WARN "Existing configuration found at '$config_dir'"
        if confirm "Backup existing configuration and proceed?"; then
            create_backup "$config_dir" "$backup_dir"
            log DEBUG "Removing existing configuration"
            if [[ "$DRY_RUN" == false ]]; then
                rm -rf "$config_dir"
            fi
        else
            log INFO "Setup cancelled by user"
            exit 0
        fi
    fi

    # Clone and setup
    clone_repository "$repo_url" "$config_dir"
    cleanup_repository "$config_dir"

    # Display completion message
    if [[ "$DRY_RUN" == false ]]; then
        display_completion_message "$CONFIG_NAME" "$config_dir"
    else
        log INFO "[DRY RUN] Setup would be completed successfully"
    fi
}

# Execute main function with all arguments
main "$@"
