#!/usr/bin/env bash
# KZ 18.11.2025
set -euo pipefail

readonly OUT="merged.mp4"
readonly TEMP="merged_nchapters.tmp.mp4"
readonly LIST="files_to_concat.txt"
readonly META="chapters_ffmetadata.txt"
readonly YT="chapters_youtube.txt"

# ---------- helpers ----------

die() {
  echo "ERROR: $*" >&2
  exit 1
}

check_deps() {
  command -v ffmpeg >/dev/null 2>&1 || die "ffmpeg not found in PATH"
  command -v ffprobe >/dev/null 2>&1 || die "ffprobe not found in PATH"
}

find_input_files() {
  shopt -s nullglob
  local arr=( [0-9][0-9]_*.mp4 )
  shopt -u nullglob

  ((${#arr[@]} == 0)) && die "No matching files ([0-9][0-9]_*.mp4) found."

  # sort them numerically
  mapfile -t files < <(printf '%s\n' "${arr[@]}" | sort)
}

build_concat_list() {
  : > "$LIST"
  for f in "${files[@]}"; do
    printf "file '%s'\n" "$f" >> "$LIST"
  done
}

format_timestamp() {
  local secs=$1
  local h=$((secs / 3600))
  local m=$(((secs % 3600) / 60))
  local s=$((secs % 60))

  if (( h > 0 )); then
    printf '%d:%02d:%02d' "$h" "$m" "$s"
  else
    printf '%d:%02d' "$m" "$s"
  fi
}

build_chapters() {
  echo "Building chapter metadata..."
  echo ";FFMETADATA1" > "$META"
  : > "$YT"

  local start=0

  for f in "${files[@]}"; do
    # duration in seconds (integer)
    local dur
    dur=$(ffprobe -v error -show_entries format=duration \
          -of default=noprint_wrappers=1:nokey=1 "$f" || echo 0)
    dur=${dur%.*}
    [[ -z "$dur" ]] && dur=0

    local end=$((start + dur))

    # Derive a nice chapter title from the filename
    local base=${f##*/}           # strip path
    base=${base%.mp4}             # strip extension
    local num=${base%%_*}         # "01"
    local rest=${base#*_}         # "VSEPR.elmelet.Trigonalis...."
    rest=${rest#VSEPR.elmelet.}   # drop "VSEPR.elmelet."
    local title_spaces=${rest//./ } # replace dots with spaces
    local chapter_title="$num – $title_spaces"

    # FFmpeg metadata chapter
    {
      echo "[CHAPTER]"
      echo "TIMEBASE=1/1"
      echo "START=$start"
      echo "END=$end"
      echo "title=$chapter_title"
      echo
    } >> "$META"

    # YouTube chapter line
    local ts
    ts=$(format_timestamp "$start")
    printf '%s %s\n' "$ts" "$chapter_title" >> "$YT"

    start=$end
  done

  echo "Chapter metadata written to:"
  echo "  $META"
  echo "  $YT"
}

mux_with_chapters() {
  echo
  echo "Muxing chapters into final file: $OUT"
  ffmpeg -hide_banner -loglevel error \
    -i "$TEMP" -i "$META" \
    -map 0 -map_metadata 1 -dn -c copy "$OUT"
}

cleanup() {
  echo "Cleaning up temporary file..."
  rm -f "$TEMP"
}

# ---------- main ----------

check_deps
find_input_files

echo "Using files:"
printf '  %s\n' "${files[@]}"

echo
echo "Concatenating into temporary file: $TEMP"
build_concat_list
ffmpeg -hide_banner -loglevel error -f concat -safe 0 -i "$LIST" -c copy "$TEMP"
echo "Concatenation done."

echo
build_chapters
mux_with_chapters
cleanup

echo
echo "Done. Created:"
echo "  $OUT               (with chapters for VLC, etc.)"
echo "  $META              (FFmpeg chapter metadata)"
echo "  $YT                (YouTube description timestamps)"
echo "  $LIST              (concat file list, optional to keep/delete)"
