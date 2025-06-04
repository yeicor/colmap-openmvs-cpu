FROM ubuntu:plucky-20250521

# Install system dependencies (build and runtime)
RUN apt-get update -yq && apt-get -yq install build-essential git cmake libpng-dev libjpeg-dev libtiff-dev libglu1-mesa-dev libglew-dev libglfw3-dev python3-dev git cmake ninja-build build-essential libboost-program-options-dev libboost-graph-dev libboost-system-dev libeigen3-dev libflann-dev libfreeimage-dev libmetis-dev libgoogle-glog-dev libgtest-dev libgmock-dev libsqlite3-dev libglew-dev qtbase5-dev libqt5opengl5-dev libcgal-dev libceres-dev libboost-iostreams-dev libboost-program-options-dev libboost-system-dev libboost-serialization-dev libopencv-dev libcgal-dev libcgal-qt6-dev
WORKDIR /build

# Copy and build colmap git submodule
COPY colmap colmap
RUN cd colmap && mkdir build && cd build && cmake .. -GNinja && ninja && ninja install

# Copy and build openmvs git submodule
COPY VCG VCG
COPY openMVS openMVS
RUN cd openMVS && mkdir cmake && cd cmake && cmake -DCMAKE_BUILD_TYPE=Release -DVCG_ROOT=../../VCG .. && cmake --build . -j$(nproc) && cmake --install .
ENV PATH=/usr/local/bin/OpenMVS:$PATH

# Set entrypoint
COPY entrypoint.sh entrypoint.sh
RUN chmod 0777 entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]
