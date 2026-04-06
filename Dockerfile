FROM archlinux:base-devel-20260329.0.507017

# Install system dependencies (build and runtime)
RUN sudo pacman -Syu --noconfirm --needed git && useradd -m builduser && echo 'builduser ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers && sudo -u builduser bash -c "cd /tmp && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si --noconfirm"
RUN sudo -u builduser bash -c "yay -Syu --noconfirm --needed sudo git cmake libpng libjpeg-turbo libjxl libtiff glu glew glfw-x11 python git cmake ninja flann freeimage google-glog gtest gmock sqlite glew qt6-base gambas3-gb-qt6-opengl vtk boost boost-libs opencv cgal openimageio eigen3 suitesparse"
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
RUN cd nanoflann && cmake -B build -S . -DCMAKE_BUILD_TYPE=Release && cmake --build build && cmake --install build

# Copy and build tinyxml2 (required for TinyEXIF)
COPY tinyxml2 tinyxml2
RUN cd tinyxml2 && cmake -B build -S . -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON && cmake --build build && cmake --install build

# Copy and build TinyEXIF (required for openMVS)
COPY TinyEXIF TinyEXIF
RUN cd TinyEXIF && cmake -B build -S . -DCMAKE_BUILD_TYPE=Release && cmake --build build && cmake --install build

# Copy and build VCG (required for openMVS)
COPY VCG VCG
RUN cd VCG && cmake -B build -S . -DCMAKE_BUILD_TYPE=Release && cmake --build build && cmake --install build
    
# Copy and build openMVS git submodule (required for colmap)
COPY openMVS openMVS
RUN sed -E -i 's/FIND_PACKAGE\(Boost REQUIRED COMPONENTS ([^)]*)\bsystem\b ? ([^)]*)\)/FIND_PACKAGE(Boost REQUIRED COMPONENTS \1\2)/g' openMVS/CMakeLists.txt  # https://bbs.archlinux.org/viewtopic.php?id=309669
RUN cd openMVS && cmake -B build -S . -DCMAKE_BUILD_TYPE=Release -DOpenMVS_USE_PYTHON=OFF -DVCG_ROOT=$(realpath ../VCG) -GNinja && cmake --build build && cmake --install build
ENV PATH=/usr/local/bin/OpenMVS:$PATH

# Copy and build ceres-solver (required for colmap)
COPY ceres-solver ceres-solver
RUN cd ceres-solver && cmake -B build -S . -DCMAKE_BUILD_TYPE=Release -DSUITESPARSE=ON && cmake --build build && cmake --install build

# Copy and build colmap git submodule
COPY colmap colmap
RUN cd colmap && cmake -B build -S . -DCMAKE_BUILD_TYPE=Release -GNinja && cmake --build build && cmake --install build

# Cleanup stuff
WORKDIR /
RUN rm -rf /build

# Set entrypoint
COPY entrypoint.sh entrypoint.sh
RUN chmod 0777 entrypoint.sh
ENTRYPOINT ["./entrypoint.sh"]
