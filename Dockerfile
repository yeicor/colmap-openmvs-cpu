# syntax=docker/dockerfile:1.12
# Unified Dockerfile for COLMAP + OpenMVS
# Supports both CPU (ubuntu) and CUDA builds via --build-arg variants

###############################################################################
# Stage 1: Base - Build tools, vcpkg, sccache
###############################################################################
# Arguments to switch between CPU and CUDA base images
ARG BASE_IMAGE=nvidia/cuda:12.9.1-devel-ubuntu22.04 # or ubuntu:24.04 for CPU
ARG RUNTIME_IMAGE=nvidia/cuda:12.9.1-runtime-ubuntu22.04 # or ubuntu:24.04 for CPU
ARG CUDA_ENABLED=ON
ARG CUDA_ARCHITECTURES=all-major

FROM ${BASE_IMAGE} AS builder

WORKDIR /build

ENV DEBIAN_FRONTEND=noninteractive \
    VCPKG_ROOT=/opt/vcpkg \
    VCPKG_OVERLAY_TRIPLETS=/build/vcpkg_triplets \
    VCPKG_INSTALLED_DIR=/build/vcpkg_installed \
    CC=gcc CXX=g++ \
    SCCACHE_DIR=/cache/sccache \
    SCCACHE_CACHE_SIZE=20G

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake ninja-build git curl zip unzip tar \
        pkg-config python3 python3-venv gfortran \
        autoconf autoconf-archive automake bison libtool libltdl-dev nasm \
        libgl-dev libglu1-mesa-dev libxmu-dev libdbus-1-dev libxtst-dev \
        libxi-dev libxinerama-dev libxcursor-dev xorg-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN set -eu; \
    arch="$(uname -m)"; \
    case "$arch" in \
        x86_64)  sccache_arch="x86_64-unknown-linux-musl" ;; \
        aarch64) sccache_arch="aarch64-unknown-linux-musl" ;; \
        *) echo "Unsupported arch: $arch" && exit 1 ;; \
    esac; \
    curl -fSL "https://github.com/mozilla/sccache/releases/download/v0.14.0/sccache-v0.14.0-${sccache_arch}.tar.gz" -o sccache.tar.gz \
    && tar xzf sccache.tar.gz --strip-components=1 \
    && mv sccache /usr/local/bin/sccache \
    && chmod +x /usr/local/bin/sccache \
    && rm -f sccache.tar.gz

COPY --chmod=755 vcpkg "${VCPKG_ROOT}"
RUN cd "${VCPKG_ROOT}" && ./bootstrap-vcpkg.sh -disableMetrics && rm -rf "${VCPKG_ROOT}/.git"

COPY --chmod=755 colmap colmap
RUN --mount=type=cache,target=/cache/sccache,sharing=locked \
    sccache --show-stats && sccache --zero-stats 2>/dev/null || true \
    && cmake -S colmap -B colmap/build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake \
        -DVCPKG_TARGET_TRIPLET=$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')-linux-release \
        -DVCPKG_INSTALLED_DIR=${VCPKG_INSTALLED_DIR} \
        -DGUI_ENABLED=OFF \
        -DCUDA_ENABLED=${CUDA_ENABLED} \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES} \
        -DTESTS_ENABLED=OFF \
        -DCMAKE_C_COMPILER_LAUNCHER=sccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=sccache \
        ${CMAKE_CONFIGURE_OPTIONS:-} \
    && cmake --build colmap/build -j$(nproc) \
    && cmake --install colmap/build --prefix /build/install \
    && sccache --show-stats || (find /opt/vcpkg/buildtrees -name "*.log" -exec cat {} \; 2>/dev/null; exit 1)

COPY --chmod=755 openMVS openMVS
RUN --mount=type=cache,target=/cache/sccache,sharing=locked \
    sccache --show-stats && sccache --zero-stats 2>/dev/null || true \
    && cmake -S openMVS -B openMVS/build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake \
        -DVCPKG_TARGET_TRIPLET=$(uname -m | sed 's/x86_64/x64/;s/aarch64/arm64/')-linux-release \
        -DVCPKG_INSTALLED_DIR=${VCPKG_INSTALLED_DIR} \
        -DOpenMVS_USE_CUDA=${CUDA_ENABLED} \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES} \
        -DOpenMVS_USE_PYTHON=OFF \
        -DOpenMVS_BUILD_VIEWER=OFF \
        -DCMAKE_C_COMPILER_LAUNCHER=sccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=sccache \
    && cmake --build openMVS/build -j$(nproc) \
    && cmake --install openMVS/build --prefix /build/install \
    && sccache --show-stats || (find /opt/vcpkg/buildtrees -name "*.log" -exec cat {} \; 2>/dev/null; exit 1)

RUN find /build/install -type f \( -name "*.so" -o -name "*.so.*" \) -exec strip --strip-unneeded {} + 2>/dev/null || true \
    && find /build/install/bin -type f -executable -exec strip --strip-all {} + 2>/dev/null || true \
    && find /build/install -name "*.a" -exec strip --strip-debug {} + 2>/dev/null || true

###############################################################################
# Stage 2: Runtime - Minimal image for the final container
###############################################################################
FROM ${RUNTIME_IMAGE} AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
    PATH=/usr/local/bin:/usr/local/bin/OpenMVS:$PATH \
    LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu

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

COPY --from=builder /build/install /usr/local
COPY --from=builder /build/vcpkg_installed/x64-linux/lib /usr/local/lib/
COPY --from=builder /build/vcpkg_installed/x64-linux/share /usr/local/share/
COPY --from=builder /build/vcpkg_installed/x64-linux/include /usr/local/include/

RUN ldconfig

COPY --chmod=755 entrypoint.sh /entrypoint.sh

LABEL org.opencontainers.image.title="colmap-openmvs" \
      org.opencontainers.image.description="COLMAP + OpenMVS: SfM and MVS pipeline" \
      org.opencontainers.image.vendor="COLMAP+OpenMVS" \
      org.opencontainers.image.source="https://github.com/yeicor/colmap-openmvs"

ENTRYPOINT ["/entrypoint.sh"]
CMD ["--help"]
