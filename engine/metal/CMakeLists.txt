# metal/ - the DeepSeek-V4.1-Flash engine on Apple Silicon (Metal).  Its own CMake project, macOS only, never part of the
# CUDA / HIP build at the root.  UNTESTED in this repository (no Mac to build it on): the sources are upstream Strata's at 13eedf552.
#
# The engine's .cu sources compile as C++: include/metal_compat goes first on the include path and gives them the CUDA runtime
# names over the Metal device runtime (src/gpu/runtime.cpp, metal-cpp).  The kernels are src/engine/* (host side) and
# kernels/*.metal + src/engine/msl/*.metal (compiled at run time).
#
#   cmake -S metal -B build-metal -G Ninja -DCMAKE_BUILD_TYPE=Release -DMETAL_CPP_DIR=<metal-cpp headers>
#   ninja -C build-metal strata_ds4
cmake_minimum_required(VERSION 3.24)
project(strata_dsv41_metal VERSION 0.1.59.1 LANGUAGES C CXX OBJCXX)

if(NOT APPLE)
  message(FATAL_ERROR "metal/ builds on macOS only")
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 20)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()
set(CMAKE_CXX_FLAGS_RELEASE "-O2")
set(CMAKE_OBJCXX_FLAGS_RELEASE "-O2")

