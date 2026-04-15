#!/usr/bin/env bash
DEPENDENCIES=("09_openmvs_densify")
INPUTS=("${WORK_DIR}/openmvs/scene_dense.mvs")
OUTPUTS=("${WORK_DIR}/openmvs/scene_dense_mesh.ply")

run_stage_function() {
    cd "${WORK_DIR}/openmvs"
    ReconstructMesh scene_dense.mvs -o scene_dense_mesh.ply ${OPENMVS_RECONSTRUCT_MESH_DENSE_ARGS}
}
