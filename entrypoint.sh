#!/usr/bin/env bash
# Production-ready Docker entrypoint for photogrammetry pipeline

set -euo pipefail

# Simple helpers
die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "INFO: $*" >&2; }

# Parse arguments
WORK_DIR="${WORK_DIR:-.}"
PIPELINE_OPTS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            cat >&2 << 'EOF'
USAGE: entrypoint [OPTIONS] [WORK_DIR]

ARGUMENTS:
  WORK_DIR              Working directory (default: current dir)

OPTIONS:
  -h, --help            Show this help
  -v, --verbose         Verbose output
  --dry-run             Simulate without executing
  --force STAGES        Force re-run stages (comma-separated)
  --skip STAGES         Skip stages (comma-separated)

ENVIRONMENT:
  PUID                  User ID (default: 1000)
  PGID                  Group ID (default: 1000)

EXAMPLES:
  entrypoint /data
  entrypoint -v --dry-run /data
  entrypoint --skip colmap_undistortion /data

EOF
            exit 0
            ;;
        -v|--verbose)
            PIPELINE_OPTS+=(--verbose)
            shift
            ;;
        --dry-run)
            PIPELINE_OPTS+=(--dry-run)
            shift
            ;;
        --force|--skip)
            PIPELINE_OPTS+=("$1" "$2")
            shift 2
            ;;
        -*)
            die "Unknown option: $1"
            ;;
        *)
            WORK_DIR="$1"
            shift
            ;;
    esac
done

# Validate work directory
[[ ! -d "$WORK_DIR" ]] && die "Directory not found: $WORK_DIR"
[[ ! -d "$WORK_DIR/images" ]] && die "Missing images/ directory in: $WORK_DIR"
WORK_DIR="$(cd "$WORK_DIR" && pwd)"

# Setup user if running as root
if [[ "$(id -u)" == "0" ]]; then
    UID_TARGET=${PUID:-1000}
    GID_TARGET=${PGID:-1000}

    if ! id "$UID_TARGET" >/dev/null 2>&1; then
        useradd -m -u "$UID_TARGET" -s /bin/bash runner 2>/dev/null || true
    fi

    chown -R "$UID_TARGET:$GID_TARGET" "$WORK_DIR" 2>/dev/null || true

    if command -v gosu >/dev/null 2>&1; then
        exec gosu "$UID_TARGET" "$0" "$@"
    else
        exec su - runner -c "$0 $@"
    fi
fi

# Show info and run pipeline
IMAGE_COUNT=$(find "$WORK_DIR/images" -type f 2>/dev/null | wc -l)

exec /pipeline/pipeline.sh "$WORK_DIR" "${PIPELINE_OPTS[@]}"
