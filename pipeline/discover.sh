#!/usr/bin/env bash
################################################################################
# Tool Discovery System - Discovers COLMAP and OpenMVS tools from stages
# Generates unified help, config templates, and tool documentation
# Usage: ./discover.sh [--print-help | --print-config | --print-vars]
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGES_DIR="${SCRIPT_DIR}/stages"

################################################################################
# Discover COLMAP tools and arguments from stages
################################################################################

discover_colmap_from_stages() {
    local -a feature_extractors matchers mappers undistorters
    local feature_extractor_args matcher_args mapper_args undistorter_args

    # Parse feature extraction stage
    if [[ -f "${STAGES_DIR}/01_colmap_feature_extraction.stage.sh" ]]; then
        feature_extractor_args=$(grep -oP 'COLMAP_FEATURE_EXTRACTOR_ARGS\K[^}]*' "${STAGES_DIR}/01_colmap_feature_extraction.stage.sh" 2>/dev/null || echo "")
    fi

    # Parse matching stage - extract COLMAP_MATCHER and COLMAP_MATCHER_ARGS
    if [[ -f "${STAGES_DIR}/02_colmap_feature_matching.stage.sh" ]]; then
        local matcher_line
        matcher_line=$(grep -oP 'colmap \$\{COLMAP_MATCHER\}' "${STAGES_DIR}/02_colmap_feature_matching.stage.sh" 2>/dev/null || true)
        if [[ -n "$matcher_line" ]]; then
            # Known matchers based on COLMAP documentation
            COLMAP_MATCHERS="vocab_tree_matcher exhaustive_matcher spatial_matcher sequential_matcher transitive_matcher"
        fi
        matcher_args=$(grep -oP 'COLMAP_MATCHER_ARGS\K[^}]*' "${STAGES_DIR}/02_colmap_feature_matching.stage.sh" 2>/dev/null || echo "")
    fi

    # Parse mapping stage - extract COLMAP_MAPPER and COLMAP_MAPPER_ARGS
    if [[ -f "${STAGES_DIR}/03_colmap_mapping.stage.sh" ]]; then
        local mapper_line
        mapper_line=$(grep -oP 'colmap \$\{COLMAP_MAPPER\}' "${STAGES_DIR}/03_colmap_mapping.stage.sh" 2>/dev/null || true)
        if [[ -n "$mapper_line" ]]; then
            # Known mappers based on COLMAP documentation
            COLMAP_MAPPERS="global_mapper mapper"
        fi
        mapper_args=$(grep -oP 'COLMAP_MAPPER_ARGS\K[^}]*' "${STAGES_DIR}/03_colmap_mapping.stage.sh" 2>/dev/null || echo "")
    fi

    # Parse undistortion stage
    if [[ -f "${STAGES_DIR}/04_colmap_undistortion.stage.sh" ]]; then
        undistorter_args=$(grep -oP 'COLMAP_UNDISTORTER_ARGS\K[^}]*' "${STAGES_DIR}/04_colmap_undistortion.stage.sh" 2>/dev/null || echo "")
    fi

    COLMAP_TOOLS="feature_extractor feature_matching mapper undistortion"
}

################################################################################
# Discover OpenMVS tools from stages
################################################################################

discover_openmvs_from_stages() {
    local -a tools
    local tool_name tool_args

    # Scan all OpenMVS stages and extract tool names and args
    for stage_file in "${STAGES_DIR}"/05_openmvs_*.stage.sh; do
        [[ ! -f "$stage_file" ]] && continue

        # Extract tool name (first command after cd)
        tool_name=$(grep -oP '(?:^|\s)([A-Z][a-zA-Z]+)(?:\s|$)' "$stage_file" | grep -v 'cd\|mkdir\|touch' | head -1 | tr -d ' ' || true)

        if [[ -n "$tool_name" ]]; then
            local stage_basename
            stage_basename=$(basename "$stage_file" .stage.sh)
            local env_name
            env_name=$(echo "$stage_basename" | sed 's/^[0-9]*_openmvs_//' | sed 's/_/ /g' | tr '[:lower:]' '[:upper:]' | tr ' ' '_')

            # Store tool info
            echo "$tool_name|$env_name"
        fi
    done | sort -u
}

