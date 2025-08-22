#!/usr/bin/env bash

# Erffy Dots Installer - Modern dotfiles management script
# Version: 3.0.0
# License: GNU GPLv3

set -euo pipefail

# Configuration
BASE_URL="https://github.com/erffy-dots"
CONFIG_DIR="$HOME/.config"
LOG_DIR="$HOME/.local/share/erffy-dots"
CACHE_DIR="$HOME/.cache/erffy-dots"
LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
LOCK_FILE="$CACHE_DIR/install.lock"

# Default settings
VERBOSE=false
DRY_RUN=false
FORCE=false
SKIP_DEPS=false
PARALLEL=4

# Available configs
declare -Ar CONFIGS=(
  ["alacritty"]="alacritty"
  ["fish"]="fish"
  ["fastfetch"]="fastfetch"
  ["hypr"]="hyprland"
  ["nvim"]="nvim"
  ["qt6ct"]="qt6ct"
  ["rofi"]="rofi"
  ["starship"]="starship"
  ["swaync"]="swaync"
  #["uwsm"]="uwsm"
  ["waybar"]="waybar"
  ["wlogout"]="wlogout"
  ["xdg-desktop-portal"]="xdp"
  ["gtk-3.0"]="gtk:gtk-3.0"
  ["gtk-4.0"]="gtk:gtk-4.0"
)

log() {
  echo -e "$1" | tee -a "$LOG_FILE"
}

ensure_dirs() {
  mkdir -p "$LOG_DIR" "$CACHE_DIR"
}

check_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    log "Another instance is running. Remove $LOCK_FILE if it's stale."
    exit 1
  fi
  echo $$ > "$LOCK_FILE"
  trap 'rm -f "$LOCK_FILE"' EXIT
}

check_requirements() {
  for cmd in git curl; do
    command -v $cmd &>/dev/null || {
      log "Missing command: $cmd"
      exit 1
    }
  done
}

clone_config() {
  local name="$1"
  local repo_info="${CONFIGS[$name]}"
  local repo="${repo_info%%:*}"
  local branch="${repo_info#*:}"
  [[ "$repo" == "$branch" ]] && branch=""

  local target="$CONFIG_DIR/$name"
  local url="$BASE_URL/$repo"

  [[ -d "$target" && $FORCE == false ]] && {
    log "Skipping $name (already exists)"
    return
  }

  [[ "$DRY_RUN" == true ]] && {
    log "Would clone $url to $target${branch:+ (branch: $branch)}"
    return
  }

  rm -rf "$target"
  if [[ -n "$branch" ]]; then
    git clone --quiet --branch "$branch" "$url" "$target"
  else
    git clone --quiet "$url" "$target"
  fi
  log "Installed $name"
}

install_dependencies() {
  $SKIP_DEPS && return

  local pkgman
  for tool in paru yay pacman; do
    if command -v $tool &>/dev/null; then
      pkgman=$tool
      break
    fi
  done

  [[ -z "$pkgman" ]] && {
    log "No supported package manager found."
    return
  }

  log "Installing dependencies using $pkgman..."

  curl -fsSL "$BASE_URL/.generic/raw/main/packages" | grep -v '^#' | while read -r pkg; do
    [[ -z "$pkg" ]] && continue
    $pkgman -Q "$pkg" &>/dev/null || {
      [[ "$DRY_RUN" == true ]] && log "Would install $pkg" || $pkgman -S --needed --noconfirm "$pkg"
    }
  done
}

list_configs() {
  printf "Available configs:\n"
  for key in "${!CONFIGS[@]}"; do
    echo "  - $key"
  done | sort
  exit
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) echo "Usage: $0 [options] [configs...]"; exit;;
      -v|--verbose) VERBOSE=true;;
      -d|--dry-run) DRY_RUN=true;;
      -f|--force) FORCE=true;;
      -s|--skip-deps) SKIP_DEPS=true;;
      -l|--list) list_configs;;
      -j|--parallel) PARALLEL="$2"; shift;;
      --) shift; break;;
      -*) log "Unknown option: $1"; exit 1;;
      *) SELECTED+=("$1");;
    esac
    shift
  done
}

main() {
  ensure_dirs
  check_lock
  check_requirements

  log "Starting erffy-dots installer..."
  log "Log file: $LOG_FILE"

  parse_args "$@"
  install_dependencies

  SELECTED=("${SELECTED[@]:-${!CONFIGS[@]}}")

  for name in "${SELECTED[@]}"; do
    if [[ -z "${CONFIGS[$name]:-}" ]]; then
      log "Unknown config: $name"
      continue
    fi
    clone_config "$name" &
    (( $(jobs -r | wc -l) >= PARALLEL )) && wait -n
  done

  wait
  log "Done."
}

main "$@"