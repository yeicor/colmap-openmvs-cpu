# Copy upstream port files except portfile.cmake
file(COPY "${VCPKG_ROOT_DIR}/ports/openblas/" DESTINATION "${CMAKE_CURRENT_LIST_DIR}" PATTERN "portfile.cmake" EXCLUDE)

# Patch upstream portfile.cmake (support and optimize for more platforms, not just native at build time)
# https://github.com/OpenMathLib/OpenBLAS#support-for-multiple-targets-in-a-single-library
if(CMAKE_SYSTEM_PROCESSOR MATCHES "^x86_64")
  string(REPLACE "-DBUILD_TESTING=OFF" "-DBUILD_TESTING=OFF -DDYNAMIC_ARCH=ON -DDYNAMIC_OLDER=ON -DTARGET=HASWELL" upstream_content "${upstream_content}")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^aarch64")
  string(REPLACE "-DBUILD_TESTING=OFF" "-DBUILD_TESTING=OFF -DDYNAMIC_ARCH=ON -DDYNAMIC_OLDER=ON -DTARGET=ARMV8" upstream_content "${upstream_content}")
else()
  message(FATAL_ERROR "Unsupported architecture ${CMAKE_SYSTEM_PROCESSOR}")
endif()
file(WRITE "${CMAKE_CURRENT_LIST_DIR}/portfile_upstream_patched.cmake" "${upstream_content}")

# Include the upstream portfile.cmake
include("${CMAKE_CURRENT_LIST_DIR}/portfile_upstream_patched.cmake")
