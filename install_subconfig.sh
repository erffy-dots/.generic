#!/usr/bin/env bash

# Erffy Dots Installer - Subconfig management script
# Version: 3.0.0
# License: GNU GPLv3

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_VERSION="3.0.0"

GITHUB_USER="erffy-dots"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
VERBOSE=false
DRY_RUN=false
FORCE=false

log() {
  local type="$1"; shift
  local msg="$*"
  local ts="$(date +"%Y-%m-%d %H:%M:%S")"
  [[ "$type" == DEBUG && $VERBOSE != true ]] && return
  echo "[$ts] $type: $msg" >&2
}

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options]

Environment:
  CONFIG_NAME       Required, repo name (e.g., nvim)
  CONFIG_DIR_NAME   Optional, install dir (defaults to CONFIG_NAME)

Options:
  -h, --help        Show this help
  -v, --verbose     Enable verbose output
  -n, --dry-run     Only print what would be done
  -f, --force       Overwrite without confirmation
  -u, --user USER   GitHub user (default: $GITHUB_USER)
  -d, --config-dir DIR  Use custom base config dir (default: \$XDG_CONFIG_HOME or ~/.config)
  --version         Print version

Example:
  CONFIG_NAME=rofi $SCRIPT_NAME -v
EOF
}

confirm() {
  [[ "$FORCE" == true ]] && return 0
  read -rp "$1 [y/N]: " resp
  [[ "$resp" =~ ^[Yy]$ ]] && return 0 || return 1
}

backup_existing() {
  local dir="$1"
  local backup="${dir}.bak"
  log INFO "Backing up existing config to $backup"
  [[ "$DRY_RUN" == true ]] && return 0
  [[ -e "$backup" ]] && rm -rf "$backup"
  mv "$dir" "$backup"
}

clone_repo() {
  local repo_url="$1" target="$2"
  log INFO "Cloning $repo_url to $target"
  [[ "$DRY_RUN" == true ]] && return 0
  git clone --quiet "$repo_url" "$target"
}

clean_repo() {
  local dir="$1"
  rm -rf $dir/{.git,README.md,LICENSE,.github,.gitignore,assets,install.sh}
  log INFO "Cleaned up repo files"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help) usage; exit 0;;
      -v|--verbose) VERBOSE=true;;
      -n|--dry-run) DRY_RUN=true;;
      -f|--force) FORCE=true;;
      -u|--user) GITHUB_USER="$2"; shift;;
      -d|--config-dir) CONFIG_HOME="$2"; shift;;
      --version) echo "$SCRIPT_NAME v$SCRIPT_VERSION"; exit 0;;
      *) log ERROR "Unknown option: $1"; usage; exit 1;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  [[ -z "${CONFIG_NAME:-}" ]] && log ERROR "CONFIG_NAME not set" && exit 1
  CONFIG_DIR_NAME="${CONFIG_DIR_NAME:-$CONFIG_NAME}"

  local dest="$CONFIG_HOME/$CONFIG_DIR_NAME"
  local repo_url="https://github.com/$GITHUB_USER/$CONFIG_NAME.git"

  log DEBUG "Repo URL: $repo_url"
  log DEBUG "Target path: $dest"

  [[ -e "$dest" ]] && {
    confirm "Overwrite existing config at $dest?" || exit 1
    backup_existing "$dest"
  }

  clone_repo "$repo_url" "$dest"
  clean_repo "$dest"

  log INFO "Installed $CONFIG_NAME config to $dest"
  echo -e "\nNext steps:\n- Review $dest\n- Adjust as needed"
}

main "$@"