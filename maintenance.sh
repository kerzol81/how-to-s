#!/bin/bash

# KZ
LOG_FILE="/var/log/maintenance.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

run_command() {
    "$@" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        log_message "Error: Command '$*' failed."
        exit 1
    fi
}

# Start maintenance
log_message "Starting regular maintenance."

log_message "Starting package list update."
run_command sudo apt update

log_message "Starting package upgrade."
run_command sudo apt upgrade -y

log_message "Starting full upgrade."
run_command sudo apt full-upgrade -y

log_message "Starting cleanup of unused packages."
run_command sudo apt autoremove -y

log_message "Regular maintenance completed."
