#!/bin/bash

# Graylog server
REMOTE_SERVER="192.168.50.214"
REMOTE_PORT="12201"

logger() {
  if [ "$#" -lt 2 ]; then
    echo "Usage: logger \"message\" \"logfile\"" >&2
    return 1
  fi

  local message="$1"
  local logfile="$2"
  local timestamp

  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  if ! touch "$logfile" 2>/dev/null; then
    echo "Error: Cannot write to logfile '$logfile'" >&2
    return 1
  fi

  if ! echo "$timestamp $message" >> "$logfile"; then
    echo "Error: Failed to write to logfile '$logfile'" >&2
    return 1
  fi

  if ! command -v nc >/dev/null 2>&1; then
    echo "Error: nc (netcat) command not found" >&2
    return 1
  fi

  if ! echo "$message" | nc -u -w1 "$REMOTE_SERVER" "$REMOTE_PORT"; then
    echo "Error: Failed to send message to remote server" >&2
    return 1
  fi

  return 0
}
