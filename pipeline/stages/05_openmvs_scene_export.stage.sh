#!/usr/bin/env bash
DEPENDENCIES=("04_colmap_undistortion")
INPUTS=("${WORK_DIR}/colmap/dense")
OUTPUTS=("${WORK_DIR}/openmvs/scene.mvs")

run_stage_function() {
    cd "${WORK_DIR}"
    mkdir -p openmvs && cd openmvs
    InterfaceCOLMAP \
        -i "${WORK_DIR}/colmap/dense" \
        -o scene.mvs \
        ${OPENMVS_INTERFACE_COLMAP_ARGS}
}
