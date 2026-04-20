#!/usr/bin/env bash
# Production-ready Docker entrypoint for photogrammetry pipeline

set -euo pipefail

# Simple helpers
die() { echo "ERROR: $*" >&2; exit 1; }

# Check for help flag or no args (before any validation)
if [[ $# -eq 0 ]]; then
    show_help=1
else
    show_help=0
    for arg in "$@"; do
        if [[ "$arg" == "--help-entrypoint" ]]; then
            show_help=1
            break
        fi
    done
fi

if [[ $show_help -eq 1 ]]; then
    cat >&2 << 'EOF'
USAGE: entrypoint [OPTIONS] [WORK_DIR]

ARGUMENTS:
  WORK_DIR              Working directory (default: current dir)

OPTIONS:
  --help-entrypoint     Show this help
  -h, --help            Show pipeline help (much more detailed)
  -v, --verbose         Verbose output
  --dry-run             Simulate without executing
  --force STAGES        Force re-run stages (comma-separated)
  --skip STAGES         Skip stages (comma-separated)
  --print-vars          Print configurable environment variables and exit

EXAMPLES:
  entrypoint /data
  entrypoint -v --dry-run /data
  entrypoint --skip 04_colmap_undistortion /data
EOF
    exit 0
fi

# Parse arguments - extract WORK_DIR and options separately
OPTIONS=()
WORK_DIR="<unset>"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help-entrypoint)
            shift
            ;;
        --force|--skip)
            OPTIONS+=("$1" "$2")
            shift 2
            ;;
        -v|--verbose|--dry-run)
            OPTIONS+=("$1")
            shift
            ;;
        -*)
            OPTIONS+=("$1")
            shift
            ;;
        *)
            WORK_DIR="$1"
            shift
            ;;
    esac
done

# Run pipeline with WORK_DIR first, then options
exec /pipeline/pipeline.sh "$WORK_DIR" "${OPTIONS[@]}"
