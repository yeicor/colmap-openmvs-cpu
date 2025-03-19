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
if [ ! -d "sparse" ] || [ ! -z "$force_colmap" ]; then
    colmap automatic_reconstructor --image_path ../images --workspace_path . --quality extreme --camera_model OPENCV --single_camera=1 --use_gpu=0 $COLMAP_ARGS || echo "Colmap exited with non-zero code $? (this is probably expected)"
    if [ ! -d "sparse" ]; then
        echo "Colmap failed to create at least one sparse reconstruction folder"
        exit 1
    fi
    if [ -d "sparse/0" ]; then
        cp "sparse/0/"* "sparse"
    fi
fi
popd

mkdir -p openmvs
pushd openmvs
if [ ! -f "scene_mesh.ply" ] || [ ! -z "$force_openmvs_scene_mesh" ]; then
    InterfaceCOLMAP -i ../colmap -o scene.mvs $OPENMVS_ARGS $InterfaceCOLMAP_ARGS
    ReconstructMesh scene.mvs $OPENMVS_ARGS $ReconstructMesh_ARGS
fi

# Optional manual crop step (open scene_mesh.ply in blender and remove out-of-bounds triangles)

if [ ! -f "scene_mesh_refined_textured.ply" ] || [ ! -z "$force_openmvs_scene_mesh_refined_textured" ]; then
    RefineMesh -i scene.mvs -m scene_mesh.ply -o scene_mesh_refined.ply $OPENMVS_ARGS $RefineMesh_ARGS
    TextureMesh -i scene.mvs -m scene_mesh_refined.ply -o scene_mesh_refined_textured.obj $OPENMVS_ARGS $TextureMesh_ARGS
fi
    
if [ ! -f "scene_dense_mesh.ply" ] || [ ! -z "$force_openmvs_scene_dense_mesh" ]; then
    DensifyPointCloud scene.mvs $OPENMVS_ARGS $DensifyPointCloud_ARGS
    ReconstructMesh scene_dense.mvs $OPENMVS_ARGS $ReconstructMesh_DENSE_ARGS
fi

# Optional manual crop step (open scene_dense_mesh.ply in blender and remove out-of-bounds triangles)

if [ ! -f "scene_dense_mesh_refined.ply" ] || [ ! -z "$force_openmvs_scene_dense_mesh_refined" ]; then
    RefineMesh -i scene_dense.mvs -m scene_dense_mesh.ply -o scene_dense_mesh_refined.ply $OPENMVS_ARGS $RefineMesh_DENSE_ARGS
    TextureMesh -i scene_dense.mvs -m scene_dense_mesh_refined.ply -o scene_dense_mesh_refined_textured.obj $OPENMVS_ARGS $TextureMesh_DENSE_ARGS
fi
popd

echo "Finished succesfully!"

