FROM archlinux/archlinux:base-devel-20250710.0.380727

# Install system dependencies (build and runtime)
RUN pacman -Syu --noconfirm --needed sudo git cmake libpng libjpeg-turbo libjxl libtiff glu glew glfw-x11 python git cmake ninja boost eigen flann freeimage google-glog gtest gmock sqlite glew qt6-base gambas3-gb-qt6-opengl vtk ceres-solver boost boost-libs opencv cgal
RUN mkdir -p /build # Otherwise docker cache fails?!
WORKDIR /build

# Copy and build gklib and metis git submodules
COPY gklib gklib
RUN cd gklib && make config cc=gcc prefix=/usr shared=1 && make install && ln -s /usr/lib/libGKlib.so.0 /usr/lib/libGKlib.so && cd ..
COPY metis metis
RUN cd metis && make config cc=gcc prefix=/usr shared=1 gklib_path=/usr && make install && cd ..

# Copy and build VCG and openmvs git submodule
COPY VCG VCG
COPY openMVS openMVS
RUN cd openMVS && mkdir mybuild && cd mybuild && cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_VERBOSE_MAKEFILE=ON -DVCG_ROOT=$(realpath ../../VCG) .. && cmake --build . -j$(nproc) && cmake --install .
ENV PATH=/usr/local/bin/OpenMVS:$PATH

# Copy and build colmap git submodule
COPY colmap colmap 
# - Patch waiting for https://github.com/colmap/colmap/pull/3470
RUN cd colmap && sed -i 's/${METIS_LIBRARIES}/${METIS_LIBRARIES} ${GK_LIBRARIES}/g' cmake/FindMetis.cmake && \
    mkdir build && cd build && cmake .. -GNinja && ninja && ninja install
    
# Cleanup stuff
WORKDIR /
RUN rm -rf /build

# Set entrypoint
COPY entrypoint.sh entrypoint.sh
RUN chmod 0777 entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]
