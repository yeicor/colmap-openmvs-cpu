#!/usr/bin/env bash
DEPENDENCIES=("06_openmvs_sparse_mesh")
INPUTS=("${WORK_DIR}/openmvs/scene.mvs" "${WORK_DIR}/openmvs/scene_mesh.ply")
OUTPUTS=("${WORK_DIR}/openmvs/scene_mesh_refined.ply")

run_stage_function() {
    cd "${WORK_DIR}/openmvs"
    RefineMesh -i scene.mvs -m scene_mesh.ply -o scene_mesh_refined.ply ${OPENMVS_REFINE_MESH_SPARSE_ARGS}
}
