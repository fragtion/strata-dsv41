# cmake/cpu_kernels.cmake - strata_kernels_cpu: the CPU expert rows the engine's CPU lane runs (Strata's AVX2 / AVX-512 kernels and
# ggml-cpu's dots).  A macro: it runs in the caller's scope.
#
# /arch:AVX512 (or -mavx512*) is set on the SOURCE, not the target, so the flag applies only to the file that needs it; the engine
# picks the kernels at run time from the CPU's features.
macro(strata_cpu_kernels)
if(STRATA_CPU_X86)
  add_library(strata_kernels_cpu STATIC src/kernels/cpu/expert.cpp src/kernels/cpu/pool.cpp
              src/kernels/cpu/expert_layout.cpp src/kernels/cpu/q2_avx2.cpp src/kernels/cpu/hadamard.cpp)
else()
  add_library(strata_kernels_cpu STATIC src/kernels/cpu/portable.cpp src/kernels/cpu/pool.cpp
              src/kernels/cpu/expert_layout.cpp src/kernels/cpu/hadamard.cpp)
endif()
target_include_directories(strata_kernels_cpu PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
# Only the kernel files get the AVX-512 / AVX2 flags; the pool and the probe run on any x86-64,
# and the engine picks the kernels at run time (cpu_avx512_ok).
if(MSVC)
  set_source_files_properties(src/kernels/cpu/expert.cpp PROPERTIES COMPILE_OPTIONS "/arch:AVX512")
  set_source_files_properties(src/kernels/cpu/q2_avx2.cpp PROPERTIES COMPILE_OPTIONS "/arch:AVX2")
else()
  # GCC/Clang spell it differently, and `-mavx512vnni` alone is not enough: VBMI is a separate feature bit.
  set_source_files_properties(src/kernels/cpu/expert.cpp
                              PROPERTIES COMPILE_OPTIONS "-mavx512f;-mavx512bw;-mavx512vl;-mavx512dq;-mavx512vnni;-mavx512vbmi;-mf16c;-mfma")
  set_source_files_properties(src/kernels/cpu/q2_avx2.cpp PROPERTIES COMPILE_OPTIONS "-mavx2;-mfma;-mf16c")
endif()
# AVX-VNNI (Alder Lake, Sapphire Rapids and later): the AVX-2 expert kernels' vpdpwssd / vpdpbusd copies (q2_avx2.cpp,
# iq_avx2.cpp; *_rows.inl), taken at run time where cpu_avxvnni_ok().  GCC and Clang compile only those functions with
# target("avxvnni") - never -mavxvnni on a file, which would let the compiler use it anywhere - and MSVC takes the
# intrinsics under /arch:AVX2.  A compiler without them (GCC < 11, Clang < 12) builds the files without the copies.
include(CheckCXXSourceCompiles)
if(MSVC)
  set(CMAKE_REQUIRED_FLAGS "/arch:AVX2")
else()
  set(CMAKE_REQUIRED_FLAGS "-mavx2 -mfma -mf16c")
endif()
check_cxx_source_compiles([=[
#include <immintrin.h>
#if defined(__GNUC__) || defined(__clang__)
__attribute__((target("avxvnni")))
#endif
static __m256i dots(__m256i a, __m256i b) { return _mm256_dpbusd_avx_epi32(_mm256_dpwssd_avx_epi32(a, a, b), a, b); }
int main() {
    volatile int x = 1;
    return _mm256_extract_epi32(dots(_mm256_set1_epi32(x), _mm256_set1_epi32(x)), 0) == 0;
}
]=] STRATA_HAVE_AVXVNNI_INTRINSICS)
unset(CMAKE_REQUIRED_FLAGS)
if(STRATA_HAVE_AVXVNNI_INTRINSICS)
  set(_strata_avxvnni STRATA_AVXVNNI=1)
else()
  set(_strata_avxvnni STRATA_AVXVNNI=0)
endif()
set_property(SOURCE src/kernels/cpu/q2_avx2.cpp APPEND PROPERTY COMPILE_DEFINITIONS ${_strata_avxvnni})
find_package(Threads REQUIRED)
target_link_libraries(strata_kernels_cpu PUBLIC Threads::Threads)
# the native (ggml-cpu) expert rows and the trellis kernels
target_sources(strata_kernels_cpu PRIVATE src/kernels/cpu/native_expert.cpp)
if(STRATA_CPU_X86)
  target_sources(strata_kernels_cpu PRIVATE src/kernels/cpu/iq_avx512.cpp src/kernels/cpu/iq_avx2.cpp
                                           src/kernels/cpu/kq_avx2.cpp src/kernels/cpu/kq_avx1.cpp src/kernels/cpu/q2_avx1.cpp
                                           src/kernels/cpu/iq_avx1.cpp src/kernels/cpu/nvfp4_avx512.cpp src/kernels/cpu/nvfp4_avx2.cpp
                                           src/kernels/cpu/tq_cpu.cpp src/kernels/cpu/tq_avx2.cpp src/kernels/cpu/tq_avx512.cpp)
else()
  # the trellis dispatcher alone (the DeepSeek engine's CPU lane and Gyro): tq_cpu.cpp runs its scalar rows when the x86 units are
  # not compiled (the Metal build does the same)
  target_sources(strata_kernels_cpu PRIVATE src/kernels/cpu/tq_cpu.cpp)
endif()
target_include_directories(strata_kernels_cpu PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/third_party/ggml)
if(MSVC)
  set_source_files_properties(src/kernels/cpu/iq_avx512.cpp src/kernels/cpu/nvfp4_avx512.cpp
                              PROPERTIES COMPILE_OPTIONS "/arch:AVX512")
  set_source_files_properties(src/kernels/cpu/iq_avx2.cpp PROPERTIES COMPILE_OPTIONS "/arch:AVX2")
  set_source_files_properties(src/kernels/cpu/kq_avx2.cpp PROPERTIES COMPILE_OPTIONS "/arch:AVX2")
  set_source_files_properties(src/kernels/cpu/nvfp4_avx2.cpp PROPERTIES COMPILE_OPTIONS "/arch:AVX2")
  set_source_files_properties(src/kernels/cpu/tq_avx2.cpp PROPERTIES COMPILE_OPTIONS "/arch:AVX2")
  set_source_files_properties(src/kernels/cpu/tq_avx512.cpp PROPERTIES COMPILE_OPTIONS "/arch:AVX512")
  # the router lookahead's AVX1 dot (older CPUs; called behind cpu_avx1_ok): no FMA, no 256-bit integer ops
  set_source_files_properties(src/kernels/cpu/kq_avx1.cpp PROPERTIES COMPILE_OPTIONS "/arch:AVX")
  # the older CPUs' Q2_0 rows and activation quantizer (q2_avx1.cpp, issue #1699): 128-bit integer lanes,
  # no FMA/F16C, its own #error guard; called only behind cpu_avx1_ok() && !cpu_avx2_ok()
  set_source_files_properties(src/kernels/cpu/q2_avx1.cpp PROPERTIES COMPILE_OPTIONS "/arch:AVX")
  # the older CPUs' i-quant expert rows (iq_avx1.hpp): 128-bit SSSE3/SSE2 integer, SSE2 float, no FMA/F16C
  set_source_files_properties(src/kernels/cpu/iq_avx1.cpp PROPERTIES COMPILE_OPTIONS "/arch:AVX")
else()
  set_source_files_properties(src/kernels/cpu/iq_avx512.cpp src/kernels/cpu/nvfp4_avx512.cpp PROPERTIES COMPILE_OPTIONS
                              "-mavx512f;-mavx512bw;-mavx512vl;-mavx512dq;-mavx512vnni;-mavx512vbmi;-mavx512vpopcntdq;-mbmi2;-mf16c;-mfma")
  set_source_files_properties(src/kernels/cpu/iq_avx2.cpp PROPERTIES COMPILE_OPTIONS "-mavx2;-mfma;-mf16c")
  set_source_files_properties(src/kernels/cpu/kq_avx2.cpp PROPERTIES COMPILE_OPTIONS "-mavx2;-mfma;-mf16c")
  set_source_files_properties(src/kernels/cpu/nvfp4_avx2.cpp PROPERTIES COMPILE_OPTIONS "-mavx2;-mfma;-mf16c")
  # the trellis kernels: AVX2 + FMA, and AVX-512 F/BW/VL/VBMI/VNNI (exactly what cpu_avx512_ok() checks)
  set_source_files_properties(src/kernels/cpu/tq_avx2.cpp PROPERTIES COMPILE_OPTIONS "-mavx2;-mfma;-mf16c")
  set_source_files_properties(src/kernels/cpu/tq_avx512.cpp PROPERTIES COMPILE_OPTIONS
                              "-mavx512f;-mavx512bw;-mavx512vl;-mavx512vnni;-mavx512vbmi;-mavx2;-mfma;-mf16c")
  set_source_files_properties(src/kernels/cpu/kq_avx1.cpp PROPERTIES COMPILE_OPTIONS "-mavx")
  # the older CPUs' Q2_0 rows and activation quantizer (q2_avx1.cpp, issue #1699): SSE4.2 + AVX with
  # AVX2/FMA/F16C explicitly off, so a -march=native build host cannot leak AVX2 code into the file that
  # runs on a Sandy Bridge Xeon
  set_source_files_properties(src/kernels/cpu/q2_avx1.cpp PROPERTIES COMPILE_OPTIONS
                              "-msse4.2;-mavx;-mno-avx2;-mno-fma;-mno-f16c")
  # the older CPUs' i-quant expert rows (iq_avx1.hpp): SSE4.2 + AVX with AVX2/FMA/F16C explicitly off, so a
  # -march=native build host cannot leak AVX2 code into the file that runs on a Sandy Bridge Xeon
  set_source_files_properties(src/kernels/cpu/iq_avx1.cpp PROPERTIES COMPILE_OPTIONS
                              "-msse4.2;-mavx;-mno-avx2;-mno-fma;-mno-f16c")
endif()
set_property(SOURCE src/kernels/cpu/iq_avx2.cpp APPEND PROPERTY COMPILE_DEFINITIONS ${_strata_avxvnni})
if(STRATA_ISA_FLOOR STREQUAL "avx")
  target_compile_definitions(strata_kernels_cpu PRIVATE STRATA_ISA_FLOOR_AVX=1)
elseif(STRATA_ISA_FLOOR STREQUAL "none")
  target_compile_definitions(strata_kernels_cpu PRIVATE STRATA_ISA_FLOOR_NONE=1)
endif()
target_link_libraries(strata_kernels_cpu PUBLIC ggml-cpu ggml-base)
target_compile_definitions(strata_kernels_cpu PUBLIC STRATA_NATIVE_EXPERTS=1)
endmacro()
