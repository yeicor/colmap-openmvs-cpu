FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install build tools and system dependencies required by vcpkg ports
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        ninja-build \
        git \
        pkg-config \
        curl \
        zip \
        unzip \
        tar \
        python3 \
        autoconf \
        autoconf-archive \
        automake \
        bison \
        libtool \
        libltdl-dev \
        nasm \
        libgl-dev \
        libglu1-mesa-dev \
        libxmu-dev \
        libdbus-1-dev \
        libxtst-dev \
        libxi-dev \
        libxinerama-dev \
        libxcursor-dev \
        xorg-dev \
    && rm -rf /var/lib/apt/lists/*

# Bootstrap vcpkg (dependency manager used by both colmap and openMVS)
ENV VCPKG_ROOT=/opt/vcpkg
RUN git clone --depth 1 https://github.com/microsoft/vcpkg.git $VCPKG_ROOT \
    && $VCPKG_ROOT/bootstrap-vcpkg.sh -disableMetrics
ENV PATH="$VCPKG_ROOT:$PATH"

RUN mkdir -p /build
WORKDIR /build

# Build colmap; vcpkg reads colmap/vcpkg.json and automatically installs all dependencies.
# x64-linux-release builds only release-mode libs (no debug), halving build time and
# package size; it is also the triplet used by openMVS's own upstream CI.
COPY colmap colmap
RUN cmake -S colmap -B colmap/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake \
        -DVCPKG_TARGET_TRIPLET=x64-linux-release \
        -DGUI_ENABLED=OFF \
        -DCUDA_ENABLED=OFF \
        -DTESTS_ENABLED=OFF \
        -GNinja \
    && cmake --build colmap/build \
    && cmake --install colmap/build

# Build openMVS; vcpkg reads openMVS/vcpkg.json and automatically installs all dependencies
COPY openMVS openMVS
RUN cmake -S openMVS -B openMVS/build \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake \
        -DVCPKG_TARGET_TRIPLET=x64-linux-release \
        -DOpenMVS_USE_CUDA=OFF \
        -DOpenMVS_USE_PYTHON=OFF \
        -GNinja \
    && cmake --build openMVS/build \
    && cmake --install openMVS/build

ENV PATH=/usr/local/bin/OpenMVS:$PATH

# Install vcpkg-built runtime libraries to the system path and clean up build artifacts.
# Both projects use the same triplet, so their shared dependencies are identical versions;
# cp -an (no-clobber) safely handles any overlapping .so files without conflicts.
RUN find /build -path "*/vcpkg_installed/*/lib" -type d \
        -exec cp -an "{}"/. /usr/local/lib/ \; \
    && ldconfig \
    && rm -rf /build

# Set entrypoint
WORKDIR /
COPY entrypoint.sh entrypoint.sh
RUN chmod 0777 entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]
