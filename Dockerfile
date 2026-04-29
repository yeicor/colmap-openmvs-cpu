# syntax=docker/dockerfile:1.23

###############################################################################
# Build arguments
###############################################################################
ARG BASE_IMAGE=set-base-image-to-nvidia-cuda-devel-with-ubuntu-base-or-simply-ubuntu-for-cpu-mode
ARG RUNTIME_IMAGE=set-runtime-image-to-nvidia-cuda-runtime-with-ubuntu-base-or-simply-ubuntu-for-cpu-mode
ARG CUDA_ARCHITECTURES=native
ARG BUILD_TYPE=Release

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
SHELL ["/bin/bash", "-c"]

ENV VCPKG_DEFAULT_BINARY_CACHE=${VCPKG_ROOT}/cache/vcpkg-binary \
    CCACHE_DIR=${VCPKG_ROOT}/cache/ccache

###############################################################################
# System dependencies
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
COPY vcpkg_ports vcpkg_ports
RUN cd ${VCPKG_ROOT} && ./bootstrap-vcpkg.sh -disableMetrics && rm -rf .git

###############################################################################
# Compiler wrapper (auto-detect arch, force compatibility flags)
###############################################################################
RUN set -eux; \
    mkdir -p /opt/compiler-wrappers; \
    ARCH_FLAG="$(uname -m)"; \
    case "$ARCH_FLAG" in \
        x86_64) EXTRA_FLAGS="-march=x86-64 -mtune=generic" ;; \
        aarch64) EXTRA_FLAGS="-march=armv8-a -mtune=generic" ;; \
        *) echo "Unsupported architecture: $ARCH_FLAG" >&2; exit 1 ;; \
    esac; \
    install -d /opt/compiler-wrappers; \
    make_wrapper () { \
        f="/opt/compiler-wrappers/$1"; \
        real="$2"; \
        printf '%s\n' \
        '#!/bin/bash' \
        'for arg in "$@"; do' \
        '  case "$arg" in' \
        '    *'"${VCPKG_ROOT}"'/buildtrees/openblas/src/*) exec __REAL__ "$@" ;; # See custom port' \
        '  esac' \
        'done' \
        'exec __REAL__ "$@" '"$EXTRA_FLAGS"'' \
        | sed "s|__REAL__|$real|g" > "$f"; \
        chmod +x "$f"; \
    }; \
    make_wrapper cc $(command -v cc); \
    make_wrapper c++ $(command -v c++); \
    make_wrapper gfortran $(command -v gfortran)

    ENV PATH=/opt/compiler-wrappers:$PATH

###############################################################################
# Build COLMAP
###############################################################################
COPY colmap colmap
RUN --mount=type=cache,target=/opt/vcpkg/cache,sharing=locked \
    --mount=type=cache,target=/build/colmap/mybuild,sharing=locked \
    set -Eeuo pipefail; \
    TRIPLET="$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')-linux"; \
    export VCPKG_OVERLAY_PORTS=$(pwd)/vcpkg_ports; \
    if [ "$(uname -m)" = "aarch64" ]; then \
        export COLMAP_CMAKE_CONFIGURE_OPTIONS="-DONNX_ENABLED=OFF"; \
    fi; \
    mkdir -p ${VCPKG_DEFAULT_BINARY_CACHE}; \
    FAISS_DEP='"faiss"'; \
    if echo "$BASE_IMAGE" | grep -q cuda; then \
        FAISS_DEP='{"name": "faiss", "features": ["gpu"]}'; \
    fi; \
    sed -i -e "s|\"dependencies\": \[|\"dependencies\": [${FAISS_DEP}, |" colmap/vcpkg.json; \
    rm colmap/vcpkg-configuration.json; \
    sed -i -E ':a;N;$!ba;s/"overrides": \[[^]]*\],?//g' colmap/vcpkg.json; \
    ccache --show-stats --verbose; ccache --zero-stats; \
    LOG=/tmp/cmake-configure.log; \
    if ! cmake -S colmap -B colmap/mybuild -G Ninja \
        -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
        -DCMAKE_TOOLCHAIN_FILE=${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake \
        -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
        -DPKG_CONFIG_EXECUTABLE=/usr/bin/pkg-config \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CUDA_COMPILER_LAUNCHER=ccache \
        -DVCPKG_TARGET_TRIPLET=${TRIPLET} \
        -DCUDA_ENABLED=$(if echo "$BASE_IMAGE" | grep -q cuda; then echo "ON"; else echo "OFF"; fi) \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES} \
        -DFETCH_FAISS=OFF \
        -DGUI_ENABLED=OFF \
        -DTESTS_ENABLED=OFF \
        ${COLMAP_CMAKE_CONFIGURE_OPTIONS:-} \
        2>&1 | tee "$LOG"; then \
        echo "===< CMake failed; printing referenced vcpkg logs >==="; \
        grep -A 5 "    See logs for more information:" "$LOG" | \
        grep -oE '/opt/vcpkg/buildtrees/.+\.log' | tee /dev/stderr | \
        sort -u | while read -r log; do \
            echo "-----< $log >-----"; \
            cat "$log" 2>/dev/null || echo "Log not found"; \
            echo "-----< /$log >-----"; \
        done; \
        exit 1; \
    fi; \
    cmake --build colmap/mybuild -j$(nproc); \
    cmake --install colmap/mybuild --prefix /build/install; \
    ccache --show-stats --verbose; \
    rm -r "colmap/mybuild/vcpkg_installed"

