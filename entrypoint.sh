#!/usr/bin/env bash
set -euo pipefail

########################################
# Logging setup
########################################
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

log "=== COLMAP + OpenMVS Pipeline Starting ==="

########################################
# Input validation
########################################
obj="${1:-}"
if [[ -z "$obj" ]]; then
    echo "ERROR: Missing obj folder as the first argument." >&2
    echo "Usage: $0 <obj_folder> [additional_args...]" >&2
    echo "  obj_folder should contain an 'images/' subfolder" >&2
    exit 1
fi

if [[ ! -d "$obj" ]]; then
    echo "ERROR: Directory does not exist: $obj" >&2
    exit 1
fi

if [[ ! -d "$obj/images" ]]; then
    echo "ERROR: 'images/' subfolder not found in: $obj" >&2
    exit 1
fi

obj="$(cd "$obj" && pwd)"
log "Working directory: $obj"

########################################
# User/permission handling (safe)
########################################
setup_user() {
    local target_uid="${PUID:-$(id -u)}"
    local target_gid="${PGID:-${PUID:-$(id -g)}}"
    local current_uid
    current_uid="$(id -u)"
    local current_gid
    current_gid="$(id -g)"

    if [[ "$current_uid" == "$target_uid" ]] && [[ "$current_gid" == "$target_gid" ]]; then
        return 0
    fi

    log "Switching to UID:GID = ${target_uid}:${target_gid}"

    # Resolve or create group
    local target_group
    target_group="$(getent group "$target_gid" 2>/dev/null | cut -d: -f1 || true)"
    if [[ -z "$target_group" ]]; then
        target_group="${GROUPNAME:-containergroup}"
        if ! getent group "$target_group" >/dev/null 2>&1; then
            groupadd -g "$target_gid" "$target_group" 2>/dev/null || true
        fi
    fi

    # Resolve or create user
    local target_user
    target_user="$(getent passwd "$target_uid" 2>/dev/null | cut -d: -f1 || true)"
    if [[ -z "$target_user" ]]; then
        target_user="${USERNAME:-containeruser}"
        if ! getent passwd "$target_user" >/dev/null 2>&1; then
            useradd -m -u "$target_uid" -g "$target_gid" -s /bin/bash "$target_user" 2>/dev/null || true
        fi
    fi

    # Fix ownership only on the working directory
    chown -R "${target_uid}:${target_gid}" "$obj" 2>/dev/null || log "WARNING: Could not change ownership on $obj"

    # Re-exec with proper UID/GID using gosu or su-exec if available, fallback to su
    if command -v gosu >/dev/null 2>&1; then
        exec gosu "$target_user" "$0" "$@"
    elif command -v su-exec >/dev/null 2>&1; then
        exec su-exec "$target_user" "$0" "$@"
    else
        exec su -s /bin/bash "$target_user" -c "\"$0\" \"$@\""
    fi
}

# Only run user setup if not already root matching target
if [[ "$(id -u)" -eq 0 ]]; then
    setup_user "$@"
fi

export PATH="/usr/local/bin/OpenMVS:${PATH}"

########################################
# Helper: run command only if marker missing
########################################
run_if_needed() {
    local marker="$1"
    shift
    local force_var="$1"
    shift

    if [[ -n "${!force_var:-}" ]] || [[ ! -f "$marker" ]]; then
        log "Running: $*"
        "$@"
        if [[ -n "$marker" ]]; then
            touch "$marker"
        fi
    else
        log "Skipping (marker exists): $*"
    fi
}

########################################
# COLMAP pipeline
########################################
run_colmap_pipeline() {
    cd "$obj"
    mkdir -p colmap
    cd colmap

    # Feature extraction
    if [[ -n "${force_colmap_feature_extractor:-}" ]] || [[ ! -f "database.db" ]]; then
        log "=== COLMAP Feature Extraction ==="
        colmap feature_extractor \
            --image_path "$obj/images" \
            --database_path database.db \
            --FeatureExtraction.use_gpu=0 \
            ${COLMAP_ARGS:-} ${feature_extractor_ARGS:-}
    else
        log "=== COLMAP Feature Extraction: SKIPPED (database.db exists) ==="
    fi

    # Feature matching
    local matcher="${colmap_matcher:-vocab_tree}"
    if [[ -n "${force_colmap_matcher:-}" ]] || [[ ! -f ".matches-done" ]]; then
        log "=== COLMAP Feature Matching ($matcher) ==="
        colmap "${matcher}_matcher" \
            --database_path database.db \
            --FeatureMatching.use_gpu=0 \
            ${COLMAP_ARGS:-} ${matcher_ARGS:-}
        touch .matches-done
    else
        log "=== COLMAP Feature Matching: SKIPPED ==="
    fi

    # Mapping (global_mapper via glomap or standard mapper)
    if [[ -n "${force_colmap_mapper:-}" ]] || [[ ! -d "sparse/0" ]]; then
        mkdir -p sparse
        if [[ "${USE_GLOMAP:-yes}" == "yes" ]]; then
            log "=== COLMAP Global Mapper (glomap) ==="
            colmap global_mapper \
                --image_path "$obj/images" \
                --database_path database.db \
                --output_path sparse \
                --GlobalMapper.gp_use_gpu=0 \
                ${GLOMAP_ARGS:-} ${glomap_mapper_ARGS:-} ${mapper_ARGS:-}
        else
            log "=== COLMAP Mapper ==="
            colmap mapper \
                --image_path "$obj/images" \
                --database_path database.db \
                --output_path sparse \
                ${COLMAP_ARGS:-} ${colmap_mapper_ARGS:-} ${mapper_ARGS:-}
        fi
    else
        log "=== COLMAP Mapping: SKIPPED (sparse/0 exists) ==="
    fi

    # Image undistortion
    if [[ ! -d "dense" ]] || [[ -n "${force_colmap:-}" ]]; then
        log "=== COLMAP Image Undistortion ==="
        mkdir -p dense
        colmap image_undistorter \
            --image_path "$obj/images" \
            --input_path sparse/0 \
            --output_path dense \
            --output_type COLMAP \
            --max_image_size 4096 \
            ${COLMAP_ARGS:-} ${image_undistorter_ARGS:-}
    else
        log "=== COLMAP Image Undistortion: SKIPPED (dense/ exists) ==="
    fi
}

