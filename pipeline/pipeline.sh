#!/usr/bin/env bash
################################################################################
# Photogrammetry Pipeline (COLMAP + OpenMVS)
# Simple, reliable, sequential execution
#
# Caching logic: A stage runs IFF:
#   1. Any output is missing, OR
#   2. Any output is older than any input
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

################################################################################
# Help function - Delegates to discovery system (unified, no duplication)
################################################################################

# Check for some flags early (before validation)
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            "${SCRIPT_DIR}/discover.sh" --print-help
            exit 0
            ;;
        --print-vars)
            "${SCRIPT_DIR}/discover.sh" --print-vars
            exit 0
            ;;
    esac
done

WORK_DIR="${1:-.}"
IMAGES_DIR="${WORK_DIR}/images"
STAGES_DIR="${SCRIPT_DIR}/stages"
LOGS_DIR="${WORK_DIR}/pipeline/logs"
STAGES_DIR="${WORK_DIR}/pipeline/stages"

# Logging (define early for use during config loading)
log()     { echo "[$(date '+%H:%M:%S')] • $*" >&2; }
log_ok()  { echo "[$(date '+%H:%M:%S')] ✓ $*" >&2; }
log_err() { echo "[$(date '+%H:%M:%S')] ✗ $*" >&2; }
log_dbg() { [[ $VERBOSE == 1 ]] && echo "[$(date '+%H:%M:%S')] ▸ $*" >&2 || true; }

# Stage completion marker helpers
stage_marker_path() {
    echo "${STAGES_DIR}/stage_${1}.done"
}

stage_is_complete() {
    [[ -f "$(stage_marker_path "$1")" ]]
}

stage_mark_complete() {
    touch "$(stage_marker_path "$1")" || return 1
}

# Parse options
VERBOSE=0
DRY_RUN=0
FORCE_STAGES=""
SKIP_STAGES=""

shift || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose) VERBOSE=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --force) FORCE_STAGES="$2"; shift 2 ;;
        --skip) SKIP_STAGES="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Validate work directory
if [[ ! -d "$WORK_DIR" ]]; then
    log_err "Directory not found: $WORK_DIR"
    exit 1
fi
if [[ ! -d "$WORK_DIR/images" ]]; then
    log_err "No images/ directory in: $WORK_DIR"
    exit 1
fi

mkdir -p "$LOGS_DIR" || { log_err "Failed to create logs directory: $LOGS_DIR"; exit 1; }
mkdir -p "$STAGES_DIR" || { log_err "Failed to create logs directory: $STAGES_DIR"; exit 1; }

# Load custom config as soon as possible
CONFIG_FILE="${WORK_DIR}/config.sh"
if [[ -f "$CONFIG_FILE" ]]; then
    log_dbg "Loading config: $CONFIG_FILE"
    if ! source "$CONFIG_FILE"; then
        log_err "Failed to load config: $CONFIG_FILE"
        exit 1
    fi
fi

log_dbg "Work directory: $WORK_DIR (images: $IMAGES_DIR)"
if [[ $VERBOSE == 1 ]]; then log "VERBOSE mode"; fi
if [[ $DRY_RUN == 1 ]]; then log "DRY-RUN mode"; fi

################################################################################
# Import and auto-evaluate tool discovery variables (to set defaults)
################################################################################

# Auto-eval discovered variables to ensure all tools are set
log_dbg "Discovering config..."
eval "$(${SCRIPT_DIR}/discover.sh --print-vars)" || { log_err "Failed to discover tools"; exit 1; }

################################################################################
# Helper functions
################################################################################

# Get modification time of a file or directory (newest mtime for dirs)
# For directories, recursively finds newest file inside
get_mtime() {
    if [[ ! -e "$1" ]]; then
        echo "0"
        return
    fi

    if [[ -d "$1" ]]; then
        # For directories, find the newest file recursively
        local newest_mtime=0
        local file_mtime
        while IFS= read -r -d '' file; do
            file_mtime=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo "0")
            [[ $file_mtime -gt $newest_mtime ]] && newest_mtime=$file_mtime
        done < <(find "$1" -type f -print0)
        echo "$newest_mtime"
    else
        # For files, just get the mtime
        stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo "0"
    fi
}

# Find newest input file
newest_input() {
    local newest_time=0
    for inp in "$@"; do
        [[ -z "$inp" ]] && continue
        local mtime=$(get_mtime "$inp")
        [[ $mtime -gt $newest_time ]] && newest_time=$mtime
    done
    echo "$newest_time"
}

# Find oldest output file
oldest_output() {
    local oldest_time=999999999999
    for out in "$@"; do
        [[ -z "$out" ]] && continue
        [[ ! -e "$out" ]] && echo "0" && return  # Missing output
        local mtime=$(get_mtime "$out")
        [[ $mtime -lt $oldest_time ]] && oldest_time=$mtime
    done
    echo "$oldest_time"
}

