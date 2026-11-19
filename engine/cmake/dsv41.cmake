# cmake/dsv41.cmake - the DeepSeek-V4.1-Flash engine (src/dsv41, from Project Maya's maya-ds4, MIT, third_party/project-maya) and its
# tests.  Macros: they run in the caller's scope.

# the engine for CUDA or HIP, and (STRATA_BUILD_TESTS) its tests
macro(strata_dsv41_engine)
  find_package(Threads REQUIRED)
  # the vendored kernels (EXL3 decode, the sampler, the MoE window) in their own library, namespace strata::dsv41k
  add_library(strata_dsv41_kernels STATIC src/dsv41/vendor/exl3.cu src/dsv41/vendor/sampler.cu src/dsv41/vendor/moe_win.cu
              src/dsv41/vendor/exl3_cpu.cpp)
  if(NOT STRATA_ENABLE_HIP)   # (the pre-sm_80 NVIDIA decode kernels exl3.cu dispatches to)
    target_sources(strata_dsv41_kernels PRIVATE src/dsv41/vendor/exl3_legacy.cu)
  endif()
  target_include_directories(strata_dsv41_kernels PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include ${_strata_gpu_include_directories})
  target_link_libraries(strata_dsv41_kernels PUBLIC ${_strata_gpu_runtime_target})

  add_executable(strata-dsv41 src/dsv41/ds4_main.cpp src/dsv41/ds4_model.cu src/dsv41/ds4_kernels.cu src/dsv41/ds4_vision.cu
                 src/dsv41/ds4_gguf.cu src/dsv41/ds4_gguf_cpu.cpp src/dsv41/ds4_iq.cu src/dsv41/ds4_iq_cpu.cpp
                 src/dsv41/ds4_tq.cu src/dsv41/ds4_tq_cpu.cpp src/dsv41/ds4_gg_cpu.cpp src/dsv41/ds4_packinfo.cpp src/platform/io_priority.cpp)
  # the commit the binary was built from, readable with --version (set -DSTRATA_BUILD_ID=... for a tree without .git)
  if(NOT STRATA_BUILD_ID AND EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/BUILD_ID)   # (a source archive has no .git: write the commit here)
    file(STRINGS ${CMAKE_CURRENT_SOURCE_DIR}/BUILD_ID STRATA_BUILD_ID LIMIT_COUNT 1)
  endif()
  if(NOT STRATA_BUILD_ID)
    execute_process(COMMAND git -C ${CMAKE_CURRENT_SOURCE_DIR} rev-parse --short=9 HEAD OUTPUT_VARIABLE STRATA_BUILD_ID
                    OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
  endif()
  if(NOT STRATA_BUILD_ID)
    set(STRATA_BUILD_ID unknown)
  endif()
  set_source_files_properties(src/dsv41/ds4_main.cpp PROPERTIES COMPILE_DEFINITIONS "DS4_BUILD_ID=\"${STRATA_BUILD_ID}\"")
  target_include_directories(strata-dsv41 PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include ${_strata_gpu_include_directories}
                             ${CMAKE_CURRENT_SOURCE_DIR}/third_party/ggml ${CMAKE_CURRENT_SOURCE_DIR}/src/prefill)
  target_link_libraries(strata-dsv41 PRIVATE strata_dsv41_kernels strata_kernels_cpu ${_strata_gpu_runtime_target}
                        ${_strata_gpu_blas_target} Threads::Threads)
  # the CPU lane's trellis experts run on Strata's CPU trellis kernels (tq_cpu.hpp)
  target_compile_definitions(strata-dsv41 PRIVATE STRATA_DSV41_TQ_CPU=1)
  if(STRATA_ENABLE_HIP)
    # the RDNA3 WMMA dense GEMM (strata_pf_gemm_f16_ld), which the chunked prompt prefers over hipBLAS on gfx11 (upstream
    # measured 4.97 -> 20-40 TFLOPS on gfx1151)
    target_sources(strata-dsv41 PRIVATE src/prefill/wmma_gemm.cu)
    if(WIN32)
      # cudaMemGetInfo is the DXGI-budgeted hip_compat::mem_get_info (src/core/device.cu): on a Strix Halo the carve-out is not
      # all the GPU may use, and the engine sizes its expert tiers by what the budget says is free
      target_sources(strata-dsv41 PRIVATE src/core/device.cu)
    endif()
    foreach(_t strata_dsv41_kernels strata-dsv41)
      target_compile_options(${_t} PRIVATE "$<$<COMPILE_LANGUAGE:HIP,CXX>:SHELL:-include ${CMAKE_CURRENT_SOURCE_DIR}/include/strata/dsv41/hip_extra.h>")
    endforeach()
  endif()

  if(STRATA_BUILD_TESTS)
    strata_dsv41_tests()
  endif()
endmacro()

# the CPU-lane benchmark alone (a PC with no GPU toolkit): ggml-cpu's dots against Strata's AVX2 i-quant rows; no GPU, no model
macro(strata_dsv41_host_bench)
  find_package(Threads REQUIRED)
  add_executable(ds4_gg_bench tests/dsv41/gg_dot_bench.cpp src/dsv41/ds4_gg_cpu.cpp)
  target_include_directories(ds4_gg_bench PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include ${CMAKE_CURRENT_SOURCE_DIR}/src/dsv41
                             ${CMAKE_CURRENT_SOURCE_DIR}/third_party/ggml)
  target_link_libraries(ds4_gg_bench PRIVATE strata_kernels_cpu Threads::Threads)
  target_compile_definitions(ds4_gg_bench PRIVATE STRATA_DSV41_TQ_CPU=1)
endmacro()

# the tests and benchmarks of tests/dsv41
macro(strata_dsv41_tests)
  enable_testing()
  if(STRATA_ENABLE_HIP)
    set(_ds4_test_lang HIP)
  else()
    set(_ds4_test_lang CUDA)
  endif()
  set(_ds4_hip_extra "$<$<COMPILE_LANGUAGE:HIP,CXX>:SHELL:-include ${CMAKE_CURRENT_SOURCE_DIR}/include/strata/dsv41/hip_extra.h>")

  strata_dsv41_host_bench()
  # the PCIe lane's cost model on this CPU (Project Maya #312's tests/ds4_lane_bench): no GPU, no model
  add_executable(ds4_lane_bench tests/dsv41/ds4_lane_bench.cpp src/dsv41/ds4_gguf_cpu.cpp src/dsv41/ds4_iq_cpu.cpp
                 src/dsv41/ds4_tq_cpu.cpp src/dsv41/ds4_gg_cpu.cpp)
  target_include_directories(ds4_lane_bench PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include ${CMAKE_CURRENT_SOURCE_DIR}/src/dsv41
                             ${CMAKE_CURRENT_SOURCE_DIR}/third_party/ggml)
  target_link_libraries(ds4_lane_bench PRIVATE strata_dsv41_kernels strata_kernels_cpu Threads::Threads)
  target_compile_definitions(ds4_lane_bench PRIVATE STRATA_DSV41_TQ_CPU=1)

  # the GGUF kernels against a double-precision reference, the PCIe lane's streamed experts against the VRAM ones' bit for bit
  # (--lane), and the packed KV caches against the BF16 rows; needs a GPU, no model
  add_executable(ds4_gguf_test tests/dsv41/ds4_gguf_test.cu src/dsv41/ds4_gguf.cu src/dsv41/ds4_gguf_cpu.cpp
                 src/dsv41/ds4_iq.cu src/dsv41/ds4_iq_cpu.cpp src/dsv41/ds4_kernels.cu src/dsv41/ds4_tq.cu
                 src/dsv41/ds4_tq_cpu.cpp src/dsv41/ds4_gg_cpu.cpp)
  target_include_directories(ds4_gguf_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include ${_strata_gpu_include_directories}
                             ${CMAKE_CURRENT_SOURCE_DIR}/third_party/ggml ${CMAKE_CURRENT_SOURCE_DIR}/src/prefill)
  target_link_libraries(ds4_gguf_test PRIVATE strata_dsv41_kernels strata_kernels_cpu ${_strata_gpu_runtime_target} Threads::Threads)
  target_compile_definitions(ds4_gguf_test PRIVATE STRATA_DSV41_TQ_CPU=1)

  # the router on a non-finite gate input (valid, distinct picks; the same picks as the host's top-k when finite); GPU, no model
  add_executable(ds4_route_guard_test tests/dsv41/ds4_route_guard_test.cu src/dsv41/ds4_kernels.cu)
  target_include_directories(ds4_route_guard_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include ${_strata_gpu_include_directories})
  target_link_libraries(ds4_route_guard_test PRIVATE strata_dsv41_kernels ${_strata_gpu_runtime_target} Threads::Threads)

  # the sampler's statistics harness (src/dsv41/sampler_stat.inc, the same file `strata-dsv41 --sampler-test` and the Metal engine
  # compile), so the backends' picks can be compared sample by sample.  NVIDIA only; GPU, no model.
  # usage: ds4_sampler_stat ROWS.bin N_VOCAB N_SAMPLES OUTPREFIX
  if(NOT STRATA_ENABLE_HIP)
    add_executable(ds4_sampler_stat src/dsv41/sampler_stat_main.cu)
    target_include_directories(ds4_sampler_stat PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include ${CMAKE_CURRENT_SOURCE_DIR}/src/dsv41
                               ${_strata_gpu_include_directories})
    target_compile_options(ds4_sampler_stat PRIVATE $<$<COMPILE_LANGUAGE:CUDA>:SHELL:-include ds4_launch.h>)
    target_link_libraries(ds4_sampler_stat PRIVATE ${_strata_gpu_runtime_target})
  endif()

  # the trellis experts (device kernels ds4_tq.cu, CPU lane ds4_tq_cpu.cpp) against a double reference; GPU, no model.
  # Both test .cpp files launch kernels, so they compile as HIP on AMD and as CUDA on NVIDIA.
  set_source_files_properties(tests/dsv41/tq_expert_test.cpp PROPERTIES LANGUAGE ${_ds4_test_lang})
  add_executable(ds4_tq_test tests/dsv41/tq_expert_test.cpp src/dsv41/ds4_tq.cu src/dsv41/ds4_iq.cu src/dsv41/ds4_tq_cpu.cpp
                 src/dsv41/ds4_iq_cpu.cpp src/dsv41/ds4_gg_cpu.cpp ../terminal/tools/trellis/tqenc.cpp)
  # the same with the plain-FMA tile instead of the gfx12 WMMA one (what CUDA and gfx11 builds run)
  add_executable(ds4_tq_test_portable tests/dsv41/tq_expert_test.cpp src/dsv41/ds4_tq.cu src/dsv41/ds4_iq.cu src/dsv41/ds4_tq_cpu.cpp
                 src/dsv41/ds4_iq_cpu.cpp src/dsv41/ds4_gg_cpu.cpp ../terminal/tools/trellis/tqenc.cpp)
  target_compile_definitions(ds4_tq_test_portable PRIVATE DS4_TQ_PORTABLE=1)
  # the i-quant experts (ds4_iq.cu) against ggml's own decode of the same blocks and a double reference, device and CPU lane
  set_source_files_properties(tests/dsv41/iq_expert_test.cpp PROPERTIES LANGUAGE ${_ds4_test_lang})
  add_executable(ds4_iq_test tests/dsv41/iq_expert_test.cpp src/dsv41/ds4_iq.cu src/dsv41/ds4_iq_cpu.cpp
                 src/dsv41/ds4_gg_cpu.cpp src/dsv41/ds4_tq.cu src/dsv41/ds4_tq_cpu.cpp)
  foreach(_t ds4_tq_test ds4_tq_test_portable ds4_iq_test)
    target_include_directories(${_t} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include ${_strata_gpu_include_directories}
                               ${CMAKE_CURRENT_SOURCE_DIR}/third_party/ggml ${CMAKE_CURRENT_SOURCE_DIR}/src/kernels/cpu)
    target_link_libraries(${_t} PRIVATE strata_kernels_cpu ${_strata_gpu_runtime_target} Threads::Threads)
    target_compile_definitions(${_t} PRIVATE STRATA_DSV41_TQ_CPU=1)
    if(STRATA_ENABLE_HIP)
      target_compile_options(${_t} PRIVATE "${_ds4_hip_extra}")
    endif()
  endforeach()

  # the dense weights (ds4_iq.cu dequant_rows / mv / f16_rows, ds4_gguf.cu rows / mv, the chunk GEMM) against a CPU reference for
  # every dense type and shape; no ggml, no model (run_dq_test.sh / .ps1 runs it one process a type and kernel)
  set_source_files_properties(tests/dsv41/dq_dense_test.cpp PROPERTIES LANGUAGE ${_ds4_test_lang})
  add_executable(ds4_dq_test tests/dsv41/dq_dense_test.cpp src/dsv41/ds4_iq.cu src/dsv41/ds4_tq.cu src/dsv41/ds4_gguf.cu)
  target_include_directories(ds4_dq_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/include ${_strata_gpu_include_directories}
                             ${CMAKE_CURRENT_SOURCE_DIR}/third_party/ggml ${CMAKE_CURRENT_SOURCE_DIR}/src/dsv41)
  target_link_libraries(ds4_dq_test PRIVATE ${_strata_gpu_runtime_target} ${_strata_gpu_blas_target} Threads::Threads)
  target_compile_definitions(ds4_dq_test PRIVATE DQ_TEST_GGUF=1 DQ_TEST_GEMM=1)
  if(STRATA_ENABLE_HIP)
    target_sources(ds4_dq_test PRIVATE src/prefill/wmma_gemm.cu)
    target_compile_options(ds4_dq_test PRIVATE "${_ds4_hip_extra}")
  endif()

  # host-only rules, no GPU, no model: the kept conversations' .meta file and prefix matching (ds4_slotmeta.hpp), restore points
  # (ds4_marks.hpp), the staging ring's slots by the measured host link, the serve loop's event queue, the experts rule, the timing
  # pick's flow correction and the pick rule
  foreach(_n slot marks ring_link evt experts_rule path_policy pick_rule)
    add_executable(ds4_${_n}_test tests/dsv41/${_n}_test.cpp)
    target_include_directories(ds4_${_n}_test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src/dsv41)
    target_compile_features(ds4_${_n}_test PRIVATE cxx_std_17)
    add_test(NAME ds4_${_n}_test COMMAND ds4_${_n}_test)
  endforeach()
  target_link_libraries(ds4_evt_test PRIVATE Threads::Threads)
endmacro()
