#!/bin/bash
# /usr/lib/systemd/system-sleep/mba-a1466-sleep.sh
# Unload broadcom-wl przed suspend, reload po wake

set -euo pipefail
LOGFILE="/var/log/mba-a1466-suspend.log"
log() { printf '%s\n' "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOGFILE"; }

pre_suspend() {
    log "PRE: suspend"
    nmcli radio wifi off 2>/dev/null || true
    rfkill block wifi 2>/dev/null || true
    sleep 1
    modprobe -r wl 2>/dev/null || true
    log "PRE: wl unloaded"
}

post_resume() {
    log "POST: resume"
    modprobe wl 2>/dev/null || true
    sleep 2
    rfkill unblock wifi 2>/dev/null || true
    nmcli radio wifi on 2>/dev/null || true
    log "POST: wl loaded"
}

case "$1/$2" in
    pre/suspend)  pre_suspend ;;
    post/suspend) post_resume ;;
esac
