#!/bin/bash
# SPDX-License-Identifier: MIT
set -u
umask 077
action=${1:-status}
case "$action" in start|stop|status) ;; *) printf 'Use start, stop or status.\n' >&2; exit 2 ;; esac

show_message() {
    local kind=$1 message=$2
    printf '%s\n' "$message"
    # Notifications can be hidden in VR. A dialog makes action failures explicit.
    if command -v zenity >/dev/null 2>&1; then
        zenity "--$kind" --title='Frame Input' --width=500 --no-markup --text="$message" 2>/dev/null || true
    elif command -v kdialog >/dev/null 2>&1; then
        if [ "$kind" = error ]; then
            kdialog --title 'Frame Input' --error "$message" 2>/dev/null || true
        else
            kdialog --title 'Frame Input' --msgbox "$message" 2>/dev/null || true
        fi
    fi
}

if [ "$action" = status ]; then
    exec /usr/bin/systemctl status --no-pager frame-input.service
fi

if ! result=$(/usr/bin/sudo -n /usr/bin/systemctl "$action" frame-input.service 2>&1); then
    show_message error "Could not $action sharing.

$result

Check the installation and service status. No password prompt is required after setup."
    exit 1
fi

if [ "$action" = start ]; then
    sleep 1
    if ! /usr/bin/systemctl is-active --quiet frame-input.service; then
        show_message error 'Sharing could not stay running. An earlier test server may still be using the port. Check: systemctl status frame-input.service'
        exit 1
    fi
    show_message info 'Sharing is available. On the streamed Windows desktop, open Use Frame Keyboard & Mouse.

Use Stop Sharing to end the session. Closing this window or ending the video stream does not stop sharing.'
else
    show_message info 'Sharing has stopped. The keyboard and mouse should work on the Frame again. If they do not, unplug and reconnect only the receiver.'
fi
