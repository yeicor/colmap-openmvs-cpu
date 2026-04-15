#!/usr/bin/env bash
DEPENDENCIES=("02_colmap_feature_matching")
INPUTS=("${WORK_DIR}/colmap/database.db" "${WORK_DIR}/colmap/database.db.matches")
OUTPUTS=("${WORK_DIR}/colmap/sparse/0/cameras.bin")

run_stage_function() {
    cd "${WORK_DIR}/colmap"
    mkdir -p sparse
    colmap ${COLMAP_MAPPER} \
        --image_path "${IMAGES_DIR}" \
        --database_path database.db \
        --output_path sparse \
        ${COLMAP_MAPPER_ARGS}
}
