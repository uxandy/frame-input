#!/bin/bash
# SPDX-License-Identifier: MIT
set -eu
[ "$(id -u)" -ne 0 ] || { printf 'Run this as your normal Frame user, without sudo.\n' >&2; exit 1; }
destination="$HOME/.local/share/applications"
mkdir -p "$destination"
for name in frame-input-start.desktop frame-input-stop.desktop; do
    source_file="/var/lib/frame-input/$name"
    if [ -e "$destination/$name" ] || [ -L "$destination/$name" ]; then
        cmp -s "$source_file" "$destination/$name" || { printf 'Existing shortcut differs: %s\n' "$destination/$name" >&2; exit 1; }
    else
        install -m 0644 "$source_file" "$destination/$name"
    fi
done
printf 'Start Sharing and Stop Sharing are available in the application menu. Add both to Steam once.\n'
