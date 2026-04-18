# syntax=docker/dockerfile:1.23

###############################################################################
# Build arguments
###############################################################################
ARG BASE_IMAGE=set-BASE_IMAGE-to-nvidia-cuda-devel-with-ubuntu-base-or-simply-ubuntu-for-cpu-mode
ARG RUNTIME_IMAGE=set-RUNTIME_IMAGE-to-nvidia-cuda-runtime-with-ubuntu-base-or-simply-ubuntu-for-cpu-mode
ARG CUDA_ARCHITECTURES=native
ARG BUILD_TYPE=Release # Debug or Release

# Internal
ARG VCPKG_ROOT=/opt/vcpkg

###############################################################################
# Stage 1: Builder
###############################################################################
FROM ${BASE_IMAGE} AS builder
ARG BASE_IMAGE
ARG CUDA_ARCHITECTURES
ARG VCPKG_ROOT
ARG BUILD_TYPE

WORKDIR /build

ENV VCPKG_DEFAULT_BINARY_CACHE=${VCPKG_ROOT}/cache/vcpkg-binary \
    CCACHE_DIR=${VCPKG_ROOT}/cache/ccache

###############################################################################
# System dependencies (APT cached)
###############################################################################
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux; rm -f /etc/apt/apt.conf.d/docker-clean; \
    APT_CMD="apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gfortran \
        nasm \
        ccache \
        cmake \
        ninja-build \
        autoconf autoconf-archive automake libtool \
        pkg-config \
        python3 \
        git curl ca-certificates \
        zip unzip tar \
        libglu1-mesa-dev \
        bison \
        libx11-dev libxft-dev libxext-dev \
        libltdl-dev \
        python3-venv \
        libxi-dev libxtst-dev \
        libxinerama-dev libxcursor-dev xorg-dev \
        libxrandr-dev"; \
    for attempt in 1 2 3; do sh -c "$APT_CMD" && break || ([ $attempt -lt 3 ] && sleep 5); done

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
    TRIPLET="$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')-linux$(if [ "$BUILD_TYPE" = "Release" ]; then echo "-release"; fi)"; \
    CC_ARCH="$(uname -m | sed 's/x86_64/x86-64/;s/aarch64/armv8-a/')"; \
    EXTRA_FLAGS=''; \
    if [ "$BUILD_TYPE" = "Debug" ]; then \
        EXTRA_FLAGS='-g -fno-omit-frame-pointer -fno-inline'; \
    fi; \
    if [ "$(uname -m)" = "aarch64" ]; then \
        export COLMAP_CMAKE_CONFIGURE_OPTIONS="-DONNX_ENABLED=OFF"; \
    fi; \
    mkdir -p ${VCPKG_DEFAULT_BINARY_CACHE}; \
    FAISS_DEP='"faiss"'; \
    if echo "$BASE_IMAGE" | grep -q cuda; then \
        FAISS_DEP='{"name": "faiss", "features": ["gpu"]}'; \
    fi; \
    sed -i -e "s|\"dependencies\": \[|\"dependencies\": [${FAISS_DEP}, |" colmap/vcpkg.json; \
    sed -i -e "s|if(IPO_ENABLED AND NOT IS_DEBUG AND NOT IS_GNU)|if(IPO_ENABLED AND NOT IS_DEBUG)|" colmap/CMakeLists.txt; \
    ccache --show-stats --verbose; ccache --zero-stats; \
    cmake -S colmap -B colmap/mybuild -G Ninja \
        -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
        -DCMAKE_TOOLCHAIN_FILE=${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake \
        -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
        -DPKG_CONFIG_EXECUTABLE=/usr/bin/pkg-config \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CUDA_COMPILER_LAUNCHER=ccache \
        -DCMAKE_C_FLAGS="${EXTRA_FLAGS}" \
        -DCMAKE_CXX_FLAGS="${EXTRA_FLAGS}" \
        -DVCPKG_TARGET_TRIPLET=${TRIPLET} \
        -DCUDA_ENABLED=$(if echo "$BASE_IMAGE" | grep -q cuda; then echo "ON"; else echo "OFF"; fi) \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES} \
        -DFETCH_FAISS=OFF \
        -DGUI_ENABLED=OFF \
        -DTESTS_ENABLED=OFF \
        ${COLMAP_CMAKE_CONFIGURE_OPTIONS:-}; \
    cmake --build colmap/mybuild -j$(nproc); \
    cmake --install colmap/mybuild --prefix /build/install; \
    ccache --show-stats --verbose; \
    rm -r "colmap/mybuild/vcpkg_installed" # Smaller caches

