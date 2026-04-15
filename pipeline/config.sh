#!/usr/bin/env bash
################################################################################
# Pipeline Configuration - Tool Arguments Only
#
# Customize via environment variables:
#   COLMAP_FEATURE_EXTRACTOR_ARGS="--SiftExtraction.num_threads 8"
#   COLMAP_MATCHER="exhaustive_matcher"
#   COLMAP_MATCHER_ARGS="--ExhaustiveMatching.num_threads 8"
#   COLMAP_MAPPER="sequential_mapper"
#   COLMAP_MAPPER_ARGS="--Mapper.num_threads 8"
#
# Example:
#   COLMAP_MATCHER=exhaustive_matcher COLMAP_MAPPER=sequential_mapper entrypoint /data
#
################################################################################

# COLMAP Feature Extractor
export COLMAP_FEATURE_EXTRACTOR_ARGS="${COLMAP_FEATURE_EXTRACTOR_ARGS:-}"

# COLMAP Feature Matching - choose matcher
# Options: vocab_tree_matcher (default), exhaustive_matcher, spatial_matcher, sequential_matcher
export COLMAP_MATCHER="${COLMAP_MATCHER:-vocab_tree_matcher}"
export COLMAP_MATCHER_ARGS="${COLMAP_MATCHER_ARGS:-}"

# COLMAP Mapper - choose mapper
# Options: global_mapper (default), sequential_mapper
export COLMAP_MAPPER="${COLMAP_MAPPER:-global_mapper}"
export COLMAP_MAPPER_ARGS="${COLMAP_MAPPER_ARGS:-}"

# COLMAP Image Undistorter
export COLMAP_UNDISTORTER_ARGS="${COLMAP_UNDISTORTER_ARGS:-}"

# OpenMVS InterfaceCOLMAP
export OPENMVS_INTERFACE_COLMAP_ARGS="${OPENMVS_INTERFACE_COLMAP_ARGS:-}"

# OpenMVS ReconstructMesh (sparse)
export OPENMVS_RECONSTRUCT_MESH_SPARSE_ARGS="${OPENMVS_RECONSTRUCT_MESH_SPARSE_ARGS:-}"

# OpenMVS RefineMesh (sparse)
export OPENMVS_REFINE_MESH_SPARSE_ARGS="${OPENMVS_REFINE_MESH_SPARSE_ARGS:-}"

# OpenMVS TextureMesh (sparse)
export OPENMVS_TEXTURE_MESH_SPARSE_ARGS="${OPENMVS_TEXTURE_MESH_SPARSE_ARGS:-}"

# OpenMVS DensifyPointCloud
export OPENMVS_DENSIFY_POINT_CLOUD_ARGS="${OPENMVS_DENSIFY_POINT_CLOUD_ARGS:-}"

# OpenMVS ReconstructMesh (dense)
export OPENMVS_RECONSTRUCT_MESH_DENSE_ARGS="${OPENMVS_RECONSTRUCT_MESH_DENSE_ARGS:-}"

# OpenMVS RefineMesh (dense)
export OPENMVS_REFINE_MESH_DENSE_ARGS="${OPENMVS_REFINE_MESH_DENSE_ARGS:-}"

# OpenMVS TextureMesh (dense)
export OPENMVS_TEXTURE_MESH_DENSE_ARGS="${OPENMVS_TEXTURE_MESH_DENSE_ARGS:-}"
