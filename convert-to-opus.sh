#!/usr/bin/env bash
#
# convert-to-opus.sh
#
# Recursively convert audio to Opus, including audio inside ZIP/7z archives.
#
# Ordinary directories:
#   Convert to .opus, validate, then remove the original audio.
#
# Archives:
#   Extract to a private temporary directory.
#   Convert audio while preserving all non-audio files and directory structure.
#   Rebuild in the original archive format.
#   Test the rebuilt archive.
#   Replace the original archive only after successful validation.
#
# Requirements: Bash 4+, ffmpeg with libopus, ffprobe, 7z, GNU coreutils.
#
# Usage:
#   ./convert-to-opus.sh DIRECTORY
#   DRY_RUN=1 ./convert-to-opus.sh DIRECTORY
#   BITRATE=20k ./convert-to-opus.sh DIRECTORY
#
# Configuration:
#   BITRATE=24k
#   SAMPLE_RATE=24000
#   CHANNELS=1
#   APP=audio
#   MIN_FREE_MB=100
#   LOG_FILE=opus-conversion.log
#   DRY_RUN=0
#
# WARNING:
#   Conversion to Opus is lossy. Keep backups until the results
#   have been audited and listened to.

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

BITRATE="${BITRATE:-24k}"
SAMPLE_RATE="${SAMPLE_RATE:-24000}"
CHANNELS="${CHANNELS:-1}"
APP="${APP:-audio}"
MIN_FREE_MB="${MIN_FREE_MB:-100}"
LOG_FILE="${LOG_FILE:-opus-conversion.log}"
DRY_RUN="${DRY_RUN:-0}"

log() {
    printf '%s %-5s %s\n' \
        "$(date '+%F %T')" "$1" "$2" |
        tee -a "$LOG_FILE"
}

die() {
    log ERROR "$*"
    exit 1
}

usage() {
    echo "Usage: $0 DIRECTORY" >&2
    exit 2
}

[[ $# -eq 1 ]] || usage

ROOT="$(realpath -- "$1")"
[[ -d "$ROOT" ]] || die "Not a directory: $ROOT"

# Validate configuration before processing files.
[[ "$BITRATE" =~ ^[0-9]+([.][0-9]+)?k$ ]] ||
    die "BITRATE must look like 24k or 20k"

[[ "$SAMPLE_RATE" =~ ^[0-9]+$ ]] ||
    die "SAMPLE_RATE must be an integer"

(( SAMPLE_RATE >= 8000 && SAMPLE_RATE <= 48000 )) ||
    die "SAMPLE_RATE must be between 8000 and 48000"

[[ "$CHANNELS" =~ ^[12]$ ]] ||
    die "CHANNELS must be 1 or 2"

[[ "$MIN_FREE_MB" =~ ^[0-9]+$ ]] ||
    die "MIN_FREE_MB must be a non-negative integer"

[[ "$DRY_RUN" == 0 || "$DRY_RUN" == 1 ]] ||
    die "DRY_RUN must be 0 or 1"

case "$APP" in
    audio|voip|lowdelay) ;;
    *) die "APP must be audio, voip, or lowdelay" ;;
esac

for cmd in ffmpeg ffprobe 7z find df stat mktemp realpath \
           awk grep sed tee date head chmod mv rm; do
    command -v "$cmd" >/dev/null 2>&1 ||
        die "Required command not found: $cmd"
done

# Use the libopus encoder
# ffmpeg -hide_banner -encoders 2>/dev/null |
#     grep -q 'opus' ||
#     die "FFmpeg does not provide the libopus encoder"
# Require libopus; do not silently fall back to the native Opus encoder.
if ffmpeg -hide_banner -encoders 2>/dev/null |
    awk '$2 == "libopus" { found=1 } END { exit !found }'; then
    OPUS_ENCODER=libopus
else
    die "FFmpeg does not provide libopus. Check: ffmpeg -hide_banner -encoders | grep -i opus"
fi

log INFO "Using Opus encoder: $OPUS_ENCODER"




# Verify that ffmpeg and ffprobe are executable.
ffmpeg -version >/dev/null 2>&1 ||
    die "FFmpeg failed its startup check"

ffprobe -version >/dev/null 2>&1 ||
    die "FFprobe failed its startup check"

# Check that the target filesystem is writable.
[[ -w "$ROOT" ]] ||
    die "Root directory is not writable: $ROOT"

WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT

log INFO "Root: $ROOT"
log INFO "Bitrate: $BITRATE"
log INFO "Sample rate: $SAMPLE_RATE"
log INFO "Channels: $CHANNELS"
log INFO "Application: $APP"
log INFO "Minimum free-space reserve: ${MIN_FREE_MB} MB"
log INFO "Dry run: $DRY_RUN"

# Extensions recognized as audio by this script.
is_audio_extension() {
    case "${1,,}" in
        mp3|m4a|m4b|aac|wav|flac|ogg|opus|wma|aif|aiff|ape|alac)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_source_audio_extension() {
    case "${1,,}" in
        mp3|m4a|m4b|aac|wav|flac|ogg|wma|aif|aiff|ape|alac)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

have_space() {
    local dir="$1"
    local required="$2"
    local available

    available="$(df -PB1 -- "$dir" |
        awk 'NR==2 {print $4}')"

    [[ "$available" =~ ^[0-9]+$ ]] || return 1

    (( available >= required ))
}

# Return success only when a file is a readable Opus audio stream.
is_valid_opus() {
    local file="$1"
    local codec

    codec="$(ffprobe -v error -select_streams a:0 \
        -show_entries stream=codec_name \
        -of default=noprint_wrappers=1:nokey=1 \
        "$file" 2>/dev/null)" || return 1

    [[ "$codec" == opus ]] || return 1

    ffmpeg -nostdin -v error -xerror -i "$file" \
        -map 0:a:0 -f null - \
        >/dev/null 2>"$WORK/validate.err"
}

# Convert one source file.
#
# A source is removed only after:
#   1. Successful encoding.
#   2. Successful Opus codec verification.
#   3. Successful complete decode.
#   4. Non-empty output.
#
# Failures leave the source in place and return a non-zero status.
convert_audio() {
    local src="$1"
    local destdir="$2"
    local base out tmp duration estimate srcsize
    local codec channels rate
    local required_bytes

    base="$(basename -- "$src")"
    base="${base%.*}"
    out="$destdir/$base.opus"

    if [[ ! -f "$src" ]]; then
        log WARN "Source is no longer a regular file: $src"
        return 1
    fi

    if [[ -e "$out" ]]; then
        log WARN "Output already exists; source retained: $src"
        return 1
    fi

    if ! ffprobe -v error -select_streams a:0 \
        -show_entries stream=codec_name,sample_rate,channels \
        -of default=noprint_wrappers=1 \
        "$src" >"$WORK/probe.txt" 2>"$WORK/probe.err"; then
        log WARN "Cannot identify audio stream: $src"
        cat "$WORK/probe.err" >>"$LOG_FILE" || :
        return 1
    fi

    codec="$(sed -n 's/^codec_name=//p' "$WORK/probe.txt" |
        head -n 1)"
    rate="$(sed -n 's/^sample_rate=//p' "$WORK/probe.txt" |
        head -n 1)"
    channels="$(sed -n 's/^channels=//p' "$WORK/probe.txt" |
        head -n 1)"

    if [[ -z "$codec" ||
          ! "$rate" =~ ^[0-9]+$ ||
          ! "$channels" =~ ^[0-9]+$ ]]; then
        log WARN "Unknown audio parameters; source retained: $src"
        return 1
    fi

    duration="$(ffprobe -v error \
        -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 \
        "$src" 2>/dev/null || :)"

    if ! awk -v d="$duration" \
        'BEGIN {exit !(d ~ /^[0-9]+([.][0-9]+)?$/ && d > 0)}'; then
        log WARN "Unknown or invalid duration; source retained: $src"
        return 1
    fi

    srcsize="$(stat -c %s -- "$src")"

    # Estimate output size from duration and configured bitrate.
    # Add 10 MiB of working margin, plus the configured free-space reserve.
    estimate="$(awk -v d="$duration" -v b="$BITRATE" '
        BEGIN {
            sub(/k$/, "", b)
            printf "%.0f", d * b * 1000 / 8 + 10485760
        }')" || {
        log WARN "Cannot estimate output size: $src"
        return 1
    }

    required_bytes=$((estimate + MIN_FREE_MB * 1048576))

    if ! have_space "$destdir" "$required_bytes"; then
        log WARN "Insufficient free space; source retained: $src"
        return 1
    fi

    log INFO "Source: $src"
    log INFO "Format: codec=$codec rate=$rate channels=$channels duration=${duration}s bytes=$srcsize"

    if [[ "$DRY_RUN" == 1 ]]; then
        log INFO "DRY RUN: would convert to $out"
        return 0
    fi

    # Create a temporary output on the destination filesystem.
    tmp="$(mktemp "$destdir/.opus-tmp.XXXXXX")"
    rm -f -- "$tmp"

    if ! ffmpeg -nostdin -hide_banner -nostats \
        -loglevel warning \
        -i "$src" \
        -map 0:a:0 -vn -sn -dn \
        -map_metadata 0 \
        -ac "$CHANNELS" \
        -ar "$SAMPLE_RATE" \
        -c:a libopus \
        -b:a "$BITRATE" \
        -vbr on \
        -application "$APP" \
        -compression_level 10 \
        -f opus "$tmp" \
        2>"$WORK/ffmpeg.err"; then

        log WARN "Encoding failed; source retained: $src"
        cat "$WORK/ffmpeg.err" >>"$LOG_FILE" || :
        rm -f -- "$tmp"
        return 1
    fi

    if ! is_valid_opus "$tmp"; then
        log WARN "Output validation failed; source retained: $src"
        cat "$WORK/validate.err" >>"$LOG_FILE" || :
        rm -f -- "$tmp"
        return 1
    fi

    if [[ ! -s "$tmp" ]]; then
        log WARN "Empty output; source retained: $src"
        rm -f -- "$tmp"
        return 1
    fi

    # Do not overwrite a pre-existing output.
    if [[ -e "$out" ]]; then
        log WARN "Output appeared during conversion; source retained: $src"
        rm -f -- "$tmp"
        return 1
    fi

    if ! mv -n -- "$tmp" "$out"; then
        log WARN "Cannot install output; source retained: $src"
        rm -f -- "$tmp"
        return 1
    fi

    if [[ -e "$tmp" ]]; then
        log WARN "Output installation was inconclusive; source retained: $src"
        rm -f -- "$tmp"
        return 1
    fi

    # Verify the installed file before deleting the source.
    if ! is_valid_opus "$out"; then
        log WARN "Installed output failed validation; source retained: $src"
        cat "$WORK/validate.err" >>"$LOG_FILE" || :
        rm -f -- "$out"
        return 1
    fi

    log INFO "Validated output: $out ($(stat -c %s -- "$out") bytes)"

    if ! rm -- "$src"; then
        log WARN "Conversion succeeded but source deletion failed: $src"
        return 1
    fi

    log INFO "Removed original: $src"
    return 0
}

