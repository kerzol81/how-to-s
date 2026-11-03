#!/usr/bin/env bash
# toDavinciResolve - converts any video into a format the free Linux build of
# DaVinci Resolve can decode: DNxHR video + PCM audio in a .mov container.
#
# Usage:
#   toDavinciResolve -i input.mp4 [-i other.mkv ...] [-o output.mov | -o dir] [-q lb|sq|hq|hqx|444] [-y]

set -u
set -o pipefail

# Bootstrap 5 theme colors as 24-bit ANSI SGR parameters
PRIMARY='38;2;13;110;253'    # #0d6efd
SECONDARY='38;2;108;117;125' # #6c757d
SUCCESS='38;2;25;135;84'     # #198754
DANGER='38;2;220;53;69'      # #dc3545
WARNING='38;2;255;193;7'     # #ffc107
INFO='38;2;13;202;240'       # #0dcaf0

use_color() { [[ -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb && -t $1 ]]; }
# paint FD SGR TEXT... - prints TEXT (no newline), colored only if FD is a terminal
paint() {
    local fd=$1 sgr=$2; shift 2
    if use_color "$fd"; then printf '\033[%sm%s\033[0m' "$sgr" "$*"; else printf '%s' "$*"; fi
}
say()   { local sgr=$1; shift; paint 1 "$sgr" "$*"; echo; }
err()   { paint 2 "$DANGER" "$*" >&2; echo >&2; }
die()   { err "Error: $*"; exit 1; }
field() { printf '  '; paint 1 "$INFO" "$(printf '%-9s' "$1")"; printf ' %s\n' "$2"; }

QUALITY="sq"
OUTPUT=""
OVERWRITE=0
INPUTS=()

usage() {
    local h='' o='' r=''
    if use_color 1; then h=$'\033[1;'"$PRIMARY"m; o=$'\033['"$INFO"m; r=$'\033[0m'; fi
    cat <<EOF
${h}Usage:${r}
  toDavinciResolve -i INPUT [-i INPUT2 ...] [-o OUTPUT] [-q QUALITY] [-y]

${h}Options:${r}
  ${o}-i FILE${r}     Input video (can be given multiple times).
  ${o}-o TARGET${r}   Output .mov file (single input only), or an existing directory.
              Default: next to the input, named "<name>_resolve.mov".
  ${o}-q QUALITY${r}  DNxHR profile (default: sq)
                lb   - smaller files, fine for editing   (~0.3 GB/min at 1080p25)
                sq   - good quality                      (~0.9 GB/min at 1080p25)
                hq   - very good quality                 (~1.3 GB/min at 1080p25)
                hqx  - 10-bit (for HDR / 10-bit sources)
                444  - 10-bit 4:4:4, largest files
  ${o}-y${r}          Overwrite existing output files.
  ${o}-h${r}          Show this help.

${h}Examples:${r}
  toDavinciResolve -i ~/Downloads/video.mp4
  toDavinciResolve -i a.mp4 -i b.mkv -o ~/Videos/resolve
  toDavinciResolve -i phone.mov -q hqx
EOF
}

while getopts ":i:o:q:yh" opt; do
    case "$opt" in
        i) INPUTS+=("$OPTARG") ;;
        o) OUTPUT="$OPTARG" ;;
        q) QUALITY="${OPTARG,,}" ;;
        y) OVERWRITE=1 ;;
        h) usage; exit 0 ;;
        :) die "option -$OPTARG needs a value (see: toDavinciResolve -h)" ;;
        \?) die "unknown option: -$OPTARG (see: toDavinciResolve -h)" ;;
    esac
done
shift $((OPTIND - 1))
[[ $# -gt 0 ]] && die "unexpected argument: '$1' - give inputs with -i"
[[ ${#INPUTS[@]} -eq 0 ]] && { usage; exit 1; }

command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null || die "ffmpeg/ffprobe is not installed (sudo apt install ffmpeg)"

case "$QUALITY" in
    lb)  PROFILE=dnxhr_lb;  PIXFMT=yuv422p;     BPP=0.75 ;;
    sq)  PROFILE=dnxhr_sq;  PIXFMT=yuv422p;     BPP=2.4 ;;
    hq)  PROFILE=dnxhr_hq;  PIXFMT=yuv422p;     BPP=3.6 ;;
    hqx) PROFILE=dnxhr_hqx; PIXFMT=yuv422p10le; BPP=3.6 ;;
    444) PROFILE=dnxhr_444; PIXFMT=yuv444p10le; BPP=7.2 ;;
    *) die "unknown quality: '$QUALITY' (lb, sq, hq, hqx, 444)" ;;
