#!/usr/bin/env bash
set -euo pipefail

json_file="flags.json"
only_app="${1:-}"

if ! command -v gum &>/dev/null; then
    echo "Please install gum to use this script."
    exit 1
fi

format_flags() {
    local flags=("$@")
    local formatted=()
    for f in "${flags[@]}"; do
        if [[ "$f" == --* ]]; then
            formatted+=("$f")
        else
            formatted+=("--$f")
        fi
    done
    printf "%s\n" "${formatted[@]}"
}

generate_file() {
    local path="$1"
    local app="$2"
    shift 2
    local flags=("$@")

    mkdir -p $(dirname $path)

    local display_path="$path"
    if [[ "$path" == "$HOME"* ]]; then
        display_path="~${path#$HOME}"
    fi

    gum spin --title "Generating $display_path for $app..." -- sleep 0.2

    if [[ "$path" == *"spotify-launcher.conf"* ]]; then
        {
            echo "[spotify]"
            echo "extra_arguments = ["
            for f in "${flags[@]}"; do
                echo "  \"$f\","
            done
            echo "]"
        } > "$path"
    else
        printf "%s\n" "${flags[@]}" > "$path"
    fi

    gum log --structured --level none "Generated $display_path for $app"
}

jq -r 'to_entries[] | @base64' "$json_file" | while read -r entry; do
    app=$(echo "$entry" | base64 --decode | jq -r '.key')

    [[ -n "$only_app" && "$only_app" != "$app" ]] && continue

    paths=($(echo "$entry" | base64 --decode | jq -r '.value.paths[]'))
    flags=($(echo "$entry" | base64 --decode | jq -r '.value.list[]'))

    formatted_flags=($(format_flags "${flags[@]}"))

    for path in "${paths[@]}"; do
        path="${path/#\~/$HOME}"
        generate_file "$path" "$app" "${formatted_flags[@]}"
    done
done

gum log --structured --level info "Successfully generated"