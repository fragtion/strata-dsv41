# cmake/cuda.cmake - the NVIDIA toolchain of the engine.  A macro: it runs in the caller's scope.
macro(strata_cuda_toolchain)
  # The default has to be set BEFORE enable_language(CUDA): that call fills an unset CMAKE_CUDA_ARCHITECTURES with nvcc's
  # own default.  -DCMAKE_CUDA_ARCHITECTURES and the CUDAARCHS environment variable win.
  set(_strata_cuda_arch_defaulted OFF)
  if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES AND NOT DEFINED ENV{CUDAARCHS})
    # upstream's release shape for this engine: SASS for sm_86 / sm_89 / sm_120 and PTX for 120, so the engine runs on an
    # RTX 30, 40 or 50 card
    set(CMAKE_CUDA_ARCHITECTURES "86-real;89-real;120" CACHE STRING "CUDA architectures")
    set(_strata_cuda_arch_defaulted ON)
  endif()
  enable_language(CUDA)
  # enable_language(CUDA) gives the .cu compile rules but not the imported targets (CUDA::cudart, CUDA::cublas)
  find_package(CUDAToolkit REQUIRED)
  if(_strata_cuda_arch_defaulted)
    message(STATUS "strata-dsv41: CMAKE_CUDA_ARCHITECTURES was not set, building for ${CMAKE_CUDA_ARCHITECTURES}. For one card only "
                   "pass it, for example -DCMAKE_CUDA_ARCHITECTURES=86 (RTX 30), 89 (RTX 40), 120 (RTX 50) or native.")
  endif()
  foreach(_a IN LISTS CMAKE_CUDA_ARCHITECTURES)
    string(REGEX REPLACE "-.*$" "" _base "${_a}")     # 120-real / 120-virtual are still 120
    if(_base STREQUAL "native" OR _base STREQUAL "all" OR _base STREQUAL "all-major")
      continue()
    endif()
    # exl3.cu has decode kernels for older cards (vendor/exl3_legacy.cu), but this engine was only run on sm_80 and newer
    if(_base LESS 75)
      message(WARNING "Building for sm_${_base}: the DeepSeek engine was only run on compute capability 8.0 and newer.")
    endif()
    if(_base GREATER_EQUAL 120 AND CMAKE_CUDA_COMPILER_VERSION VERSION_LESS 13.0)
      message(WARNING "Building for sm_${_base} (RTX 50) with CUDA ${CMAKE_CUDA_COMPILER_VERSION}: upstream's engines built with "
                      "CUDA 12.8 crashed on long prompts on these cards. Use CUDA 13.0 or newer.")
    endif()
  endforeach()
  message(STATUS "strata-dsv41: CUDA enabled, arch ${CMAKE_CUDA_ARCHITECTURES}")
  set(_strata_gpu_runtime_target CUDA::cudart)
  set(_strata_gpu_blas_target CUDA::cublas)
  set(_strata_gpu_include_directories ${CMAKE_CUDA_TOOLKIT_INCLUDE_DIRECTORIES})
endmacro()
