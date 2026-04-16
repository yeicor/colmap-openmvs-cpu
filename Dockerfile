# syntax=docker/dockerfile:1.12

###############################################################################
# Build arguments
###############################################################################
ARG BASE_IMAGE=nvidia/cuda:13.1.1-devel-ubuntu24.04
ARG RUNTIME_IMAGE=nvidia/cuda:13.1.1-runtime-ubuntu24.04
ARG CUDA_ENABLED=ON
ARG CUDA_ARCHITECTURES=native

# Internal
ARG VCPKG_ROOT=/opt/vcpkg

###############################################################################
# Stage 1: Builder
###############################################################################
FROM ${BASE_IMAGE} AS builder
ARG CUDA_ENABLED
ARG CUDA_ARCHITECTURES
ARG VCPKG_ROOT

WORKDIR /build

ENV VCPKG_DEFAULT_BINARY_CACHE=${VCPKG_ROOT}/cache/vcpkg-binary

###############################################################################
# System dependencies (APT cached)
###############################################################################
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gfortran \
        cmake \
        ninja-build \
        autoconf autoconf-archive automake libtool \
        pkg-config \
        python3 \
        git curl ca-certificates\
        zip unzip tar \
        libglu1-mesa-dev \
        bison \
        libx11-dev libxft-dev libxext-dev \
        libltdl-dev \
        python3-venv \
        libxi-dev libxtst-dev \
        libxrandr-dev

###############################################################################
# vcpkg (stable layer)
###############################################################################
COPY vcpkg ${VCPKG_ROOT}
RUN cd ${VCPKG_ROOT} && ./bootstrap-vcpkg.sh -disableMetrics && rm -rf .git

###############################################################################
# Build COLMAP
###############################################################################
COPY colmap colmap
RUN --mount=type=cache,target=/opt/vcpkg/cache,sharing=locked \
    --mount=type=cache,target=/build/colmap/mybuild,sharing=locked \
    set -eux; \
    TRIPLET="$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')-linux-release"; \
    if [ "$(uname -m)" = "aarch64" ]; then \
        export COLMAP_CMAKE_CONFIGURE_OPTIONS="-DONNX_ENABLED=OFF"; \
    fi; \
    mkdir -p ${VCPKG_DEFAULT_BINARY_CACHE}; \
    cmake -S colmap -B colmap/mybuild -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake \
        -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
        -DPKG_CONFIG_EXECUTABLE=/usr/bin/pkg-config \
        -DVCPKG_TARGET_TRIPLET=${TRIPLET} \
        -DGUI_ENABLED=OFF \
        -DCUDA_ENABLED=${CUDA_ENABLED} \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES} \
        -DTESTS_ENABLED=OFF \
        ${COLMAP_CMAKE_CONFIGURE_OPTIONS:-}; \
    cmake --build colmap/mybuild -j$(nproc); \
    cmake --install colmap/mybuild --prefix /build/install

###############################################################################
# Build OpenMVS
###############################################################################
COPY openMVS openMVS
RUN --mount=type=cache,target=/opt/vcpkg/cache,sharing=locked \
    --mount=type=cache,target=/build/openMVS/mybuild,sharing=locked \
    set -eux; \
    TRIPLET="$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')-linux-release"; \
    rm -r "/build/openMVS/mybuild/vcpkg_installed/$TRIPLET/tools/pkgconf" || true; \
    cmake -S openMVS -B openMVS/mybuild -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake \
        -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
        -DPKG_CONFIG_EXECUTABLE=/usr/bin/pkg-config \
        -DVCPKG_TARGET_TRIPLET=${TRIPLET} \
        -DOpenMVS_USE_CUDA=${CUDA_ENABLED} \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES} \
        -DOpenMVS_USE_PYTHON=OFF \
        -DOpenMVS_BUILD_VIEWER=OFF \
        -DOpenMVS_ENABLE_TESTS=OFF \
        -DOpenMVS_USE_BREAKPAD=OFF; \
    cmake --build openMVS/mybuild -j$(nproc); \
    cmake --install openMVS/mybuild --prefix /build/install; \
    cp -r /usr/local/bin/OpenMVS /build/install/bin/OpenMVS

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
    LD_LIBRARY_PATH=/usr/local/lib:/usr/local/cuda-13.1/compat/

###############################################################################
# Runtime dependencies (APT cached)
###############################################################################
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libstdc++6 libgcc-s1 libgfortran5 \
        curl ca-certificates \
        libglu1-mesa \
        libx11-6 \
        libxft2 \
        libxext6 \
        libltdl7 \
        libxi6 \
        libxtst6 \
        libxrandr2 \
        libglx-mesa0 \
        libgl1 \
        libgl1-mesa-dri \
        libgomp1 && \
    curl -Lo /vocab_tree_faiss_flickr100K_words256K.bin "https://github.com/colmap/colmap/releases/download/3.11.1/vocab_tree_faiss_flickr100K_words256K.bin" && \
    rm -rf /var/lib/apt/lists/*

###############################################################################
# Copy build artifacts
###############################################################################
COPY --from=builder /build/install/bin /usr/local/bin
COPY --from=builder /build/install/lib /usr/local/lib

###############################################################################
# Entrypoint
###############################################################################
COPY entrypoint.sh /entrypoint.sh
COPY pipeline /pipeline

LABEL org.opencontainers.image.title="colmap-openmvs" \
      org.opencontainers.image.description="COLMAP + OpenMVS: SfM and MVS pipeline" \
      org.opencontainers.image.vendor="COLMAP+OpenMVS" \
      org.opencontainers.image.source="https://github.com/yeicor/colmap-openmvs"

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
CMD ["--help"]
