#!/usr/bin/env bash
DEPENDENCIES=("03_colmap_mapping")
INPUTS=("${WORK_DIR}/colmap/sparse/0/cameras.bin")
OUTPUTS=("${WORK_DIR}/colmap/dense/images")

run_stage_function() {
    cd "${WORK_DIR}/colmap"
    mkdir -p dense
    colmap image_undistorter \
        --image_path "${IMAGES_DIR}" \
        --input_path sparse/0 \
        --output_path dense \
        --output_type COLMAP \
        ${COLMAP_UNDISTORTER_ARGS}
}