# Rebuild a ZIP or 7z archive from the extracted directory.
#
# The original archive is never removed until the rebuilt archive has
# passed its integrity test and its audio entries have been checked.
process_archive() {
    local archive="$1"
    local parent name ext archive_type
    local extractdir rebuilt f suffix failed
    local had_source_audio=0

    parent="$(dirname -- "$archive")"
    name="$(basename -- "$archive")"
    ext="${name##*.}"
    ext="${ext,,}"

    case "$ext" in
        zip) archive_type=zip ;;
        7z)  archive_type=7z ;;
        *)   return 0 ;;
    esac

    log INFO "Archive: $archive"

    if [[ "$DRY_RUN" == 1 ]]; then
        log INFO "DRY RUN: would extract, convert, validate, and rebuild: $archive"
        return 0
    fi

    # Require enough room for extracted contents and a rebuilt archive.
    # This is a conservative check, not a guarantee against quota limits.
    if ! have_space "$parent" "$((MIN_FREE_MB * 1048576))"; then
        log WARN "Insufficient free-space reserve; archive retained: $archive"
        return 1
    fi

    extractdir="$(mktemp -d "$WORK/archive.XXXXXX")"

    if ! 7z x -y "-o$extractdir" -- "$archive" \
        >"$WORK/7z-extract.out" 2>"$WORK/7z-extract.err"; then
        log WARN "Extraction failed; archive retained: $archive"
        cat "$WORK/7z-extract.err" >>"$LOG_FILE" || :
        return 1
    fi

    # Do not follow symlinks when scanning extracted contents.
    # Conversion is restricted to regular files.
    while IFS= read -r -d '' f; do
        suffix="${f##*.}"

        if ! is_source_audio_extension "$suffix"; then
            continue
        fi

        had_source_audio=1

        if ! convert_audio "$f" "$(dirname -- "$f")"; then
            log WARN "Archive conversion failed: $f"
        fi
    done < <(find "$extractdir" -type f -print0)

    # If any recognized original audio remains, do not rebuild.
    # This includes failures, ambiguous output-name collisions, and
    # sources that could not be identified as valid audio.
    failed=0

    while IFS= read -r -d '' f; do
        suffix="${f##*.}"

        if is_source_audio_extension "$suffix"; then
            log WARN "Unconverted audio remains; archive retained: $f"
            failed=1
        fi
    done < <(find "$extractdir" -type f -print0)

    if (( failed )); then
        return 1
    fi

    if (( ! had_source_audio )); then
        log INFO "No recognized source audio found: $archive"
        return 0
    fi

    # Create a unique temporary archive beside the original.
    rebuilt="$(mktemp "$parent/.${name}.rebuilt.XXXXXX")"
    rm -f -- "$rebuilt"

    # Explicit -tzip/-t7z avoids relying on the temporary filename suffix.
    # Running from the extraction directory keeps archive paths relative.
    if ! (
        cd "$extractdir"
        7z a "-t$archive_type" "$rebuilt" . \
            >"$WORK/7z-rebuild.out" 2>"$WORK/7z-rebuild.err"
    ); then
        log WARN "Rebuild failed; archive retained: $archive"
        cat "$WORK/7z-rebuild.err" >>"$LOG_FILE" || :
        rm -f -- "$rebuilt"
        return 1
    fi

    # Verify archive integrity.
    if ! 7z t -- "$rebuilt" \
        >"$WORK/7z-test.out" 2>"$WORK/7z-test.err"; then
        log WARN "Archive integrity test failed; original retained: $archive"
        cat "$WORK/7z-test.err" >>"$LOG_FILE" || :
        rm -f -- "$rebuilt"
        return 1
    fi

    # Verify that no recognized source audio entries remain.
    # Use the archive listing's Path fields, not its binary contents.
    if ! 7z l -slt -- "$rebuilt" >"$WORK/7z-list.txt" 2>/dev/null; then
        log WARN "Cannot inspect rebuilt archive; original retained: $archive"
        rm -f -- "$rebuilt"
        return 1
    fi

    if grep -Ei '^Path = .*[.](mp3|m4a|m4b|aac|wav|flac|ogg|wma|aif|aiff|ape|alac)$' \
        "$WORK/7z-list.txt" >/dev/null; then
        log WARN "Original audio extension remains in rebuilt archive; original retained: $archive"
        rm -f -- "$rebuilt"
        return 1
    fi

    # Preserve the original archive's permission bits when possible.
    chmod --reference="$archive" "$rebuilt" 2>/dev/null || :

    # Replace the original only after all checks succeed.
    if ! mv -f -- "$rebuilt" "$archive"; then
        log ERROR "Cannot replace archive; original retained if rename failed: $archive"
        rm -f -- "$rebuilt"
        return 1
    fi

    log INFO "Rebuilt and validated archive: $archive"
    return 0
}

# Main traversal.
#
# Archives are rebuilt in place. Directories inside archives are handled
# only by process_archive(), not as separate top-level files.
#
# Existing .opus files are left untouched.
while IFS= read -r -d '' f; do
    # Ignore anything under our private temporary workspace.
    case "$f" in
        "$WORK"/*) continue ;;
    esac

    # Do not process symlinks or non-regular files.
    [[ -f "$f" && ! -L "$f" ]] || continue

    ext="${f##*.}"
    ext="${ext,,}"

    case "$ext" in
        zip|7z)
            process_archive "$f" || log WARN "Archive processing did not complete successfully: $f"
            ;;
        opus)
            log INFO "Already Opus; skipped: $f"
            ;;
        mp3|m4a|m4b|aac|wav|flac|ogg|wma|aif|aiff|ape|alac)
            convert_audio "$f" "$(dirname -- "$f")" ||
                log WARN "Audio conversion did not complete successfully: $f"
            ;;
        *)
            # Other files are preserved.
            # Unknown extensions are not assumed to be audio.
            ;;
    esac
done < <(find "$ROOT" -type f -print0)

log INFO "Finished processing: $ROOT"
