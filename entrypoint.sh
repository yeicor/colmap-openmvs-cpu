#!/usr/bin/env bash

cd "$(dirname $(realpath $0))"
set -ex

# === INPUTS ===
export obj="$1"
if [ -z "$obj" ]; then
    echo "Missing obj folder as the first argument. Should point to a folder with an images/ subfolder"
    exit 1
fi

# === USER AND PERMISSIONS ===
export PUID="${PUID:-1000}"
export PGID="${PGID:-${PUID}}"
if [[ "$(id -u)" != "$PUID" ]] || [[ "$(id -g)" != "$PGID" ]]; then
    echo "Running as user $PUID:$PGID..."
    groupadd -g "$PGID" "${GROUPNAME:-containergroup}" || true
    useradd -m -u "${PUID}" -g "${PGID}" "${USERNAME:-containeruser}" || true
    chown -R "${PUID}:${PGID}" "$obj"
    exec su - "${USERNAME:-containeruser}" -c "$0 $@"
fi
export PATH="/usr/local/bin/OpenMVS:$PATH"

# === COLMAP ===

cd "$obj"
mkdir -p colmap
pushd colmap
if [ ! -z "$force_colmap_feature_extractor" ] || [ ! -f "database.db" ]; then
  # Recommended if possible: --ImageReader.single_camera=1 --ImageReader.camera_model=OPENCV
  colmap feature_extractor  --image_path ../images --database_path database.db --FeatureExtraction.use_gpu=0 $COLMAP_ARGS $feature_extractor_ARGS
fi

if [ ! -z "$force_colmap_matcher" ] || [ ! -f ".matches-done" ]; then
  colmap_matcher="${colmap_matcher:-vocab_tree}" # exhaustive, sequential, vocab_tree...
  colmap ${colmap_matcher}_matcher --database_path database.db --FeatureMatching.use_gpu=0 $COLMAP_ARGS $matcher_ARGS
  touch .matches-done
fi

if [ ! -z "$force_colmap_mapper" ] || [ ! -d "sparse/0" ]; then
  if [[ "${USE_GLOMAP:-yes}" == "yes" ]]; then
      glomap mapper --image_path ../images --database_path database.db --output_path sparse --GlobalPositioning.use_gpu=0 --BundleAdjustment.use_gpu=0 $GLOMAP_ARGS $glomap_mapper_ARGS $mapper_ARGS
  else # Use colmap's slower built-in mapper instead
      colmap mapper --image_path ../images --database_path database.db --output_path sparse $COLMAP_ARGS $colmap_mapper_ARGS $mapper_ARGS
  fi
fi

if [ ! -d "dense" ] || [ ! -z "$force_colmap" ]; then
    mkdir dense
    colmap image_undistorter --image_path ../images --input_path sparse/0 --output_path dense --output_type COLMAP --max_image_size 4096 $COLMAP_ARGS $image_undistorter_ARGS
fi
popd

# === OPENMVS ===

mkdir -p openmvs
pushd openmvs
if [ ! -f "scene.mvs" ] || [ ! -z "$force_openmvs_scene" ]; then
    InterfaceCOLMAP -i ../colmap/dense -o scene.mvs $OPENMVS_ARGS $InterfaceCOLMAP_ARGS
fi
if [ ! -f "scene_mesh.ply" ] || [ ! -z "$force_openmvs_scene_mesh" ]; then
    ReconstructMesh scene.mvs $OPENMVS_ARGS $ReconstructMesh_ARGS $ReconstructMesh_SPARSE_ARGS
fi

# Optional manual crop step (open scene_mesh.ply in blender and remove out-of-bounds triangles)
if [ ! -z "$PAUSE" ] || [ ! -z "$PAUSE_BEFORE_REFINE" ]; then
    echo "OpenMVS mesh is ready, you can now open scene_mesh.ply in blender and remove out-of-bounds triangles. Press any key to continue..."
    read -n 1 -s
fi

if [ ! -f "scene_mesh_refined.ply" ] || [ ! -z "$force_openmvs_scene_mesh_refined" ]; then
    RefineMesh -i scene.mvs -m scene_mesh.ply -o scene_mesh_refined.ply $OPENMVS_ARGS $RefineMesh_ARGS $RefineMesh_SPARSE_ARGS
fi
if [ ! -f "scene_mesh_refined_textured.ply" ] || [ ! -z "$force_openmvs_scene_mesh_refined_textured" ]; then
    TextureMesh -i scene.mvs -m scene_mesh_refined.ply -o scene_mesh_refined_textured.obj $OPENMVS_ARGS $TextureMesh_ARGS $TextureMesh_SPARSE_ARGS
fi
    
if [ ! -f "scene_dense.mvs" ] || [ ! -z "$force_openmvs_scene_dense" ]; then
    DensifyPointCloud scene.mvs $OPENMVS_ARGS $DensifyPointCloud_ARGS
fi
if [ ! -f "scene_dense_mesh.ply" ] || [ ! -z "$force_openmvs_scene_dense_mesh" ]; then
    ReconstructMesh scene_dense.mvs $OPENMVS_ARGS $ReconstructMesh_ARGS $ReconstructMesh_DENSE_ARGS
fi

# Optional manual crop step (open scene_dense_mesh.ply in blender and remove out-of-bounds triangles)
if [ ! -z "$PAUSE" ] || [ ! -z "$PAUSE_BEFORE_REFINE_DENSE" ]; then
    echo "OpenMVS dense mesh is ready, you can now open scene_dense_mesh.ply in blender and remove out-of-bounds triangles. Press any key to continue..."
    read -n 1 -s
fi

if [ ! -f "scene_dense_mesh_refined.ply" ] || [ ! -z "$force_openmvs_scene_dense_mesh_refined" ]; then
    RefineMesh -i scene_dense.mvs -m scene_dense_mesh.ply -o scene_dense_mesh_refined.ply $OPENMVS_ARGS $RefineMesh_ARGS $RefineMesh_DENSE_ARGS
fi
if [ ! -f "scene_dense_mesh_refined_textured.ply" ] || [ ! -z "$force_openmvs_scene_dense_mesh_refined_textured" ]; then
    TextureMesh -i scene_dense.mvs -m scene_dense_mesh_refined.ply -o scene_dense_mesh_refined_textured.obj $OPENMVS_ARGS $TextureMesh_ARGS $TextureMesh_DENSE_ARGS
fi
popd

echo "Finished succesfully!"

