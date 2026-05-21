#!/usr/bin/env bash
# 21.05.2026 KZ
# Traccar GPS data exporter
# Exports: GPX + JSON + CSV
#
# Usage:
#   traccar-export --list
#   traccar-export -id DEVICE_ID_OR_NAME_OR_UNIQUEID -from 2025.05.01 -to 2025.05.21
#
# Required environment variables:
#   TRACCAR_USER="your@email.com"
#   TRACCAR_PASS="your-password"
#
# Optional environment variables:
#   TRACCAR_URL="http://127.0.0.1:8082"
#   TRACCAR_OUT_DIR="/home/$USER/traccar_exports"
#   TRACCAR_TZ_OFFSET="Z"
#
# Timezone examples:
#   TRACCAR_TZ_OFFSET="Z"       UTC
#   TRACCAR_TZ_OFFSET="+02:00"  Hungary summer time
#   TRACCAR_TZ_OFFSET="+01:00"  Hungary winter time

set -euo pipefail

TRACCAR_URL="${TRACCAR_URL:-http://127.0.0.1:8082}"
TRACCAR_USER="${TRACCAR_USER:-}"
TRACCAR_PASS="${TRACCAR_PASS:-}"
OUT_DIR="${TRACCAR_OUT_DIR:-./traccar_exports}"
TZ_OFFSET="${TRACCAR_TZ_OFFSET:-Z}"

DEVICE_KEY=""
FROM_DATE=""
TO_DATE=""
LIST_ONLY="no"

usage() {
    echo "Usage:"
    echo "  traccar-export --list"
    echo "  traccar-export -id DEVICE_ID_OR_NAME_OR_UNIQUEID -from YYYY.MM.DD -to YYYY.MM.DD"
    echo
    echo "Examples:"
    echo "  traccar-export --list"
    echo "  traccar-export -id zolee_iphone -from 2025.05.01 -to 2025.05.21"
    echo "  TRACCAR_TZ_OFFSET='+02:00' traccar-export -id zolee_iphone -from 2025.05.01 -to 2025.05.21"
    echo
    echo "Required environment variables:"
    echo "  TRACCAR_USER"
    echo "  TRACCAR_PASS"
    echo
    echo "Optional environment variables:"
    echo "  TRACCAR_URL       Default: http://127.0.0.1:8082"
    echo "  TRACCAR_OUT_DIR   Default: ./traccar_exports"
    echo "  TRACCAR_TZ_OFFSET Default: Z"
}

log_info() {
    echo "[*] $*"
}

log_success() {
    echo "[+] $*"
}

log_error() {
    echo "[-] $*" >&2
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_error "Missing command: $1"
        log_error "Install it with: sudo apt install $1 -y"
        exit 1
    fi
}