get_filename_component(STRATA_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
set(GGML_COMMON "${STRATA_ROOT}/third_party/ggml/ggml-common.h")

# ---- the kernel runtime and its parity tests ----------------------------------------------------------------------
add_library(mtl_rt STATIC src/mtl_rt.mm src/ref_quant.cpp src/gguf_lite.cpp)
target_include_directories(mtl_rt PUBLIC src ${STRATA_ROOT}/third_party/ggml ${STRATA_ROOT}/include)
target_compile_options(mtl_rt PRIVATE $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
target_compile_definitions(mtl_rt PRIVATE
  STRATA_GGML_COMMON_DEFAULT="${GGML_COMMON}"
  STRATA_METAL_KERNELS_DEFAULT="${CMAKE_CURRENT_SOURCE_DIR}/kernels")
target_link_libraries(mtl_rt PUBLIC "-framework Metal" "-framework Foundation")

foreach(t ds4_dq_parity ds4_route_guard_parity)
  add_executable(${t} tests/${t}.cpp)
  target_link_libraries(${t} PRIVATE mtl_rt)
endforeach()

# ---- the engine ------------------------------------------------------------------------------------------------------
set(METAL_CPP_DIR "" CACHE PATH "metal-cpp headers (https://developer.apple.com/metal/cpp/)")
if(NOT EXISTS "${METAL_CPP_DIR}/Metal/Metal.hpp")
  message(STATUS "strata-dsv41 metal: METAL_CPP_DIR is not set: the engine (strata_ds4) is not built")
  return()
endif()

# ggml-base / ggml-cpu from the vendored third_party/strata-ggml: the native expert formats' type traits and the CPU lane's NEON dots
include(${STRATA_ROOT}/cmake/strata_ggml.cmake)
strata_ggml_resolve("${STRATA_ROOT}")
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_STATIC ON CACHE BOOL "" FORCE)
set(GGML_METAL OFF CACHE BOOL "" FORCE)
set(GGML_BLAS OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
add_subdirectory(${_strata_ggml_root}/ggml ${CMAKE_BINARY_DIR}/ggml EXCLUDE_FROM_ALL)

# The CPU kernels the engine's CPU lane uses.  portable.cpp is the arm64 stand-in for the x86 AVX entry points (each says so and stops
# if it is ever reached; the engine asks the *_supported() checks first and keeps ggml-cpu's rows).
set(S ${STRATA_ROOT}/src)
add_library(strata_kernels_cpu STATIC
  ${S}/kernels/cpu/portable.cpp ${S}/kernels/cpu/pool.cpp ${S}/kernels/cpu/expert_layout.cpp ${S}/kernels/cpu/hadamard.cpp
  ${S}/kernels/cpu/native_expert.cpp ${S}/kernels/cpu/tq_cpu.cpp ${S}/platform/io_priority.cpp)
target_include_directories(strata_kernels_cpu PUBLIC ${STRATA_ROOT}/include PRIVATE ${STRATA_ROOT}/third_party/ggml
                           ${_strata_ggml_root}/ggml/include ${_strata_ggml_root}/ggml/src ${_strata_ggml_root}/ggml/src/ggml-cpu)
target_compile_definitions(strata_kernels_cpu PUBLIC STRATA_NATIVE_EXPERTS=1)
target_compile_options(strata_kernels_cpu PRIVATE -Wno-unused-parameter -Wno-deprecated-declarations)
find_package(Threads REQUIRED)
target_link_libraries(strata_kernels_cpu PUBLIC ggml-cpu ggml-base Threads::Threads)

add_library(strata_gpu_metal STATIC src/gpu/runtime.cpp)
target_include_directories(strata_gpu_metal BEFORE PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include/metal_compat
                           ${CMAKE_CURRENT_SOURCE_DIR}/include ${STRATA_ROOT}/include)
target_include_directories(strata_gpu_metal SYSTEM PUBLIC ${METAL_CPP_DIR})
target_compile_definitions(strata_gpu_metal PUBLIC STRATA_GPU_METAL=1)
target_link_libraries(strata_gpu_metal PUBLIC "-framework Metal" "-framework Foundation" "-framework QuartzCore")

# The Metal kernel library (host side).  ds4_finish.cpp is compiled into the program itself (below).
add_library(strata_metal_kernels STATIC
  src/engine/ds4_ctx.cpp src/engine/ds4_host.cpp src/engine/ds4_vision_metal.cpp src/engine/exl3_legacy_stub.cpp)
target_include_directories(strata_metal_kernels PRIVATE src ${STRATA_ROOT}/third_party/ggml)
target_compile_definitions(strata_metal_kernels PRIVATE
  STRATA_GGML_COMMON_DEFAULT="${GGML_COMMON}" STRATA_METAL_KERNELS_DEFAULT="${CMAKE_CURRENT_SOURCE_DIR}/kernels")
target_link_libraries(strata_metal_kernels PUBLIC strata_gpu_metal mtl_rt)

set(DS4 ${STRATA_ROOT}/src/dsv41)
set(STRATA_DS4_SOURCES
  ${DS4}/ds4_main.cpp ${CMAKE_CURRENT_SOURCE_DIR}/src/engine/ds4_finish.cpp ${DS4}/ds4_model.cu ${DS4}/ds4_gguf.cu ${DS4}/ds4_iq.cu
  ${DS4}/ds4_kernels.cu ${DS4}/ds4_tq.cu ${DS4}/ds4_vision.cu
  ${DS4}/vendor/exl3.cu ${DS4}/vendor/exl3_cpu.cpp ${DS4}/vendor/moe_win.cu ${DS4}/vendor/sampler.cu
  ${DS4}/ds4_gg_cpu.cpp ${DS4}/ds4_gguf_cpu.cpp ${DS4}/ds4_iq_cpu.cpp ${DS4}/ds4_tq_cpu.cpp ${DS4}/ds4_packinfo.cpp)
set_source_files_properties(
  ${DS4}/ds4_model.cu ${DS4}/ds4_gguf.cu ${DS4}/ds4_iq.cu ${DS4}/ds4_kernels.cu ${DS4}/ds4_tq.cu ${DS4}/ds4_vision.cu
  ${DS4}/vendor/exl3.cu ${DS4}/vendor/moe_win.cu ${DS4}/vendor/sampler.cu
  PROPERTIES LANGUAGE CXX)
# The CPU lane for the experts the GPU does not hold (ggml-cpu's NEON row dots)
set_source_files_properties(${DS4}/ds4_gg_cpu.cpp PROPERTIES COMPILE_DEFINITIONS "STRATA_DSV41_TQ_CPU=1")

# The engine's queue, residency and barrier rules live in mtl_rt.mm and gpu/runtime.cpp behind STRATA_DS4_RUNTIME.  strata_ds4
# compiles its own copy of these two files with it, linked as objects so they win over the same symbols in the libraries.
add_library(ds4_rt_mm OBJECT src/mtl_rt.mm)
target_include_directories(ds4_rt_mm PRIVATE src ${STRATA_ROOT}/third_party/ggml ${STRATA_ROOT}/include)
target_compile_options(ds4_rt_mm PRIVATE $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
target_compile_definitions(ds4_rt_mm PRIVATE STRATA_DS4_RUNTIME=1 STRATA_GGML_COMMON_DEFAULT="${GGML_COMMON}"
  STRATA_METAL_KERNELS_DEFAULT="${CMAKE_CURRENT_SOURCE_DIR}/kernels")
add_library(ds4_rt_gpu OBJECT src/gpu/runtime.cpp)
target_include_directories(ds4_rt_gpu BEFORE PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include/metal_compat
                           ${CMAKE_CURRENT_SOURCE_DIR}/include ${STRATA_ROOT}/include)
target_include_directories(ds4_rt_gpu SYSTEM PRIVATE ${METAL_CPP_DIR})
target_compile_definitions(ds4_rt_gpu PRIVATE STRATA_DS4_RUNTIME=1 STRATA_GPU_METAL=1)

add_executable(strata_ds4 ${STRATA_DS4_SOURCES} $<TARGET_OBJECTS:ds4_rt_mm> $<TARGET_OBJECTS:ds4_rt_gpu>)
target_include_directories(strata_ds4 PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/include/metal_compat ${STRATA_ROOT}/include ${DS4} ${CMAKE_CURRENT_SOURCE_DIR}/src
  ${STRATA_ROOT}/third_party/ggml ${_strata_ggml_root}/ggml/include ${_strata_ggml_root}/ggml/src ${_strata_ggml_root}/ggml/src/ggml-cpu)
target_compile_definitions(strata_ds4 PRIVATE STRATA_METAL=1 STRATA_VERSION="${PROJECT_VERSION}-metal")
target_compile_options(strata_ds4 PRIVATE -Wno-unused-parameter -Wno-deprecated-declarations -Wno-implicit-function-declaration)
target_link_libraries(strata_ds4 PRIVATE strata_metal_kernels strata_kernels_cpu)

# The commit the program was built from, shown by --version: -DSTRATA_BUILD_ID=..., else BUILD_ID beside the sources, else git, else "source".
if(NOT STRATA_BUILD_ID AND EXISTS ${STRATA_ROOT}/BUILD_ID)
  file(STRINGS ${STRATA_ROOT}/BUILD_ID STRATA_BUILD_ID LIMIT_COUNT 1)
endif()
if(NOT STRATA_BUILD_ID)
  execute_process(COMMAND git -C ${STRATA_ROOT} rev-parse --short=9 HEAD OUTPUT_VARIABLE STRATA_BUILD_ID OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
endif()
if(NOT STRATA_BUILD_ID)
  set(STRATA_BUILD_ID source)
endif()
set_source_files_properties(${DS4}/ds4_main.cpp PROPERTIES COMPILE_DEFINITIONS "DS4_BUILD_ID=\"${STRATA_BUILD_ID}\"")
