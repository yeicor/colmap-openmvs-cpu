FROM archlinux/archlinux:base-devel-20250710.0.380727

# Install system dependencies (build and runtime)
RUN pacman -Syu --noconfirm --needed sudo git cmake libpng libjpeg-turbo libjxl libtiff glu glew glfw-x11 python git cmake ninja boost eigen flann freeimage google-glog gtest gmock sqlite glew qt5-base gambas3-gb-qt5-opengl ceres-solver boost boost-libs opencv cgal # metis cgal-qt6
RUN git clone "https://github.com/KarypisLab/gklib" && cd gklib && make config cc=gcc prefix=/usr && make install && cd .. && rm -rf gklib && \
    git clone "https://github.com/KarypisLab/metis" && cd metis && make config cc=gcc prefix=/usr shared=1 && make install && cd .. && rm -rf metis
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
