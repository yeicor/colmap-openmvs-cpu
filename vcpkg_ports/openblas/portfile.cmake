# Copy upstream port files except portfile.cmake
file(COPY "${VCPKG_ROOT_DIR}/ports/openblas/" DESTINATION "${CMAKE_CURRENT_LIST_DIR}" PATTERN "portfile.cmake" EXCLUDE)

# Patch upstream portfile.cmake (support and optimize for more platforms, not just native at build time)
string(REPLACE "-DBUILD_TESTING=OFF" "-DBUILD_TESTING=OFF -DDYNAMIC_ARCH=ON -DDYNAMIC_OLDER=ON" upstream_content "${upstream_content}")
file(WRITE "${CMAKE_CURRENT_LIST_DIR}/portfile_upstream_patched.cmake" "${upstream_content}")

# Include the upstream portfile.cmake
include("${CMAKE_CURRENT_LIST_DIR}/portfile_upstream_patched.cmake")