normalize_date() {
    local input="$1"

    if [[ "$input" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
        echo "${input//./-}"
    elif [[ "$input" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "$input"
    else
        log_error "Invalid date format: $input"
        log_error "Use YYYY.MM.DD, for example 2025.05.01"
        exit 1
    fi
}

validate_tz_offset() {
    local input="$1"

    if [[ "$input" == "Z" ]]; then
        return 0
    fi

    if [[ "$input" =~ ^[+-][0-9]{2}:[0-9]{2}$ ]]; then
        return 0
    fi

    log_error "Invalid TRACCAR_TZ_OFFSET: $input"
    log_error "Use Z, +02:00, +01:00, etc."
    exit 1
}

urlencode() {
    jq -rn --arg v "$1" '$v|@uri'
}

xml_escape() {
    local input="$1"
    printf '%s' "$input" | sed \
        -e 's/&/\&amp;/g' \
        -e 's/</\&lt;/g' \
        -e 's/>/\&gt;/g' \
        -e 's/"/\&quot;/g' \
        -e "s/'/\&apos;/g"
}

print_devices() {
    local devices_file="$1"

    echo
    echo "[*] Available Traccar devices:"
    echo

    jq -r '
        .[]
        | [
            (.id | tostring),
            (.name // "-"),
            (.uniqueId // "-"),
            (.status // "-"),
            (.lastUpdate // "-")
          ]
        | @tsv
    ' "$devices_file" | awk -F '\t' '
        BEGIN {
            printf "%-8s %-30s %-30s %-12s %-25s\n", "ID", "NAME", "UNIQUE ID", "STATUS", "LAST UPDATE"
            printf "%-8s %-30s %-30s %-12s %-25s\n", "--", "----", "---------", "------", "-----------"
        }
        {
            printf "%-8s %-30s %-30s %-12s %-25s\n", $1, $2, $3, $4, $5
        }
    '

    echo
    echo "[*] You can export by numeric ID, name, or unique ID."
    echo
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -id|--id)
            DEVICE_KEY="${2:-}"
            shift 2
            ;;
        -from|--from)
            FROM_DATE="${2:-}"
            shift 2
            ;;
        -to|--to)
            TO_DATE="${2:-}"
            shift 2
            ;;
        --list|list)
            LIST_ONLY="yes"
            shift
            ;;
        -h|--help|help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

require_cmd curl
require_cmd jq
require_cmd awk

validate_tz_offset "$TZ_OFFSET"

if [[ -z "$TRACCAR_USER" || -z "$TRACCAR_PASS" ]]; then
    log_error "TRACCAR_USER and TRACCAR_PASS must be set."
    echo
    usage
    exit 1
fi

COOKIE_FILE="$(mktemp)"
DEVICES_JSON="$(mktemp)"
POSITIONS_JSON_TMP="$(mktemp)"

cleanup() {
    rm -f "$COOKIE_FILE" "$DEVICES_JSON" "$POSITIONS_JSON_TMP"
}
trap cleanup EXIT

log_info "Traccar URL: $TRACCAR_URL"
log_info "Logging in to Traccar API..."

curl -fsS \
    -c "$COOKIE_FILE" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -X POST \
    --data-urlencode "email=${TRACCAR_USER}" \
    --data-urlencode "password=${TRACCAR_PASS}" \
    "${TRACCAR_URL%/}/api/session" >/dev/null

log_success "Login OK."

log_info "Pulling device list from Traccar API..."

curl -fsS \
    -b "$COOKIE_FILE" \
    "${TRACCAR_URL%/}/api/devices" > "$DEVICES_JSON"

DEVICE_COUNT="$(jq 'length' "$DEVICES_JSON")"
log_success "Found ${DEVICE_COUNT} device(s)."

print_devices "$DEVICES_JSON"

if [[ "$LIST_ONLY" == "yes" ]]; then
    exit 0
fi

if [[ -z "$DEVICE_KEY" || -z "$FROM_DATE" || -z "$TO_DATE" ]]; then
    log_error "Missing export arguments."
    usage
    exit 1
fi

FROM_DAY="$(normalize_date "$FROM_DATE")"
TO_DAY="$(normalize_date "$TO_DATE")"

FROM_ISO="${FROM_DAY}T00:00:00${TZ_OFFSET}"
TO_ISO="${TO_DAY}T23:59:59${TZ_OFFSET}"

mkdir -p "$OUT_DIR"

log_info "Selected device search key: $DEVICE_KEY"

DEVICE_MATCH_COUNT="$(jq -r --arg key "$DEVICE_KEY" '
    map(select(
        (.uniqueId // "") == $key or
        (.name // "") == $key or
        ((.id | tostring) == $key)
    )) | length
' "$DEVICES_JSON")"

if [[ "$DEVICE_MATCH_COUNT" -eq 0 ]]; then
    log_error "Device not found: $DEVICE_KEY"
    exit 1
fi

if [[ "$DEVICE_MATCH_COUNT" -gt 1 ]]; then
    log_error "Multiple devices matched: $DEVICE_KEY"
    log_error "Use the numeric ID instead."
    exit 1
fi

DEVICE_ID="$(jq -r --arg key "$DEVICE_KEY" '
    map(select(
        (.uniqueId // "") == $key or
        (.name // "") == $key or
        ((.id | tostring) == $key)
    )) | first | .id
' "$DEVICES_JSON")"

DEVICE_NAME="$(jq -r --arg id "$DEVICE_ID" '
    map(select((.id | tostring) == $id)) | first | .name // "unknown"
' "$DEVICES_JSON")"

DEVICE_UNIQUE_ID="$(jq -r --arg id "$DEVICE_ID" '
    map(select((.id | tostring) == $id)) | first | .uniqueId // "unknown"
' "$DEVICES_JSON")"

DEVICE_STATUS="$(jq -r --arg id "$DEVICE_ID" '
    map(select((.id | tostring) == $id)) | first | .status // "unknown"
' "$DEVICES_JSON")"

DEVICE_NAME_XML="$(xml_escape "$DEVICE_NAME")"
DEVICE_UNIQUE_ID_XML="$(xml_escape "$DEVICE_UNIQUE_ID")"

log_success "Selected device:"
echo "    Numeric ID: $DEVICE_ID"
echo "    Name:       $DEVICE_NAME"
echo "    Unique ID:  $DEVICE_UNIQUE_ID"
echo "    Status:     $DEVICE_STATUS"
echo "    From:       $FROM_ISO"
echo "    To:         $TO_ISO"

SAFE_DEVICE="$(echo "${DEVICE_NAME}_${DEVICE_UNIQUE_ID}_${DEVICE_ID}" | tr -c 'A-Za-z0-9_.-' '_')"
BASE_NAME="${SAFE_DEVICE}_${FROM_DAY}_to_${TO_DAY}"

JSON_FILE="${OUT_DIR}/${BASE_NAME}.json"
GPX_FILE="${OUT_DIR}/${BASE_NAME}.gpx"
CSV_FILE="${OUT_DIR}/${BASE_NAME}.csv"

FROM_ENC="$(urlencode "$FROM_ISO")"
TO_ENC="$(urlencode "$TO_ISO")"

log_info "Downloading route positions from Traccar API..."

curl -fsS \
    -b "$COOKIE_FILE" \
    "${TRACCAR_URL%/}/api/reports/route?deviceId=${DEVICE_ID}&from=${FROM_ENC}&to=${TO_ENC}" \
    > "$POSITIONS_JSON_TMP"

POSITION_COUNT="$(jq 'length' "$POSITIONS_JSON_TMP")"

if [[ "$POSITION_COUNT" -eq 0 ]]; then
    log_error "No positions found for this device/date range."
    exit 1
fi

log_success "Downloaded ${POSITION_COUNT} positions."

log_info "Writing full JSON export..."

jq \
    --arg exportCreatedAt "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg traccarUrl "$TRACCAR_URL" \
    --arg deviceSearchKey "$DEVICE_KEY" \
    --arg deviceId "$DEVICE_ID" \
    --arg deviceName "$DEVICE_NAME" \
    --arg deviceUniqueId "$DEVICE_UNIQUE_ID" \
    --arg deviceStatus "$DEVICE_STATUS" \
    --arg from "$FROM_ISO" \
    --arg to "$TO_ISO" \
    '{
        export: {
            createdAt: $exportCreatedAt,
            source: $traccarUrl,
            deviceSearchKey: $deviceSearchKey,
            deviceId: ($deviceId | tonumber),
            deviceName: $deviceName,
            deviceUniqueId: $deviceUniqueId,
            deviceStatus: $deviceStatus,
            from: $from,
            to: $to,
            format: "traccar-full-json"
        },
        positions: .
    }' "$POSITIONS_JSON_TMP" > "$JSON_FILE"

log_info "Writing CSV export..."

jq -r '
    ["deviceId","positionId","protocol","serverTime","deviceTime","fixTime","valid","latitude","longitude","altitude","speed","course","accuracy","address","attributes_json"],
    (.[] | [
        .deviceId,
        .id,
        (.protocol // ""),
        (.serverTime // ""),
        (.deviceTime // ""),
        (.fixTime // ""),
        (.valid // ""),
        (.latitude // ""),
        (.longitude // ""),
        (.altitude // ""),
        (.speed // ""),
        (.course // ""),
        (.accuracy // ""),
        (.address // ""),
        ((.attributes // {}) | tostring)
    ])
    | @csv
' "$POSITIONS_JSON_TMP" > "$CSV_FILE"

log_info "Writing GPX export..."

{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<gpx version="1.1" creator="traccar-export" xmlns="http://www.topografix.com/GPX/1/1" xmlns:traccar="https://www.traccar.org">'
    echo "  <metadata>"
    echo "    <name>Traccar export - ${DEVICE_NAME_XML}</name>"
    echo "    <desc>Device ID: ${DEVICE_ID}, Unique ID: ${DEVICE_UNIQUE_ID_XML}, From: ${FROM_ISO}, To: ${TO_ISO}</desc>"
    echo "    <time>$(date -u +"%Y-%m-%dT%H:%M:%SZ")</time>"
    echo "  </metadata>"
    echo "  <trk>"
    echo "    <name>${DEVICE_NAME_XML}</name>"
    echo "    <desc>Traccar device ${DEVICE_ID} / ${DEVICE_UNIQUE_ID_XML}</desc>"
    echo "    <trkseg>"

    jq -r '
        .[]
        | select(.latitude != null and .longitude != null)
        | "      <trkpt lat=\"\(.latitude)\" lon=\"\(.longitude)\">\n" +
          "        <ele>\(.altitude // 0)</ele>\n" +
          "        <time>\((.fixTime // .deviceTime // .serverTime // "") | @html)</time>\n" +
          "        <name>position-\(.id)</name>\n" +
          "        <extensions>\n" +
          "          <traccar:positionId>\(.id)</traccar:positionId>\n" +
          "          <traccar:deviceId>\(.deviceId)</traccar:deviceId>\n" +
          "          <traccar:protocol>\((.protocol // "") | @html)</traccar:protocol>\n" +
          "          <traccar:speed>\(.speed // "")</traccar:speed>\n" +
          "          <traccar:course>\(.course // "")</traccar:course>\n" +
          "          <traccar:accuracy>\(.accuracy // "")</traccar:accuracy>\n" +
          "          <traccar:valid>\(.valid // "")</traccar:valid>\n" +
          "          <traccar:serverTime>\((.serverTime // "") | @html)</traccar:serverTime>\n" +
          "          <traccar:deviceTime>\((.deviceTime // "") | @html)</traccar:deviceTime>\n" +
          "          <traccar:attributes>\(((.attributes // {}) | @json) | @html)</traccar:attributes>\n" +
          "        </extensions>\n" +
          "      </trkpt>"
    ' "$POSITIONS_JSON_TMP"

    echo "    </trkseg>"
    echo "  </trk>"
    echo "</gpx>"
} > "$GPX_FILE"

log_success "Export completed."
echo
echo "[+] Files created:"
echo "    GPX:  $GPX_FILE"
echo "    JSON: $JSON_FILE"
echo "    CSV:  $CSV_FILE"
echo
echo "[*] Position count: $POSITION_COUNT"
