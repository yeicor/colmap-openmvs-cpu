FROM archlinux:base-devel-20251221.0.472429

# Install system dependencies (build and runtime)
RUN sudo pacman -Syu --noconfirm --needed git && useradd -m builduser && echo 'builduser ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers && sudo -u builduser bash -c "cd /tmp && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si --noconfirm"
RUN yay -Syu --noconfirm --needed sudo git cmake libpng libjpeg-turbo libjxl libtiff glu glew glfw-x11 python git cmake ninja boost eigen flann freeimage google-glog gtest gmock sqlite glew qt6-base gambas3-gb-qt6-opengl vtk ceres-solver boost boost-libs opencv cgal openimageio
RUN mkdir -p /build # Otherwise docker cache fails?!
WORKDIR /build

# Copy and build gklib and metis git submodules (colmap likes gklib statically compiled within libmetis.so)
COPY gklib gklib
RUN cd gklib && CFLAGS="-fPIC" make config cc=gcc prefix=/usr && make install && cd ..
COPY metis metis
RUN cd metis && echo "target_link_libraries(metis libGKlib.a)" >> libmetis/CMakeLists.txt && \
    make config cc=gcc prefix=/usr shared=1 gklib_path=/usr && make install && cd ..

# Copy and build nanoflann (required for openMVS)
COPY nanoflann nanoflann
RUN cd nanoflann && cmake -B build -S . && cmake --install build
    
# Copy and build VCG and openmvs git submodule
COPY VCG VCG
COPY openMVS openMVS
RUN cd openMVS && mkdir mybuild && cd mybuild && cmake -DCMAKE_BUILD_TYPE=Release -DVCG_ROOT=$(realpath ../../VCG) -GNinja .. && ninja && ninja install
ENV PATH=/usr/local/bin/OpenMVS:$PATH

# Copy and build colmap git submodule
COPY colmap colmap
RUN cd colmap && mkdir build && cd build && cmake -GNinja .. && ninja && ninja install

# Copy and build glomap git submodule
COPY glomap glomap
RUN cd glomap && mkdir build && cd build && cmake -GNinja .. && ninja && ninja install
    
# Cleanup stuff
WORKDIR /
RUN rm -rf /build

# Set entrypoint
COPY entrypoint.sh entrypoint.sh
RUN chmod 0777 entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]
