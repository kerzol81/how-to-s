#!/bin/bash

# KZ
LOG_FILE="/var/log/maintenance.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_message "Starting package list update."
sudo apt update >> "$LOG_FILE" 2>&1
log_message "Package list update completed."

log_message "Starting package upgrade."
sudo apt upgrade -y >> "$LOG_FILE" 2>&1
log_message "Package upgrade completed."

log_message "Starting full upgrade."
sudo apt full-upgrade -y >> "$LOG_FILE" 2>&1
log_message "Full upgrade completed."

log_message "Starting cleanup of unused packages."
sudo apt autoremove -y >> "$LOG_FILE" 2>&1
log_message "Cleanup completed."

log_message "Regular maintenance completed."
