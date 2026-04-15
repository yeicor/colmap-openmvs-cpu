#!/usr/bin/env bash
DEPENDENCIES=("05_openmvs_scene_export")
INPUTS=("${WORK_DIR}/openmvs/scene.mvs")
OUTPUTS=("${WORK_DIR}/openmvs/scene_dense.mvs")

run_stage_function() {
    cd "${WORK_DIR}/openmvs"
    DensifyPointCloud scene.mvs -o scene_dense.mvs ${OPENMVS_DENSIFY_POINT_CLOUD_ARGS}
}
