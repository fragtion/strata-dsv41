@echo off
rem build-dsv41.bat: builds the DeepSeek-V4.1-Flash engine (strata-dsv41.exe) from this checkout on Windows with an NVIDIA card.
rem
rem   build-dsv41.bat
rem   set DSV41_ARCH=86-real & build-dsv41.bat          only your card's code (faster build): 86 RTX 30, 89 RTX 40, 120 RTX 50
rem
rem Needs: Visual Studio 2022 (any edition, or the Build Tools) with the C++ workload, the CUDA 13.0 toolkit, CMake 3.24+ and
rem Ninja. CMake and Ninja are taken from this folder's .venv when they are there
rem (python -m pip install -r requirements-build.txt), otherwise from PATH.
rem llama.cpp's ggml is vendored in third_party\strata-ggml, so nothing is downloaded and STRATA_GGML_DIR is not needed.
rem
rem Settings (all optional):
rem   DSV41_ARCH   CUDA architectures, default "86-real;89-real;120" (upstream's release set: SASS for sm_86/89/120, PTX for 120)
rem   CUDA_ROOT    default C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.0
rem   BUILD_JOBS   default: the number of logical processors
rem
rem Result: engine-dsv41\<version>-windows-x86_64-cuda-cuda13-src\strata-dsv41.exe, with cublas64_13.dll and cublasLt64_13.dll
rem copied from CUDA (cudart is static). The compiler log is build-dsv41\build.log.
setlocal
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "BD=%ROOT%\build-dsv41"
if "%CUDA_ROOT%"=="" set "CUDA_ROOT=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.0"
if "%DSV41_ARCH%"=="" set "DSV41_ARCH=86-real;89-real;120"
if "%BUILD_JOBS%"=="" set "BUILD_JOBS=%NUMBER_OF_PROCESSORS%"
if not exist "%CUDA_ROOT%\bin\nvcc.exe" ( echo   no nvcc.exe in %CUDA_ROOT%\bin: install CUDA 13.0 or set CUDA_ROOT & exit /b 2 )

set "CMAKE=cmake"
set "NINJA=ninja"
if exist "%ROOT%\.venv\Scripts\cmake.exe" set "CMAKE=%ROOT%\.venv\Scripts\cmake.exe"
if exist "%ROOT%\.venv\Scripts\ninja.exe" set "NINJA=%ROOT%\.venv\Scripts\ninja.exe"
"%CMAKE%" --version >nul 2>&1 || ( echo   CMake not found: python -m pip install -r requirements-build.txt into .venv, or put cmake on PATH & exit /b 2 )

rem Visual Studio 2022's C++ environment (vswhere finds any edition and the Build Tools)
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
set "VSDIR="
if exist "%VSWHERE%" for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -version [17.0^,18.0^) -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%I"
if "%VSDIR%"=="" ( echo   Visual Studio 2022 with the C++ workload was not found & exit /b 2 )
call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul || ( echo   vcvars64.bat failed & exit /b 2 )

mkdir "%BD%" 2>nul
rem the MSVC linker writes large temporary files; a TEMP it cannot write fails with LNK1104
mkdir "%BD%\tmp" 2>nul
set "TEMP=%BD%\tmp"
set "TMP=%BD%\tmp"

rem configure every time: the build id (the git commit) is baked in at configure time
"%CMAKE%" -G Ninja "-DCMAKE_MAKE_PROGRAM=%NINJA%" -S "%ROOT%" -B "%BD%" -DCMAKE_BUILD_TYPE=Release ^
  -DSTRATA_ENABLE_CUDA=ON -DSTRATA_BUILD_TESTS=OFF -DSTRATA_PORTABLE=ON ^
  "-DCMAKE_CUDA_ARCHITECTURES=%DSV41_ARCH%" "-DCMAKE_CUDA_COMPILER=%CUDA_ROOT%\bin\nvcc.exe" "-DCUDAToolkit_ROOT=%CUDA_ROOT%" || goto :fail
if exist "%BD%\strata-dsv41.exe" del /q "%BD%\strata-dsv41.exe"
echo   Building strata-dsv41 for %DSV41_ARCH% with %BUILD_JOBS% jobs - compiler output: %BD%\build.log
"%CMAKE%" --build "%BD%" -j %BUILD_JOBS% --target strata-dsv41 > "%BD%\build.log" 2>&1 || goto :fail
if not exist "%BD%\strata-dsv41.exe" goto :fail

for /f "delims=" %%V in ('"%BD%\strata-dsv41.exe" --version') do set "VERLINE=%%V"
echo   %VERLINE%
set "VER="
for /f "tokens=2" %%A in ("%VERLINE%") do set "VER=%%A"
if "%VER%"=="" set "VER=unknown"
set "OUT=%ROOT%\engine-dsv41\%VER%-windows-x86_64-cuda-cuda13-src"
mkdir "%OUT%" 2>nul
copy /y "%BD%\strata-dsv41.exe" "%OUT%\" >nul || goto :fail
for %%D in (cublas64_13.dll cublasLt64_13.dll) do (
  if exist "%CUDA_ROOT%\bin\x64\%%D" ( copy /y "%CUDA_ROOT%\bin\x64\%%D" "%OUT%\" >nul ) else copy /y "%CUDA_ROOT%\bin\%%D" "%OUT%\" >nul
)
echo   Engine ready: %OUT%\strata-dsv41.exe
exit /b 0

:fail
if exist "%BD%\build.log" findstr /i /c:" error " /c:"error C" /c:"error:" /c:"FAILED:" "%BD%\build.log"
echo   The build failed - see the messages above.
exit /b 1