###############################################################################
# Build OpenMVS
###############################################################################
COPY openMVS openMVS
RUN --mount=type=cache,target=/opt/vcpkg/cache,sharing=locked \
    --mount=type=cache,target=/build/openMVS/mybuild,sharing=locked \
    set -Eeuo pipefail; \
    TRIPLET="$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')-linux"; \
    export VCPKG_OVERLAY_PORTS=$(pwd)/vcpkg_ports; \
    rm -r "/build/openMVS/mybuild/vcpkg_installed/$TRIPLET/tools/pkgconf" || true; \
    ccache --show-stats --verbose; ccache --zero-stats; \
    LOG=/tmp/cmake-configure.log; \
    if ! cmake -S openMVS -B openMVS/mybuild -G Ninja \
        -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
        -DCMAKE_TOOLCHAIN_FILE=${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake \
        -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
        -DPKG_CONFIG_EXECUTABLE=/usr/bin/pkg-config \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CUDA_COMPILER_LAUNCHER=ccache \
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$(if [ "${BUILD_TYPE}" = "Debug" ]; then echo OFF; else echo ON; fi) \
        -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON \
        -DVCPKG_TARGET_TRIPLET=${TRIPLET} \
        -DOpenMVS_USE_CUDA=$(if echo "$BASE_IMAGE" | grep -q cuda; then echo ON; else echo OFF; fi) \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES} \
        -DOpenMVS_USE_PYTHON=OFF \
        -DOpenMVS_BUILD_VIEWER=OFF \
        -DOpenMVS_ENABLE_TESTS=OFF \
        -DOpenMVS_USE_BREAKPAD=OFF \
        2>&1 | tee "$LOG"; then \
        echo "===< CMake failed; printing referenced vcpkg logs >==="; \
        grep -A 5 "    See logs for more information:" "$LOG" | \
        grep -oE '/opt/vcpkg/buildtrees/.+\.log' | tee /dev/stderr | \
        sort -u | while read -r log; do \
            echo "-----< $log >-----"; \
            cat "$log" 2>/dev/null || echo "Log not found"; \
            echo "-----< /$log >-----"; \
        done; \
        exit 1; \
    fi; \
    cmake --build openMVS/mybuild -j"$(nproc)"; \
    cmake --install openMVS/mybuild --prefix /build/install; \
    cp -r /usr/local/bin/OpenMVS /build/install/bin/OpenMVS; \
    ccache --show-stats --verbose; \
    rm -r "openMVS/mybuild/vcpkg_installed"

###############################################################################
# Strip binaries (only for Release builds)
###############################################################################
RUN set -eux; \
    if [ "${BUILD_TYPE}" = "Release" ]; then \
        find /build/install -name "*.a" -delete; \
        find /build/install -type f \( -name "*.so" -o -name "*.so.*" \) -exec strip --strip-unneeded {} + 2>/dev/null || true; \
        find /build/install/bin -type f -executable -exec strip --strip-all {} + 2>/dev/null || true; \
    fi

###############################################################################
# Stage 2: Runtime
###############################################################################
FROM ${RUNTIME_IMAGE} AS runtime
ARG BUILD_TYPE

###############################################################################
# Runtime dependencies
###############################################################################
RUN set -eux; \
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
        libxcursor1 \
        libxcomposite1 \
        libxdamage1 \
        libxfixes3 \
        libdbus-1-3 \
        libxrender1 \
        libxcb1 \
        libsystemd0 \
        libxau6 \
        libxdmcp6 \
        libglx-mesa0 \
        libgl1 \
        libgl1-mesa-dri \
        libgomp1" && \
    for attempt in 1 2 3; do sh -c "$APT_CMD" && break || ([ $attempt -lt 3 ] && sleep 5); done && \
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

RUN set -eux; \
    mkdir -p /home/user; \
    chmod 777 /home/user

WORKDIR /home/user

ENV HOME=/home/user \
    USER=user \
    LOGNAME=user \
    SHELL=/bin/bash \
    PATH=/usr/local/bin:/usr/local/bin/OpenMVS:$PATH \
    LD_LIBRARY_PATH=/usr/local/lib:/usr/local/cuda/compat

LABEL org.opencontainers.image.title="colmap-openmvs" \
      org.opencontainers.image.description="COLMAP + OpenMVS: SfM and MVS pipeline" \
      org.opencontainers.image.vendor="COLMAP+OpenMVS" \
      org.opencontainers.image.source="https://github.com/yeicor/colmap-openmvs"

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
CMD ["--help"]