esac

if [[ -n "$OUTPUT" && ! -d "$OUTPUT" && ${#INPUTS[@]} -gt 1 ]]; then
    die "with multiple inputs, -o must be an existing directory"
fi

# Snaps a frame rate to the nearest standard value (phone videos are often
# variable frame rate, which Resolve handles badly).
snap_fps() {
    awk -v r="$1" 'BEGIN {
        n = split(r, p, "/"); f = (n == 2 && p[2] != 0) ? p[1] / p[2] : r + 0
        if (f <= 0 || f > 1000) { print "25"; exit }
        split("24000/1001 24 25 30000/1001 30 48 50 60000/1001 60 100 120000/1001 120", c, " ")
        best = ""; bd = 1e9
        for (i in c) { split(c[i], q, "/"); v = (q[2] ? q[1] / q[2] : q[1]); d = (f > v ? f - v : v - f) / v
                       if (d < bd) { bd = d; best = c[i] } }
        if (bd <= 0.03) print best; else printf "%d\n", f + 0.5
    }'
}

human() { awk -v b="$1" 'BEGIN { split("B KB MB GB TB", u, " "); i = 1; while (b >= 1024 && i < 5) { b /= 1024; i++ } printf "%.1f %s", b, u[i] }'; }

NPROC=$(nproc 2>/dev/null || echo 4)
FAILED=0
DONE=0
SKIPPED=0

for IN in "${INPUTS[@]}"; do
    echo
    say "1;$PRIMARY" "=== $IN"
    if [[ ! -f "$IN" ]]; then err "  Error: file not found, skipping."; FAILED=$((FAILED + 1)); continue; fi

    # Video stream info
    VINFO=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height,avg_frame_rate,r_frame_rate,pix_fmt,codec_name \
        -of default=nw=1 "$IN" 2>/dev/null)
    if [[ -z "$VINFO" ]]; then err "  Error: no video stream (or unreadable file), skipping."; FAILED=$((FAILED + 1)); continue; fi
    W=$(sed -n 's/^width=//p' <<<"$VINFO"); H=$(sed -n 's/^height=//p' <<<"$VINFO")
    VCODEC=$(sed -n 's/^codec_name=//p' <<<"$VINFO"); SRCPIX=$(sed -n 's/^pix_fmt=//p' <<<"$VINFO")
    AVG=$(sed -n 's/^avg_frame_rate=//p' <<<"$VINFO"); RFR=$(sed -n 's/^r_frame_rate=//p' <<<"$VINFO")
    [[ "$AVG" == "0/0" || -z "$AVG" ]] && AVG="$RFR"
    # Prefer the nominal rate (r_frame_rate) when it is close to the average (e.g. VFR phone video at 30 fps)
    if awk -v a="$AVG" -v r="$RFR" 'BEGIN { n = split(a, p, "/"); av = (n == 2 && p[2]) ? p[1] / p[2] : a + 0
                                           m = split(r, q, "/"); rv = (m == 2 && q[2]) ? q[1] / q[2] : r + 0
                                           exit !(rv > 0 && rv <= 240 && (av - rv) / rv < 0.03 && (rv - av) / rv < 0.03) }'; then
        FPS=$(snap_fps "$RFR")
    else
        FPS=$(snap_fps "$AVG")
    fi
    DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$IN" 2>/dev/null)
    [[ "$DUR" =~ ^[0-9.]+$ ]] || DUR=0
    ACOUNT=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$IN" 2>/dev/null | wc -l)

    # Output path
    BASE=$(basename -- "$IN"); BASE="${BASE%.*}"
    if [[ -z "$OUTPUT" ]]; then OUT="$(dirname -- "$IN")/${BASE}_resolve.mov"
    elif [[ -d "$OUTPUT" ]]; then OUT="${OUTPUT%/}/${BASE}_resolve.mov"
    else OUT="$OUTPUT"; [[ "$OUT" == *.mov ]] || OUT="${OUT}.mov"; fi
    if [[ "$(realpath -m -- "$OUT")" == "$(realpath -m -- "$IN")" ]]; then
        err "  Error: the output cannot be the same file as the input."; FAILED=$((FAILED + 1)); continue
    fi
    if [[ -e "$OUT" && $OVERWRITE -eq 0 ]]; then
        say "$WARNING" "  Already exists: $OUT - skipping (use -y to overwrite)."; SKIPPED=$((SKIPPED + 1)); continue
    fi

    # Size estimate and free space
    FPSF=$(awk -v r="$FPS" 'BEGIN { n = split(r, p, "/"); print (n == 2 ? p[1] / p[2] : r) }')
    EST=$(awk -v w="$W" -v h="$H" -v f="$FPSF" -v d="$DUR" -v b="$BPP" 'BEGIN { printf "%.0f", w * h * f * d * b / 8 }')
    FREE=$(( $(df -Pk -- "$(dirname -- "$OUT")" | awk 'NR == 2 { print $4 }') * 1024 ))
    field "Source:" "${VCODEC} ${W}x${H} (${SRCPIX}), ${AVG} fps, $(printf '%.0f' "$DUR") s, ${ACOUNT} audio track(s)"
    field "Target:" "DNxHR ${QUALITY^^} ${PIXFMT}, ${FPS} fps, PCM 48 kHz -> $OUT"
    field "Size:" "~$(human "$EST") estimated (free space: $(human "$FREE"))"
    if (( EST > FREE )); then
        err "  Error: not enough free space, skipping (try -q lb, or -o to another disk)."
        FAILED=$((FAILED + 1)); continue
    fi
    if [[ "$SRCPIX" == *10* || "$SRCPIX" == *12* ]] && [[ "$QUALITY" != hqx && "$QUALITY" != 444 ]]; then
        say "$WARNING" "  Note: the source is 10/12-bit; to keep the full bit depth use -q hqx"
    fi

    # Thread count from available memory (4K needs ~0.5 GB per thread, otherwise the OOM killer strikes)
    AVAIL_MB=$(awk '/^MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo)
    PER_THREAD=$(awk -v w="$W" -v h="$H" 'BEGIN { r = w * h / (1920 * 1080); if (r < 0.25) r = 0.25; printf "%d", 120 * r }')
    BASE_MB=$(( PER_THREAD * 2 + 150 ))
    THREADS=$(( (AVAIL_MB * 7 / 10 - BASE_MB) / PER_THREAD ))
    (( THREADS > NPROC )) && THREADS=$NPROC
    (( THREADS < 1 )) && THREADS=1
    field "Threads:" "$THREADS (available memory: ${AVAIL_MB} MB)"

    TMP="${OUT%.mov}.part.mov"
    START=$(date +%s)
    if ffmpeg -nostdin -hide_banner -loglevel error -stats -y \
            -threads "$THREADS" -i "$IN" \
            -map 0:v:0 -map '0:a?' -map_metadata 0 \
            -c:v dnxhd -profile:v "$PROFILE" -pix_fmt "$PIXFMT" \
            -r "$FPS" -fps_mode cfr \
            -c:a pcm_s16le -ar 48000 \
            -threads "$THREADS" \
            "$TMP"; then
        mv -f -- "$TMP" "$OUT"
        say "$SUCCESS" "  Done ($(( $(date +%s) - START )) s): $OUT ($(human "$(stat -c %s -- "$OUT")"))"
        DONE=$((DONE + 1))
    else
        rc=$?
        rm -f -- "$TMP"
        if [[ $rc -eq 137 ]]; then
            err "  Error: ffmpeg was killed by the system (most likely out of memory). Close some programs and try again."
        else
            err "  Error: ffmpeg failed (exit code $rc)."
        fi
        FAILED=$((FAILED + 1))
    fi
done

echo
printf 'Total: '
paint 1 "$SUCCESS" "$DONE done"; printf ', '
if (( FAILED > 0 )); then paint 1 "$DANGER" "$FAILED failed"; else paint 1 "$SECONDARY" "0 failed"; fi
(( SKIPPED > 0 )) && { printf ', '; paint 1 "$WARNING" "$SKIPPED skipped"; }
echo "."
[[ $FAILED -eq 0 ]]
