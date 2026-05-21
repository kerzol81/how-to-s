#!/usr/bin/env bash
# KZ 21.05.2026
# Live colorized Traccar log viewer

LOG_FILE="/opt/traccar/logs/tracker-server.log"

RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

if [[ ! -f "$LOG_FILE" ]]; then
    echo "${RED}[-] Traccar log file not found: $LOG_FILE${RESET}"
    exit 1
fi

highlight_devices() {
    perl -pe '
        BEGIN {
            $red = "\e[31m";
            $bold = "\e[1m";
            $reset = "\e[0m";
        }

        s/((?:device_id|deviceId)"\s*:\s*")([A-Za-z0-9_.:-]+)/$1$bold$red$2$reset/g;
        s/([?&]id=)([A-Za-z0-9_.:-]+)/$1$bold$red$2$reset/g;
        s/(\bEvent id:\s*)([A-Za-z0-9_.:-]+)/$1$bold$red$2$reset/g;
        s/(\bid:\s*)([A-Za-z0-9_.:-]+)/$1$bold$red$2$reset/g;
    '
}

print_line() {
    local line="$1"
    local color="${2:-}"

    if [[ -n "$color" ]]; then
        printf "%b%s%b\n" "$color" "$line" "$RESET" | highlight_devices
    else
        printf "%s\n" "$line" | highlight_devices
    fi
}

colorize_line() {
    local line="$1"

    if echo "$line" | grep -Eiq "login failed|failed|error|exception|invalid|bad request|unauthorized|forbidden|__proto__|constructor|Next-Action|client-proxy|application/dns-message|safe_check"; then
        print_line "$line" "$RED"
    elif echo "$line" | grep -Eiq "200 OK|success|accepted|deviceOnline|connected"; then
        print_line "$line" "$GREEN"
    elif echo "$line" | grep -Eiq "warning|warn|deviceUnknown"; then
        print_line "$line" "$YELLOW"
    else
        print_line "$line"
    fi
}

print_help() {
    echo "Usage: traccar_log_viewer [all|errors|osmand|teltonika|auth|abuse|devices|help]"
    echo
    echo "Live colorized commands:"
    echo "  all        Follow all Traccar logs live"
    echo "  errors     Follow errors, failed logins, invalid requests"
    echo "  osmand     Follow OsmAnd / 5055 activity"
    echo "  teltonika  Follow Teltonika / 5027 activity"
    echo "  auth       Follow login failures"
    echo "  abuse      Follow likely abuse/scanner attempts"
    echo "  devices    Follow lines containing detected device IDs"
    echo "  help       Show this help"
    echo
    echo "Color meaning:"
    echo "  red        failed/error/attack/bad request"
    echo "  green      200 OK/success/connected/online"
    echo "  yellow     warning/deviceUnknown"
    echo "  white      normal info"
    echo
    echo "Detected device IDs are highlighted in bold red."
}

MODE="${1:-all}"

case "$MODE" in
    all)
        echo "${BLUE}[*] Following all Traccar logs live. Press Ctrl+C to stop.${RESET}"
        sudo tail -n 50 -f "$LOG_FILE" | while IFS= read -r line; do
            colorize_line "$line"
        done
        ;;

    errors)
        echo "${BLUE}[*] Following errors and suspicious Traccar events live. Press Ctrl+C to stop.${RESET}"
        sudo tail -n 200 -f "$LOG_FILE" | grep --line-buffered -Ei "error|exception|failed|invalid|bad request|unauthorized|forbidden|deviceUnknown" | while IFS= read -r line; do
            colorize_line "$line"
        done
        ;;

    osmand)
        echo "${BLUE}[*] Following OsmAnd / 5055 activity live. Press Ctrl+C to stop.${RESET}"
        sudo tail -n 200 -f "$LOG_FILE" | grep --line-buffered -Ei "osmand|5055" | while IFS= read -r line; do
            colorize_line "$line"
        done
        ;;

    teltonika)
        echo "${BLUE}[*] Following Teltonika / 5027 activity live. Press Ctrl+C to stop.${RESET}"
        sudo tail -n 200 -f "$LOG_FILE" | grep --line-buffered -Ei "teltonika|5027" | while IFS= read -r line; do
            colorize_line "$line"
        done
        ;;

    auth)
        echo "${BLUE}[*] Following Traccar login failures live. Press Ctrl+C to stop.${RESET}"
        sudo tail -n 200 -f "$LOG_FILE" | grep --line-buffered -Ei "login failed from" | while IFS= read -r line; do
            colorize_line "$line"
        done
        ;;

    abuse)
        echo "${BLUE}[*] Following likely abuse/scanner attempts live. Press Ctrl+C to stop.${RESET}"
        sudo tail -n 200 -f "$LOG_FILE" | grep --line-buffered -Ei "Next-Action|__proto__|constructor|client-proxy|application/dns-message|safe_check|wp-login|xmlrpc|phpmyadmin|\.env|bad request" | whileIFS= read -r line; do
            colorize_line "$line"
        done
        ;;

    devices)
        echo "${BLUE}[*] Following detected device ID lines live. Press Ctrl+C to stop.${RESET}"
        sudo tail -n 200 -f "$LOG_FILE" | grep --line-buffered -Ei "device_id\"|deviceId\"|[?&]id=|Event id:|(^|[[:space:]])id:[[:space:]]" | while IFS= read -r line; do
            colorize_line "$line"
        done
        ;;

    help|-h|--help)
        print_help
        ;;

    *)
        echo "${RED}[-] Unknown option: $MODE${RESET}"
        echo "${YELLOW}[?] Use: traccar_log_viewer help${RESET}"
        exit 1
        ;;
esac
