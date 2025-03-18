#!/usr/bin/env bash

cd "$(dirname $(realpath $0))"
set -ex

export obj="$1"
if [ -z "$obj" ]; then
    echo "missing obj folder as the first argument. Should point to a folder with an images/ subfolder"
    exit 1
fi

cd "$obj"
mkdir -p colmap
pushd colmap
if [ ! -d "colmap/dense/0" ] || [ ! -z "$force_colmap" ]; then
    colmap automatic_reconstructor --image_path ../images --workspace_path . --quality extreme --camera_model OPENCV --single_camera=1 --use_gpu=0 || true
    if [ ! -d "colmap/dense/0" ]; then
        echo "Colmap failed to create at least one dense reconstruction folder"
        exit 1
    fi
fi
popd

mkdir -p openmvs
pushd openmvs
if [ ! -f "openmvs/scene_mesh.ply" ] || [ ! -z "$force_openmvs_scene_mesh" ]; then
    InterfaceCOLMAP -i ../colmap/dense/0 -o scene.mvs && ReconstructMesh scene.mvs
fi

# Optional manual crop step (open scene_mesh.ply in blender and remove out-of-bounds triangles)

if [ ! -f "openmvs/scene_mesh_refined_textured.ply" ] || [ ! -z "$force_openmvs_scene_mesh_refined_textured" ]; then
    RefineMesh -i scene.mvs -m scene_mesh.ply -o scene_mesh_refined.ply && TextureMesh -i scene.mvs -m scene_mesh_refined.ply -o scene_mesh_refined_textured.obj
fi
    
if [ ! -f "openmvs/scene_dense_mesh.ply" ] || [ ! -z "$force_openmvs_scene_dense_mesh" ]; then
    DensifyPointCloud scene.mvs && ReconstructMesh scene_dense.mvs
fi

# Optional manual crop step (open scene_dense_mesh.ply in blender and remove out-of-bounds triangles)

if [ ! -f "openmvs/scene_dense_mesh_refined.ply" ] || [ ! -z "$force_openmvs_scene_dense_mesh_refined" ]; then
    RefineMesh -i scene_dense.mvs -m scene_dense_mesh.ply -o scene_dense_mesh_refined.ply && TextureMesh -i scene_dense.mvs -m scene_dense_mesh_refined.ply -o scene_dense_mesh_refined_textured.obj
fi
popd

echo "Finished succesfully!"

