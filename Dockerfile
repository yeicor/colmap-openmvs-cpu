# syntax=docker/dockerfile:1.12

###############################################################################
# Build arguments
###############################################################################
ARG BASE_IMAGE=nvidia/cuda:12.9.1-devel-ubuntu22.04
ARG RUNTIME_IMAGE=nvidia/cuda:12.9.1-runtime-ubuntu22.04
ARG CUDA_ENABLED=ON
ARG CUDA_ARCHITECTURES=all-major

# Internal
ARG VCPKG_INSTALLED_DIR=/build/vcpkg_installed

###############################################################################
# Stage 1: Builder
###############################################################################
FROM ${BASE_IMAGE} AS builder

WORKDIR /build

ENV DEBIAN_FRONTEND=noninteractive \
    VCPKG_ROOT=/opt/vcpkg \
    VCPKG_DEFAULT_BINARY_CACHE=/cache/vcpkg-binary \
    VCPKG_BINARY_SOURCES="clear;files,/cache/vcpkg-binary,readwrite"

###############################################################################
# System dependencies (APT cached)
###############################################################################
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake ninja-build git curl zip unzip tar \
        pkg-config python3 python3-venv gfortran \
        autoconf autoconf-archive automake bison libtool libltdl-dev nasm \
        libgl-dev libglu1-mesa-dev libxmu-dev libdbus-1-dev libxtst-dev \
        libxi-dev libxinerama-dev libxcursor-dev xorg-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*

###############################################################################
# vcpkg (stable layer)
###############################################################################
COPY vcpkg ${VCPKG_ROOT}
RUN cd ${VCPKG_ROOT} && ./bootstrap-vcpkg.sh -disableMetrics && rm -rf .git

###############################################################################
# Build COLMAP
###############################################################################
COPY colmap colmap
RUN --mount=type=cache,target=${VCPKG_DEFAULT_BINARY_CACHE},sharing=locked \
    --mount=type=cache,target=${VCPKG_INSTALLED_DIR},sharing=locked \
    --mount=type=cache,target=${VCPKG_ROOT}/downloads,sharing=locked \
    --mount=type=cache,target=${VCPKG_ROOT}/buildtrees,sharing=locked \
    --mount=type=cache,target=${VCPKG_ROOT}/packages,sharing=locked \
    set -eux; \
    TRIPLET="$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')-linux-release"; \
    if [ "$(uname -m)" = "aarch64" ]; then \
        export COLMAP_CMAKE_CONFIGURE_OPTIONS="-DONNX_ENABLED=OFF"; \
    fi; \
    cmake -S colmap -B colmap/build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake \
        -DVCPKG_TARGET_TRIPLET=${TRIPLET} \
        -DVCPKG_INSTALLED_DIR=${VCPKG_INSTALLED_DIR} \
        -DGUI_ENABLED=OFF \
        -DCUDA_ENABLED=${CUDA_ENABLED} \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES} \
        -DTESTS_ENABLED=OFF \
        ${COLMAP_CMAKE_CONFIGURE_OPTIONS:-}; \
    cmake --build colmap/build -j$(nproc); \
    cmake --install colmap/build --prefix /build/install

###############################################################################
# Build OpenMVS
###############################################################################
COPY openMVS openMVS
RUN --mount=type=cache,target=${VCPKG_DEFAULT_BINARY_CACHE},sharing=locked \
    --mount=type=cache,target=${VCPKG_INSTALLED_DIR},sharing=locked \
    --mount=type=cache,target=${VCPKG_ROOT}/downloads,sharing=locked \
    --mount=type=cache,target=${VCPKG_ROOT}/buildtrees,sharing=locked \
    --mount=type=cache,target=${VCPKG_ROOT}/packages,sharing=locked \
    set -eux; \
    TRIPLET="$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')-linux-release"; \
    cmake -S openMVS -B openMVS/build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake \
        -DVCPKG_TARGET_TRIPLET=${TRIPLET} \
        -DVCPKG_INSTALLED_DIR=${VCPKG_INSTALLED_DIR} \
        -DOpenMVS_USE_CUDA=${CUDA_ENABLED} \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES} \
        -DOpenMVS_USE_PYTHON=OFF \
        -DOpenMVS_BUILD_TOOLS=OFF \
        -DOpenMVS_BUILD_VIEWER=OFF \
        -DOpenMVS_USE_CERES=ON \
        -DOpenMVS_USE_BREAKPAD=OFF; \
    cmake --build openMVS/build -j$(nproc); \
    cmake --install openMVS/build --prefix /build/install

###############################################################################
# Strip binaries (smaller image)
###############################################################################
RUN find /build/install -type f \( -name "*.so" -o -name "*.so.*" \) -exec strip --strip-unneeded {} + 2>/dev/null || true \
    && find /build/install/bin -type f -executable -exec strip --strip-all {} + 2>/dev/null || true \
    && find /build/install -name "*.a" -exec strip --strip-debug {} + 2>/dev/null || true

###############################################################################
# Stage 2: Runtime
###############################################################################
FROM ${RUNTIME_IMAGE} AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
    PATH=/usr/local/bin:/usr/local/bin/OpenMVS:$PATH \
    LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu

###############################################################################
# Runtime dependencies (APT cached)
###############################################################################
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        libstdc++6 libgcc-s1 libgfortran5 ca-certificates \
        libgl1 libglu1-mesa libboost-dev \
        libx11-6 libxext6 libxrender1 \
        libxi6 libxrandr2 libxcursor1 \
        libxinerama1 libxtst6 libdbus-1-3 \
    && rm -rf /var/lib/apt/lists/* \
    && ldconfig

###############################################################################
# Copy build artifacts
###############################################################################
COPY --from=builder /build/install /usr/local
COPY --from=builder ${VCPKG_INSTALLED_DIR}/x64-linux/lib /usr/local/lib/
COPY --from=builder ${VCPKG_INSTALLED_DIR}/x64-linux/share /usr/local/share/
COPY --from=builder ${VCPKG_INSTALLED_DIR}/x64-linux/include /usr/local/include/

RUN ldconfig

###############################################################################
# Entrypoint
###############################################################################
COPY --chmod=755 entrypoint.sh /entrypoint.sh

LABEL org.opencontainers.image.title="colmap-openmvs" \
      org.opencontainers.image.description="COLMAP + OpenMVS: SfM and MVS pipeline" \
      org.opencontainers.image.vendor="COLMAP+OpenMVS" \
      org.opencontainers.image.source="https://github.com/yeicor/colmap-openmvs"

ENTRYPOINT ["/entrypoint.sh"]
CMD ["--help"]