# Check if stage should be skipped
is_skipped() {
    local stage=$1
    echo ",$SKIP_STAGES," | grep -qF ",$stage," && return 0 || true
    return 1
}

# Check if stage is forced to run
is_forced() {
    local stage=$1
    echo ",$FORCE_STAGES," | grep -qF ",$stage," && return 0 || true
    return 1
}

# Check if any output is missing or stale (relative to inputs)
# Called with: outputs_stale "$stage" inputs_array outputs_array
outputs_stale() {
    local stage=$1
    local inputs_str="$2"
    local outputs_str="$3"

    # Parse inputs from space-separated string
    local inputs=()
    for inp in $inputs_str; do
        [[ -n "$inp" ]] && inputs+=("$inp")
    done

    # Parse outputs from space-separated string
    local outputs=()
    for out in $outputs_str; do
        [[ -n "$out" ]] && outputs+=("$out")
    done

    # Check if any output is missing
    for out in "${outputs[@]}"; do
        if [[ ! -e "$out" ]]; then
            log_dbg "  Output missing: $out"
            return 0
        fi
    done

    # Check if any output is older than any input
    if [[ ${#inputs[@]} -gt 0 ]] && [[ ${#outputs[@]} -gt 0 ]]; then
        local newest_input_time=$(newest_input "${inputs[@]}")
        local oldest_output_time=$(oldest_output "${outputs[@]}")

        if [[ $newest_input_time -gt $oldest_output_time ]]; then
            log_dbg "  Output stale: input modified after output (input: $newest_input_time, output: $oldest_output_time)"
            return 0
        fi
    fi

    return 1  # All outputs exist and are fresh
}

# Execute stage with logging
run_stage() {
    local stage_name=$1
    local logfile=$2

    # Log file header
    {
        echo "================================================================================"
        echo "Stage: $stage_name"
        echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "================================================================================"
    } > "$logfile"

    # Execute with real-time output in verbose mode
    if [[ $VERBOSE == 1 ]]; then
        (set -x; run_stage_function) 2>&1 | tee -a "$logfile"
        return ${PIPESTATUS[0]}
    else
        run_stage_function >> "$logfile" 2>&1
        return $?
    fi
}

################################################################################
# Discover and execute stages
################################################################################

readarray -t stages < <(find "${STAGES_DIR}" -name "*.stage.sh" | sort) || { log_err "Failed to find stages"; exit 1; }
if [[ ${#stages[@]} -eq 0 ]]; then
    log_err "No stages found in $STAGES_DIR"
    exit 1
fi

log_dbg "Found ${#stages[@]} stages"

# Execute each stage
for stage_file in "${stages[@]}"; do
    stage_name=$(basename "$stage_file" .stage.sh)
    logfile="${LOGS_DIR}/${stage_name}.log"

    # Load stage metadata
    unset DEPENDENCIES INPUTS OUTPUTS run_stage_function
    if ! source "$stage_file"; then
        log_err "Failed to load stage file: $stage_file"
        exit 1
    fi

    # Check skip/force/cache logic
    if is_forced "$stage_name"; then
        log "Stage $stage_name: forced (--force)"
    elif is_skipped "$stage_name"; then
        log "Stage $stage_name: skipped (--skip)"
        continue
    elif stage_is_complete "$stage_name" && ! outputs_stale "$stage_name" "${INPUTS[*]:-}" "${OUTPUTS[*]:-}"; then
        log "Stage $stage_name: cached (completion marker found and outputs are fresh)"
        continue
    else
        log "Stage $stage_name: will run (missing/stale outputs or no completion marker)"
    fi

    # Dry-run mode
    if [[ $DRY_RUN == 1 ]]; then
        log_ok "$stage_name (dry-run)"
        continue
    fi

    # Create log file directory
    if ! mkdir -p "$(dirname "$logfile")"; then
        log_err "Failed to create log directory: $(dirname "$logfile")"
        exit 1
    fi

    # Run stage and capture exit code
    run_stage "$stage_name" "$logfile"
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_err "$stage_name (exit code: $exit_code)"

        # Show error context in verbose mode
        if [[ $VERBOSE == 1 ]]; then
            log_err "Last output:"
            tail -20 "$logfile" 2>/dev/null | sed 's/^/  /' >&2
        else
            log_err "See $logfile for details"
        fi
        exit 1
    fi

    if true; then
        # Verify outputs exist
        missing=0
        for out in "${OUTPUTS[@]:-}"; do
            if [[ ! -e "$out" ]]; then
                log_err "$stage_name: output missing: $out"
                missing=1
            fi
        done

        if [[ $missing == 1 ]]; then
            exit 1
        fi

        # Write completion marker only after successful completion
        if ! stage_mark_complete "$stage_name"; then
            log_err "Failed to write completion marker for $stage_name"
            exit 1
        fi

        log_ok "$stage_name"
    fi
done

log_ok "Pipeline complete"
