#!/usr/bin/env bash
DEPENDENCIES=()
INPUTS=("${IMAGES_DIR}")
OUTPUTS=("${WORK_DIR}/colmap/database.db")

run_stage_function() {
    cd "${WORK_DIR}"
    mkdir -p colmap && cd colmap
    colmap feature_extractor \
        --image_path "${IMAGES_DIR}" \
        --database_path database.db \
        ${COLMAP_FEATURE_EXTRACTOR_ARGS}
}
