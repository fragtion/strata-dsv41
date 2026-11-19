# strata-dsv41 - the DeepSeek-V4.1-Flash engine (strata-dsv41), taken from Strata (github.com/Niko1221/Strata) at 13eedf552.
#
# One target: the engine strata-dsv41 for NVIDIA (STRATA_ENABLE_CUDA) or AMD (STRATA_ENABLE_HIP), plus its tests
# (STRATA_BUILD_TESTS).  The Mac (Metal) engine is the separate project in metal/.
#
#   cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=Release -DSTRATA_ENABLE_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86
#   cmake --build build --target strata-dsv41
#
# The CPU side (the experts that do not fit in VRAM) runs on ggml-cpu, built from the copy vendored in
# third_party/strata-ggml: nothing is downloaded.
cmake_minimum_required(VERSION 3.24)
project(strata-dsv41 VERSION 0.1.59.1 LANGUAGES CXX)
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/strata_ggml.cmake)   # the vendored ggml (ggml-base, ggml-cpu)
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/cpu_kernels.cmake)   # strata_kernels_cpu: the CPU expert rows
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/cuda.cmake)          # NVIDIA toolchain
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/dsv41.cmake)         # the engine and its tests

add_compile_definitions(STRATA_VERSION="${PROJECT_VERSION}")
# release builds keep a PDB beside the exe, so a minidump from a stalled engine can be read back to the source line
if(MSVC AND CMAKE_BUILD_TYPE STREQUAL "Release")
  add_compile_options($<$<COMPILE_LANGUAGE:CXX>:/Zi>)
  add_link_options(/DEBUG /OPT:REF /OPT:ICF)
endif()

# A build for other PCs: ggml-cpu for any AVX2 CPU instead of this machine's (the engine's own AVX-512 kernels are per file
# and chosen at run time either way), and the MSVC runtime linked in, so no Visual C++ redistributable is needed.
option(STRATA_PORTABLE "build for other PCs: AVX2 baseline, static MSVC runtime" OFF)
# EXPERIMENTAL: an engine for CPUs without AVX2, compiled on that PC: ggml-cpu is built for "avx" (AVX, no FMA/F16C/AVX2)
# or "none" (SSE4.2 + POPCNT).  The engine's own AVX2/AVX-512 kernels stay in the binary behind their CPU checks.
set(STRATA_ISA_FLOOR "" CACHE STRING "experimental older-CPU build: empty (default, AVX2 floor), avx, or none (SSE4.2)")
set_property(CACHE STRATA_ISA_FLOOR PROPERTY STRINGS "" avx none)
if(NOT STRATA_ISA_FLOOR STREQUAL "" AND NOT STRATA_ISA_FLOOR STREQUAL "avx" AND NOT STRATA_ISA_FLOOR STREQUAL "none")
  message(FATAL_ERROR "STRATA_ISA_FLOOR must be empty, avx or none (got '${STRATA_ISA_FLOOR}')")
endif()
if(STRATA_ISA_FLOOR AND STRATA_PORTABLE)
  message(FATAL_ERROR "STRATA_ISA_FLOOR (an older-CPU build) and STRATA_PORTABLE (the AVX2 release build) exclude each other")
endif()
if(STRATA_PORTABLE AND MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded")
endif()

# The AVX kernels exist for x86 only; on aarch64 portable.cpp stands in for them and ggml-cpu's NEON dots do the CPU experts.
if(NOT CMAKE_SYSTEM_PROCESSOR OR CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64|amd64|x64|X64|i[3-6]86|x86|X86)$")
  set(STRATA_CPU_X86 ON)
else()
  set(STRATA_CPU_X86 OFF)
endif()
if(STRATA_ISA_FLOOR AND NOT STRATA_CPU_X86)
  message(WARNING "STRATA_ISA_FLOOR is an x86 older-CPU build and does not apply to ${CMAKE_SYSTEM_PROCESSOR}; ignored")
  set(STRATA_ISA_FLOOR "" CACHE STRING "" FORCE)
endif()
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

option(STRATA_ENABLE_CUDA "Build the engine for NVIDIA GPUs (CUDA)" OFF)
option(STRATA_ENABLE_HIP "Build the engine for AMD GPUs (HIP, wave32: gfx1100, gfx1201, ...)" OFF)
option(STRATA_BUILD_TESTS "Build the DeepSeek tests and benchmarks (tests/dsv41)" OFF)
if(STRATA_ENABLE_CUDA AND STRATA_ENABLE_HIP)
  message(FATAL_ERROR "STRATA_ENABLE_CUDA and STRATA_ENABLE_HIP are separate backends; enable only one")
endif()
if(STRATA_ENABLE_HIP)
  include(cmake/hip_backend.cmake)
endif()

if(STRATA_ENABLE_CUDA)
  strata_cuda_toolchain()
elseif(STRATA_ENABLE_HIP)
  set(_strata_gpu_runtime_target strata_hip_runtime)
  set(_strata_gpu_blas_target ${STRATA_HIP_BLAS_TARGETS})
  set(_strata_gpu_include_directories ${STRATA_HIP_COMPAT_INCLUDE_DIR})
endif()

# ggml-base / ggml-cpu (vendored), then the CPU kernels that use them
strata_ggml_resolve("${CMAKE_CURRENT_SOURCE_DIR}")
enable_language(C)
strata_ggml_configure_root()
strata_cpu_kernels()

if(STRATA_ENABLE_CUDA OR STRATA_ENABLE_HIP)
  strata_dsv41_engine()
else()
  # no GPU toolkit: only the host-side benchmark of the CPU lane can be built
  message(STATUS "strata-dsv41: neither STRATA_ENABLE_CUDA nor STRATA_ENABLE_HIP is on - building the CPU-lane benchmark (ds4_gg_bench) only")
  strata_dsv41_host_bench()
endif()
