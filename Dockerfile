# CPU variant: ubuntu:24.04
# CUDA variant: nvidia/cuda:<version>-devel-ubuntu24.04
ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

# Re-declare ARGs after FROM (they are scoped per build stage)
ARG CUDA_ENABLED=0
ARG CUDA_ARCHITECTURES=all-major

ENV DEBIAN_FRONTEND=noninteractive

# Install build tools and system dependencies required by vcpkg ports
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake ninja-build git pkg-config \
        ca-certificates curl zip unzip tar python3 \
        autoconf autoconf-archive automake bison libtool libltdl-dev nasm \
        libgl-dev libglu1-mesa-dev libxmu-dev libdbus-1-dev libxtst-dev \
        libxi-dev libxinerama-dev libxcursor-dev xorg-dev \
    && rm -rf /var/lib/apt/lists/*

# Bootstrap vcpkg from the pinned submodule (no network fetch at build time)
ENV VCPKG_ROOT=/opt/vcpkg
COPY vcpkg $VCPKG_ROOT
RUN $VCPKG_ROOT/bootstrap-vcpkg.sh -disableMetrics

WORKDIR /build

# Build colmap; vcpkg reads colmap/vcpkg.json and installs all declared dependencies.
# Both projects share /build/vcpkg_installed so common deps are only built once.
# x64-linux-release builds release-only shared libs (no debug copies).
COPY colmap colmap
RUN cmake -S colmap -B colmap/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake \
        -DVCPKG_TARGET_TRIPLET=x64-linux-release \
        -DVCPKG_INSTALLED_DIR=/build/vcpkg_installed \
        -DGUI_ENABLED=OFF \
        -DCUDA_ENABLED=${CUDA_ENABLED} \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES} \
        -DTESTS_ENABLED=OFF \
        -GNinja \
    && cmake --build colmap/build \
    && cmake --install colmap/build

# Build openMVS; vcpkg reads openMVS/vcpkg.json and installs all declared dependencies
COPY openMVS openMVS
RUN cmake -S openMVS -B openMVS/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake \
        -DVCPKG_TARGET_TRIPLET=x64-linux-release \
        -DVCPKG_INSTALLED_DIR=/build/vcpkg_installed \
        -DOpenMVS_USE_CUDA=${CUDA_ENABLED} \
        -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES} \
        -DOpenMVS_USE_PYTHON=OFF \
        -GNinja \
    && cmake --build openMVS/build \
    && cmake --install openMVS/build

ENV PATH=/usr/local/bin/OpenMVS:$PATH

# Copy vcpkg-built runtime shared libraries to the system library path, then clean up
# all build artefacts and the vcpkg tree (not needed at runtime).
RUN cp -an /build/vcpkg_installed/x64-linux-release/lib/. /usr/local/lib/ \
    && ldconfig \
    && rm -rf /build $VCPKG_ROOT

WORKDIR /
COPY entrypoint.sh entrypoint.sh
RUN chmod 0777 entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]