################################################################################
# Generate unified help with tool details
################################################################################

generate_help() {
    discover_colmap_from_stages

    cat << 'EOF'
================================================================================
Photogrammetry Pipeline - COLMAP + OpenMVS
================================================================================

USAGE:
  pipeline.sh <work-dir> [options]

ARGUMENTS:
  work-dir              Directory containing images/ subdirectory

OPTIONS:
  -v, --verbose         Enable verbose output with real-time execution logs
  --dry-run             Show what would be executed without running
  --force STAGES        Force re-run specific stages (comma-separated list)
  --skip STAGES         Skip specific stages (comma-separated list)
  -h, --help            Show this help message

EXAMPLES:
  pipeline.sh /data/project
  pipeline.sh /data/project -v --dry-run
  pipeline.sh /data/project --force 01_colmap_feature_extraction,03_colmap_mapping
  pipeline.sh /data/project --skip 06_openmvs_sparse_mesh

PIPELINE STAGES:
  COLMAP (Feature Detection, Matching, Mapping):
    01_colmap_feature_extraction    Extract SIFT features from images
    02_colmap_feature_matching      Match features between image pairs
    03_colmap_mapping               Structure-from-motion reconstruction
    04_colmap_undistortion          Undistort images for dense matching

  OpenMVS (Dense Reconstruction):
    05_openmvs_scene_export         Convert COLMAP output to MVS format
    06_openmvs_sparse_mesh          Reconstruct sparse mesh
    07_openmvs_sparse_refine        Refine sparse mesh
    08_openmvs_sparse_texture       Texture sparse mesh
    09_openmvs_densify              Generate dense point cloud
    10_openmvs_dense_mesh           Reconstruct dense mesh
    11_openmvs_dense_refine         Refine dense mesh
    12_openmvs_dense_texture        Texture dense mesh

USAGE EXAMPLES:
  # Use exhaustive matcher for better quality (slower)
  export COLMAP_MATCHER=exhaustive_matcher
  pipeline.sh /data/project

  # Use incremental mapper instead of global
  export COLMAP_MAPPER=mapper
  pipeline.sh /data/project

  # Parallelize feature extraction with 8 threads
  export COLMAP_FEATURE_EXTRACTOR_ARGS="--SiftExtraction.num_threads 8"
  pipeline.sh /data/project

  # Combine multiple settings
  COLMAP_MATCHER=exhaustive_matcher COLMAP_MATCHER_ARGS="--ExhaustiveMatching.num_threads 8" \
    pipeline.sh /data/project -v

OUTPUT STRUCTURE:
  <work-dir>/
    images/                         Input images (required)
    logs/                         Execution logs for each stage
    colmap/
      database.db                   COLMAP feature database
      sparse/0/                     Sparse reconstruction (cameras, images, points)
      dense/                        Undistorted images for dense reconstruction
    openmvs/
      scene.mvs                     MVS scene file
      scene_mesh.ply                Sparse mesh output
      scene_dense.mvs               Dense point cloud
      scene_dense_mesh.ply          Final dense mesh

================================================================================
COLMAP TOOL HELP:
================================================================================
EOF

    # Print COLMAP main help
    echo "COLMAP Main Help:"
    colmap --help 2>/dev/null || echo "  (COLMAP not installed or not in PATH)"
    echo ""

    # Discover and print help for each COLMAP subcommand
    if command -v colmap &> /dev/null; then
        local colmap_commands
        colmap_commands=$(colmap --help | grep -oP '^\s+\K[a-z_]+(?=\s|$)' | grep -v '^$' || true)

        if [[ -n "$colmap_commands" ]]; then
            while IFS= read -r cmd; do
                [[ -z "$cmd" ]] && continue
                echo "===> COLMAP $cmd Help:"
                colmap "$cmd" --help || echo "  (Command '$cmd' not available)"
                echo ""
            done <<< "$colmap_commands"
        fi
    fi

    cat << 'EOF'
================================================================================
OPENMVS TOOL HELP:
================================================================================
EOF

    # Discover and print help for each OpenMVS tool
    local openmvs_bin_dir="/usr/local/bin/OpenMVS"
    if [[ -d "$openmvs_bin_dir" ]]; then
        local openmvs_tools
        openmvs_tools=$(ls "$openmvs_bin_dir" | grep -v '^\.' || true)

        if [[ -n "$openmvs_tools" ]]; then
            while IFS= read -r tool; do
                [[ -z "$tool" ]] && continue
                echo "===> OpenMVS $tool Help:"
                "$openmvs_bin_dir/$tool" --help || true # || echo "  (Tool '$tool' not available)"
                echo ""
            done <<< "$openmvs_tools"
        fi
    else
        echo "  (OpenMVS not found in $openmvs_bin_dir)"
    fi

    cat << 'EOF'
================================================================================

To configure the stages as shown above, set the following environment variables:
EOF
    print_vars
}

