#!/usr/bin/env bash
DEPENDENCIES=("11_openmvs_dense_refine")
INPUTS=("${WORK_DIR}/openmvs/scene_dense.mvs" "${WORK_DIR}/openmvs/scene_dense_mesh_refined.ply")
OUTPUTS=("${WORK_DIR}/openmvs/scene_dense_mesh_refined_textured.ply")

run_stage_function() {
    cd "${WORK_DIR}/openmvs"
    TextureMesh -i scene_dense.mvs -m scene_dense_mesh_refined.ply -o scene_dense_mesh_refined_textured.ply ${OPENMVS_TEXTURE_MESH_DENSE_ARGS}
}
