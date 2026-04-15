#!/usr/bin/env bash
DEPENDENCIES=("07_openmvs_sparse_refine")
INPUTS=("${WORK_DIR}/openmvs/scene.mvs" "${WORK_DIR}/openmvs/scene_mesh_refined.ply")
OUTPUTS=("${WORK_DIR}/openmvs/scene_mesh_refined_textured.ply")

run_stage_function() {
    cd "${WORK_DIR}/openmvs"
    TextureMesh -i scene.mvs -m scene_mesh_refined.ply -o scene_mesh_refined_textured.ply ${OPENMVS_TEXTURE_MESH_SPARSE_ARGS}
}