################################################################################
# Print discovered variables
################################################################################

print_vars() {
    local -A defined_vars
    local -a undefined_vars

    # Collect all variable accesses from stage files
    local all_vars
    all_vars=$(grep -h -oP '\$\{[A-Z_][A-Z0-9_]*\}' "${STAGES_DIR}"/*.stage.sh | sed 's/[${}]//g')

    # Variables defined in pipeline.sh (these should not be reported)
    defined_vars=$(grep -h -oP '[A-Z_][A-Z0-9_]*=' "${SCRIPT_DIR}/pipeline.sh" | sed 's/=//g')
    for var in $defined_vars; do
        defined_vars["$var"]=1
    done

    # Find all undefined variables
    while IFS= read -r var; do
        [[ -z "$var" ]] && continue
        if [[ -z "${defined_vars[$var]:-}" ]]; then
            undefined_vars+=("$var")
        fi
    done <<< "$all_vars"

    COLMAP_MATCHERS=(vocab_tree_matcher exhaustive_matcher spatial_matcher sequential_matcher transitive_matcher)
    COLMAP_MAPPERS=(global_mapper mapper)

    # Print discovered undefined variables
    for var in "${undefined_vars[@]}"; do
        # Special case for non-args variables:
        if [[ "$var" == "COLMAP_MATCHER" ]]; then
            echo "export COLMAP_MATCHER=\"\${COLMAP_MATCHER:-${COLMAP_MATCHERS[0]}}\" # Available matchers: ${COLMAP_MATCHERS[@]}"
        elif [[ "$var" == "COLMAP_MAPPER" ]]; then
            echo "export COLMAP_MAPPER=\"\${COLMAP_MAPPER:-${COLMAP_MAPPERS[0]}}\" # Available mappers: ${COLMAP_MAPPERS[@]}"
        else
            echo "export $var=\"\${${var}:-}\""
        fi
    done
}

################################################################################
# Main
################################################################################

case "${1:-config}" in
    --print-help)
        generate_help
        ;;
    --print-vars)
        print_vars
        ;;
    --help|-h)
        cat << 'EOF'
Tool Discovery System
Usage: discover.sh [--print-help | --print-config | --print-vars | --help]

  --print-help      Show formatted help for pipeline with all tools and options
  --print-config    Show configuration template with all environment variables
  --print-vars      Print discovered tool variables (for sourcing)
  --help, -h        Show this help message

Examples:
  ./discover.sh --print-help
  ./discover.sh --print-config > new_config.sh
  eval $(./discover.sh --print-vars)
EOF
        ;;
esac
