# syntax=docker/dockerfile:1.7-labs

ARG BASE_IMAGE=myorg/colmap-base:latest
FROM ${BASE_IMAGE} AS builder

ARG CUDA_ENABLED=0
ARG CUDA_ARCHITECTURES=all-major

ENV DEBIAN_FRONTEND=noninteractive

############################
# vcpkg config (OPTIMAL)
############################
ENV VCPKG_DEFAULT_TRIPLET=x64-linux
ENV VCPKG_INSTALLED_DIR=/build/vcpkg_installed
ENV VCPKG_BINARY_SOURCES="clear;files,/cache/vcpkg,readwrite"
ENV VCPKG_FEATURE_FLAGS="manifests,binarycaching"

############################
# sccache config (FIXED)
############################
#ENV SCCACHE_DIR=/cache/sccache
#ENV SCCACHE_CACHE_SIZE=50G
#ENV CMAKE_C_COMPILER_LAUNCHER=sccache
#ENV CMAKE_CXX_COMPILER_LAUNCHER=sccache

WORKDIR /build

########################################################
# 1. PRE-WARM vcpkg cache (CRITICAL FOR PERFORMANCE)
########################################################
COPY colmap/vcpkg.json colmap/vcpkg.json
COPY openMVS/vcpkg.json openMVS/vcpkg.json

RUN --mount=type=cache,target=/cache/vcpkg \
    --mount=type=cache,target=/cache/sccache \
    /usr/bin/env bash -c "${VCPKG_ROOT}/vcpkg install \
        --triplet x64-linux \
        --x-install-root=${VCPKG_INSTALLED_DIR} \
        $(jq -r '.dependencies[] | if type=="string" then . else .name + (if .features then "[" + (.features|join(",")) + "]" else "" end) end' colmap/vcpkg.json openMVS/vcpkg.json | sort | uniq | tr '\n' ' ')"

########################################################
# 2. COLMAP build (CMake drives vcpkg)
########################################################
COPY colmap colmap

RUN --mount=type=cache,target=/cache/vcpkg \
    --mount=type=cache,target=/cache/sccache \
    cmake -S colmap -B colmap/build \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake \
        -DVCPKG_TARGET_TRIPLET=x64-linux \
        -DVCPKG_INSTALLED_DIR=${VCPKG_INSTALLED_DIR} \
        -DGUI_ENABLED=OFF \
        -DCUDA_ENABLED=${CUDA_ENABLED} \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES} \
        -DTESTS_ENABLED=OFF \
    && cmake --build colmap/build -j$(nproc) \
    && cmake --install colmap/build

########################################################
# 3. OpenMVS build
########################################################
COPY openMVS openMVS

RUN --mount=type=cache,target=/cache/vcpkg \
    --mount=type=cache,target=/cache/sccache \
    cmake -S openMVS -B openMVS/build \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake \
        -DVCPKG_TARGET_TRIPLET=x64-linux \
        -DVCPKG_INSTALLED_DIR=${VCPKG_INSTALLED_DIR} \
        -DOpenMVS_USE_CUDA=${CUDA_ENABLED} \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES} \
        -DOpenMVS_USE_PYTHON=OFF \
    && cmake --build openMVS/build -j$(nproc) \
    && cmake --install openMVS/build

########################################################
# 4. runtime
########################################################
FROM ubuntu:24.04 AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
        libstdc++6 libgcc-s1 \
        libgl1 libglu1-mesa \
        libx11-6 libxext6 libxrender1 \
        libxi6 libxrandr2 libxcursor1 \
        libxinerama1 libxtst6 \
        libdbus-1-3 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local /usr/local
COPY --from=builder /build/vcpkg_installed /usr/local

RUN ldconfig

ENV PATH=/usr/local/bin/OpenMVS:$PATH

COPY entrypoint.sh entrypoint.sh
RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]
