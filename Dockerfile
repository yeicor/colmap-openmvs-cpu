# syntax=docker/dockerfile:1.12
# Multi-stage build for COLMAP + OpenMVS
# Build stage: uses base image with build tools
ARG BASE_IMAGE=myorg/colmap-base:latest
FROM ${BASE_IMAGE} AS builder

ARG CUDA_ENABLED=0
ARG CUDA_ARCHITECTURES=all-major

ENV DEBIAN_FRONTEND=noninteractive \
    VCPKG_DEFAULT_TRIPLET=x64-linux \
    VCPKG_INSTALLED_DIR=/build/vcpkg_installed \
    SCCACHE_DIR=/cache/sccache \
    SCCACHE_CACHE_SIZE=20G

WORKDIR /build

# Utility: capture and print vcpkg build logs
RUN echo '#!/bin/bash\nset -euo pipefail\n\
capture_vcpkg_logs() { \
    failed=0; \
    for log in $(find /opt/vcpkg/buildtrees -name "*.log" 2>/dev/null | head -50); do \
        if grep -qi "error\\|failed" "$log" 2>/dev/null; then \
            echo "=== $(basename $(dirname $log)) BUILD FAILED ==="; \
            cat "$log" | head -100; \
            failed=1; \
        fi; \
    done; \
    return $failed; \
}; \
capture_vcpkg_logs' > /usr/local/bin/capture-vcpkg-logs.sh && chmod +x /usr/local/bin/capture-vcpkg-logs.sh

COPY --chmod=755 colmap colmap

RUN --mount=type=cache,target=/cache/sccache,sharing=locked \
    sccache --zero-stats 2>/dev/null || true \
    && cmake -S colmap -B colmap/build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake \
        -DVCPKG_TARGET_TRIPLET=x64-linux \
        -DVCPKG_INSTALLED_DIR=${VCPKG_INSTALLED_DIR} \
        -DGUI_ENABLED=OFF \
        -DCUDA_ENABLED=${CUDA_ENABLED} \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES} \
        -DTESTS_ENABLED=OFF \
        -DCMAKE_C_COMPILER_LAUNCHER=sccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=sccache \
    && cmake --build colmap/build -j$(nproc) \
    && cmake --install colmap/build --prefix /build/install \
    && sccache --show-stats || (find /opt/vcpkg/buildtrees -name "*.log" -exec cat {} \; 2>/dev/null; exit 1)

COPY --chmod=755 openMVS openMVS

RUN --mount=type=cache,target=/cache/sccache,sharing=locked \
    sccache --zero-stats 2>/dev/null || true \
    && cmake -S openMVS -B openMVS/build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake \
        -DVCPKG_TARGET_TRIPLET=x64-linux \
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

# Stage: save buildtrees for debugging (only on failure, triggered separately)
FROM scratch AS debug-artifacts
COPY --from=builder /opt/vcpkg/buildtrees /buildtrees
COPY --from=builder /build/vcpkg_installed/x64-linux/lib /vcpkg_installed/lib
COPY --from=builder /build/vcpkg_installed/x64-linux/include /vcpkg_installed/include

# Runtime stage: minimal Ubuntu with only runtime libs
FROM ubuntu:24.04 AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
    PATH=/usr/local/bin:/usr/local/bin/OpenMVS:$PATH \
    LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        libstdc++6 libgcc-s1 libgfortran5 ca-certificates \
        libgl1 libglu1-mesa \
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