###############################################################################
# Build OpenMVS
###############################################################################
COPY openMVS openMVS
RUN --mount=type=cache,target=/opt/vcpkg/cache,sharing=locked \
    --mount=type=cache,target=/build/openMVS/mybuild,sharing=locked \
    set -eux; \
    TRIPLET="$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')-linux$(if [ "$BUILD_TYPE" = "Release" ]; then echo "-release"; fi)"; \
    CC_ARCH="$(uname -m | sed 's/x86_64/x86-64/;s/aarch64/armv8-a/')"; \
    EXTRA_FLAGS=''; \
    IPO_FLAG=ON; \
    if [ "$BUILD_TYPE" = "Debug" ]; then \
        EXTRA_FLAGS='-g -fno-omit-frame-pointer -fno-inline'; \
        IPO_FLAG=OFF; \
    fi; \
    rm -r "/build/openMVS/mybuild/vcpkg_installed/$TRIPLET/tools/pkgconf" || true; \
    ccache --show-stats --verbose; ccache --zero-stats; \
    cmake -S openMVS -B openMVS/mybuild -G Ninja \
        -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
        -DCMAKE_TOOLCHAIN_FILE=${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake \
        -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
        -DPKG_CONFIG_EXECUTABLE=/usr/bin/pkg-config \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CUDA_COMPILER_LAUNCHER=ccache \
        -DCMAKE_C_FLAGS="${EXTRA_FLAGS}" \
        -DCMAKE_CXX_FLAGS="${EXTRA_FLAGS}" \
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=${IPO_FLAG} \
        -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON \
        -DVCPKG_TARGET_TRIPLET=${TRIPLET} \
        -DOpenMVS_USE_CUDA=$(if echo "$BASE_IMAGE" | grep -q cuda; then echo "ON"; else echo "OFF"; fi) \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES} \
        -DOpenMVS_USE_PYTHON=OFF \
        -DOpenMVS_BUILD_VIEWER=OFF \
        -DOpenMVS_ENABLE_TESTS=OFF \
        -DOpenMVS_USE_BREAKPAD=OFF; \
    cmake --build openMVS/mybuild -j$(nproc); \
    cmake --install openMVS/mybuild --prefix /build/install; \
    cp -r /usr/local/bin/OpenMVS /build/install/bin/OpenMVS; \
    ccache --show-stats --verbose; \
    rm -r "openMVS/mybuild/vcpkg_installed" # Smaller caches

###############################################################################
# Strip binaries only for release builds
###############################################################################
RUN set -eux; \
    if [ "$BUILD_TYPE" == "Release" ]; then \
        find /build/install -type f \( -name "*.so" -o -name "*.so.*" \) -exec strip --strip-unneeded {} + 2>/dev/null || true; \
        find /build/install/bin -type f -executable -exec strip --strip-all {} + 2>/dev/null || true; \
        find /build/install -name "*.a" -exec strip --strip-debug {} + 2>/dev/null || true; \
    fi

###############################################################################
# Stage 2: Runtime
###############################################################################
FROM ${RUNTIME_IMAGE} AS runtime
ARG BUILD_TYPE

ENV DEBIAN_FRONTEND=noninteractive \
    PATH=/usr/local/bin:/usr/local/bin/OpenMVS:$PATH \
    LD_LIBRARY_PATH=/usr/local/lib:/usr/local/cuda/compat

###############################################################################
# Runtime dependencies (APT cached)
###############################################################################
RUN set -eux; \
    DEBUG_RUNTIME_PACKAGES=""; \
    if [ "$BUILD_TYPE" = "Debug" ]; then \
        DEBUG_RUNTIME_PACKAGES="gdb binutils"; \
    fi; \
    APT_CMD="apt-get update && apt-get install -y --no-install-recommends \
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
        libgomp1 \
        ${DEBUG_RUNTIME_PACKAGES}" && \
    for attempt in 1 2 3; do sh -c "$APT_CMD" && break || ([ $attempt -lt 3 ] && sleep 5); done && \
    CURL_CMD="curl --fail -Lo /vocab_tree_faiss_flickr100K_words256K.bin 'https://github.com/colmap/colmap/releases/download/3.11.1/vocab_tree_faiss_flickr100K_words256K.bin'" && \
    for attempt in 1 2 3; do sh -c "$CURL_CMD" && break || ([ $attempt -lt 3 ] && sleep 5); done && \
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