########################################
# OpenMVS pipeline
########################################
run_openmvs_pipeline() {
    cd "$obj"
    mkdir -p openmvs
    cd openmvs

    # Export scene from COLMAP
    run_if_needed "" "force_openmvs_scene" \
        InterfaceCOLMAP -i "$obj/colmap/dense" -o scene.mvs \
            ${OPENMVS_ARGS:-} ${InterfaceCOLMAP_ARGS:-}

    # --- Sparse mesh ---
    run_if_needed "scene_mesh.ply" "force_openmvs_scene_mesh" \
        ReconstructMesh scene.mvs \
            ${OPENMVS_ARGS:-} ${ReconstructMesh_ARGS:-} ${ReconstructMesh_SPARSE_ARGS:-}

    # Optional pause for manual editing
    if [[ -n "${PAUSE:-}" ]] || [[ -n "${PAUSE_BEFORE_REFINE:-}" ]]; then
        log "OpenMVS sparse mesh ready. Edit scene_mesh.ply, then press any key to continue..."
        read -r -n 1 -s
    fi

    run_if_needed "scene_mesh_refined.ply" "force_openmvs_scene_mesh_refined" \
        RefineMesh -i scene.mvs -m scene_mesh.ply -o scene_mesh_refined.ply \
            ${OPENMVS_ARGS:-} ${RefineMesh_ARGS:-} ${RefineMesh_SPARSE_ARGS:-}

    run_if_needed "scene_mesh_refined_textured.ply" "force_openmvs_scene_mesh_refined_textured" \
        TextureMesh -i scene.mvs -m scene_mesh_refined.ply -o scene_mesh_refined_textured.obj \
            ${OPENMVS_ARGS:-} ${TextureMesh_ARGS:-} ${TextureMesh_SPARSE_ARGS:-}

    # --- Dense mesh ---
    run_if_needed "scene_dense.mvs" "force_openmvs_scene_dense" \
        DensifyPointCloud scene.mvs \
            ${OPENMVS_ARGS:-} ${DensifyPointCloud_ARGS:-}

    run_if_needed "scene_dense_mesh.ply" "force_openmvs_scene_dense_mesh" \
        ReconstructMesh scene_dense.mvs \
            ${OPENMVS_ARGS:-} ${ReconstructMesh_ARGS:-} ${ReconstructMesh_DENSE_ARGS:-}

    # Optional pause for manual editing
    if [[ -n "${PAUSE:-}" ]] || [[ -n "${PAUSE_BEFORE_REFINE_DENSE:-}" ]]; then
        log "OpenMVS dense mesh ready. Edit scene_dense_mesh.ply, then press any key to continue..."
        read -r -n 1 -s
    fi

    run_if_needed "scene_dense_mesh_refined.ply" "force_openmvs_scene_dense_mesh_refined" \
        RefineMesh -i scene_dense.mvs -m scene_dense_mesh.ply -o scene_dense_mesh_refined.ply \
            ${OPENMVS_ARGS:-} ${RefineMesh_ARGS:-} ${RefineMesh_DENSE_ARGS:-}

    run_if_needed "scene_dense_mesh_refined_textured.ply" "force_openmvs_scene_dense_mesh_refined_textured" \
        TextureMesh -i scene_dense.mvs -m scene_dense_mesh_refined.ply -o scene_dense_mesh_refined_textured.obj \
            ${OPENMVS_ARGS:-} ${TextureMesh_ARGS:-} ${TextureMesh_DENSE_ARGS:-}
}

########################################
# Main execution
########################################
log "=== Starting COLMAP Pipeline ==="
run_colmap_pipeline

log "=== Starting OpenMVS Pipeline ==="
run_openmvs_pipeline

log "=== Pipeline completed successfully! ==="
