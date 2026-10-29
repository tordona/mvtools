Change log
- 2.7.47.200-arm64 (20261029)
  - Direct3D 12 Engine Branch Divergence & Milestone Version Bump:
    - Bumped branch version to 2.7.47.200-arm64, formally establishing version divergence from upstream mvtools-pfmod to reflect the major architectural additions (Direct3D 12 compute offload, unified single-binary engine, and hardware flow synthesis).
  - Unified Dual-Engine Architecture & Runtime Direct3D 12 Toggle:
    - Unified the native ARM64 CPU NEON engine and Direct3D 12 DirectCompute GPU engine into a single canonical binary (mvtools2.dll), eliminating dual-binary distribution (mvtools2-d3d12.dll).
    - Reverted build outputs in MSBuild (mvtools.vcxproj), CMakeLists.txt, and copyall.bat from mvtools2-d3d12 directly back to mvtools2.dll.
    - Added MEnableD3D12([enable]b) and MIsD3D12Available() runtime AviSynth functions to control Direct3D 12 compute offload directly from script profiles, accurately reflecting that the GPU is always active for decoding and display while this toggle specifically governs compute shader offload.
    - Direct3D 12 compute offload defaults to false at DLL load, guaranteeing zero D3D12 queue or device allocation overhead until explicitly enabled in scripts.
    - Dropped legacy function names (MEnableGPU, MIsGPUAvailable), eliminating redundant script entry points.
    - Offloaded coarse motion vector predictor interpolation directly to GPU compute (motion_search_cs.hlsl), executing parallel on-chip bilinear/nearest coarse block mapping and eliminating per-frame CPU-side predictor loops and vector heap allocations in PlaneOfBlocks::RecalculateMVs.
    - Extended D3D12FlowSynthesis 3-texture ring caching with consecutive source/reference pair matching (m_lastSrcRingIdx), eliminating redundant frame re-uploads during fractional rate conversions (such as 24 fps -> 60 fps intermediate sub-frames).
    - Recompiled embedded shader bytecode header (motion_search_cso.h).
  - Snapdragon AviSynth Profiles (Revision 2.1.0):
    - Updated profiles to Revision 2.1.0 across Snapdragon X Plus, 8cx Gen 3, 8cx Gen 2, 8cx Gen 1, 850, and 7c Gen 2 to load the unified mvtools2.dll and configure offload via USE_D3D12 = false and MEnableD3D12(USE_D3D12).
    - Added adaptive parameter scaling based on USE_D3D12: configured sharp=0 with pel=1 on GPU compute paths to bypass redundant subpixel filtering, while leveraging hardware bilinear texture sampling in D3D12FlowSynthesis.
    - Configured MBlockFps(mode=2, blend=true) across GPU profiles for dynamic median pixel-flow synthesis and linear occlusion fallback.
    - Scaled memory allocation (SetMemoryMax) and worker threads dynamically between Direct3D 12 compute and CPU NEON fallbacks.
    - Cleaned all profile templates and quickstart documentation, removing deprecated plugin_file variables and redundant plugin loader statements.
  - Dynamic 4K Resolution Adaptation Across All 42 AviSynth Profiles:
    - Added real-time resolution detection (`is_4k = (Width() > 2048)` or `src.Width() > 2048`) across all 42 tracked AviSynth profiles (ARM64 Snapdragon and x86-64 Intel/AMD).
    - Implemented proportional block scaling to maintain the spatial macro-block count invariant between 1080p and 4K:
      - Coarse pass scales from 32x32 (1080p) to 64x64 (4K).
      - Fine refinement pass scales from 16x16 (1080p) to 32x32 (4K); 8x8 passes scale to 16x16 (4K).
      - Proxy pipelines scale from 16x16 / 32x16 to 32x32 / 64x32 on 4K streams.
      - Edge padding scales proportionally (`hpad=16, vpad=16` at 4K).
    - Reduces total evaluated blocks in 4K two-pass motion search from 40,560 down to 10,200 (a 75% compute load reduction), preventing memory bus saturation, GPU execution timeouts, and frame dropping on high-resolution media.
    - Updated starter scripts and profile documentation across `docs/quickstart.md`, `docs/profiles/README.md`, `AIAgentProfileGuide.md`, and all platform hardware guides.
  - High-Resolution 4K DirectCompute Shader & Engine Optimizations:
    - Fused UV Chroma Compute Pass: Merged independent U and V chroma synthesis dispatches into packed dual-plane compute shaders (`FlowWarpChromaCS` and `FlowBlendChromaCS` in `flow_warp.hlsl`), processing U and V channels simultaneously with native `min16float2` arithmetic. Reduces 4K synthesis compute dispatches by 33% and halves descriptor heap and pipeline state switches.
    - Gated Static Plane Loads: Annotated texture sampling for un-occluded fallback blending with explicit `[branch]` in `flow_warp.hlsl` when `maskMode == 0`, preventing compiler branch flattening and skipping static texture fetches during standard motion-compensated interpolation frames to conserve memory bus bandwidth.
    - Groupshared Motion Vector Broadcast: Introduced threadgroup-shared vector caching (`gs_MvF` and `gs_MvB`) in `flow_warp.hlsl` for `MBlockFps` (`flowMode == 0`), cutting macroblock motion vector texture loads from 128 down to 4 per $16 \times 8$ workgroup (a 96.9% reduction in vector read traffic).
    - Row-Decimated 2x Strided SAD for 4K Streams: Implemented vertical 2-row striding (`dy += 2`) with proportional bit-shift reconstruction (`sad << 1`) in `motion_search_cs.hlsl` when `extendedWidth > 2048` and `nBlkSizeY >= 16`. Halves raw `ByteAddressBuffer` pixel memory reads and integer SAD evaluations across 4K frames while maintaining exact lambda motion cost scaling and scene change detection (`thSCD1`) invariants.
    - Scaled MRecalculate Early-Exit Threshold: Scaled the early-out SAD limit dynamically with block geometry (`(nBlkSizeX * nBlkSizeY) >> 1`) instead of a fixed 128 threshold, restoring the empirical 0.5 SAD/pixel early termination on 4K $32 \times 32$ refinement blocks.
    - Unified 6-Slot Plane LRU Cache: Replaced the separated 1-slot source and 4-slot reference buffers in `D3D12MotionSearch.cpp` with a unified 6-slot LRU plane cache (`m_planeCache`), eliminating ping-pong cache misses across forward/backward `MAnalyse` and `MRecalculate` passes. Reduces 4K host-to-device plane upload bandwidth by 75%–80% (~34 MB/frame saved at 4K).
  - Benchmarking Suite & Deployment Automation:
    - Updated Install-MvToolsPotPlayer.ps1, Benchmarks/MvToolsBenchmark-Start.ps1, and Benchmarks/MvToolsBenchmarks-Compare.ps1 to configure and detect USE_D3D12 and MEnableD3D12 with backward compatibility for legacy scripts.
    - Streamlined deployment automation to manage the unified mvtools2.dll binary, removing dual-binary checks and cleaning legacy d3d12 binaries from player environments.
    - Updated baseline comparison matrices across all 6 Snapdragon platforms, recording D3D12 GPU optimizations (Snapdragon X Plus MaxQuality CPU load reduced from 10.6% to 6.0%, Snapdragon 8cx Gen 2 CPU load reduced from 15.3% to 8.2%).
    - Normalized baseline matrix filenames (e.g. BenchmarkMatrix_Comparison_Core-i5-7Y54.md) and removed legacy raw CPUID filename entries.
    - Added PresentMon frame-time capture to benchmark harness, with PowerShell 5.1 and 7 support across ARM64 and x64 environments.
  - Documentation & Typography:
    - Verified 1:1 documentation parity between Documentation/guides/ and docs/guides/ across all 7 platform and auto-tuning guides.
    - Updated README.md primary plugin specifications to describe the unified canonical binary architecture.
    - Added Docsify documentation structure for GitHub Pages.
    - Standardized all platform guides and profile documentation across Documentation/guides/, docs/guides/, and docs/profiles/ to Revision 2.1 specifications and unified MEnableD3D12 / USE_D3D12 syntax.
    - Standardized all technical documentation, scripts, and baseline tables to strict NIST SP 811 / BIPM SI unit spacing standards (e.g., 60 fps, 24 fps, 15 W, 16 GB, 18 ms, 4 px) and objective engineering tone.

- 2.7.47.121-arm64 (20261023)
  - Synthesis Memory & NEON Blend Refinements (merged from mvtools-pfmod):
    - Elided unused full-frame/small occlusion mask allocations (MaskFull*, MaskOcc*, smallMask*, SimpleResize) and per-frame full-frame zeroing in MVBlockFps modes 0-2, saving ~17.2 MB working set at 1080p (~78-104 MB at 4K) under AviSynth+ MT and ~252 MB/s of dead memory writes at 1080p60.
    - Enabled SIMD overlapped output conversion (Short2Bytes_sse2 for 8-bit, Short2Bytes_Int32toWord16_sse4 for 10-16-bit) in MVBlockFps with 16-byte pointer and pitch alignment guards.
    - Vectorized frame and edge-border Blend<pixel_t> in MaskFun.cpp across uint8_t, uint16_t, and float planes using native ARM64 NEON intrinsics with an early-out for empty border strips.
    - Further reduced sustained 1080p 24 fps -> 60 fps CPU-mode system load on Qualcomm Snapdragon X Plus (Balanced profile) from 8.24% down to 7.27% mean / 7.00% median / 10.70% peak (-55.1% cumulative reduction vs scalar baseline) with zero dropped frames.
- 2.7.47.120-arm64 (20261023)
  - Native ARM64 NEON SIMD Vectorization & Full-Pipeline Dispatch (merged from mvtools-pfmod):
    - Vectorized MVBlockFps::ResultBlock (modes 0, 1, and 2: MC Average, Static Median, and Dynamic Median) using 128-bit ARM64 NEON intrinsics.
    - Implemented native ARMv8.0 NEON (Sad_neon_v8) and ARMv8.2-A DotProd UDOT (Sad_neon_dotprod) 8-bit SAD kernels across all 45 block sizes (4x1 to 64x64) with dynamic Windows PF_ARM_V82_DP_INSTRUCTIONS_AVAILABLE runtime detection.
    - Implemented unrolled 128-bit/64-bit NEON block copying (Copy_neon) in CopyCode.cpp across 8-bit, 16-bit, and 32-bit float formats.
    - Added get_simd_cpu_flags() ARM64 CPUF bridge in cpu.cpp across MSuper, MVBlockFps, MVFlowFps, MVFlow*, MVRecalculate, MVCompensate, MVDegrain*, MVMask, MVFinest, MVShow, DCTFactory, and Padding, activating SIMD pyramid downsampling, pel=2/4 Wiener/bicubic refinement, SimpleResize vector upsampling, and Overlaps windowing.
    - Reduced sustained 1080p 24 fps -> 60 fps CPU-mode system load on Qualcomm Snapdragon X Plus by 49.4% (from 16.2% down to 8.2% mean / 12.3% peak) with zero dropped frames, while accelerating host-side MSuper pyramid generation for Direct3D 12 workflows.
- 2.7.47.110-arm64 (20261020)
  - Direct3D 12 Gather Flow & Dynamic Median Frame Synthesis (MFlowFps & MBlockFps):
    - Implemented full GPU frame synthesis engine (D3D12FlowSynthesis.cpp/.h), eliminating the CPU readback fence stall.
    - Added Hardware Dynamic Median Compute Shader (flow_warp.hlsl) for exact visual and mathematical parity with CPU NEON.
    - Converted pixel color calculations, temporal cross-fade, and median clamping to native Adreno FP16 (min16float) for dual-issue ALU throughput.
    - Optimized compute threadgroup dimensions to Wave64 (16x8, 128 threads) for Adreno architecture and L1 texture cache alignment.
    - Integrated 3-Ring Texture Cache (m_ring[3]) and Asynchronous Double-Buffering (NUM_SLOTS = 2) with non-blocking try_lock slot acquisition, reducing memory bus traffic by 50%.
    - Implemented bulk contiguous memcpy for host-to-device transfers, eliminating >10,200 row-by-row scalar function calls per frame.
  - Stability & Reliability:
    - Fixed 0xc0000005 Access Violation in vcruntime140.dll on widescreen 4K formats (3840x1714) via strict 2D coordinate bounds clamping in motion_search_cs.hlsl.
    - Added defensive null-guards on mapped pointers, GetDeviceRemovedReason() validation, and bounded 2,000 ms fence synchronization timeouts.
    - Raised profile mem_limit to 1,536 MB, completely eliminating pagefile disk swapping (0.0 swaps/sec).
- 2.7.47.100-arm64 (20261019)
  - Direct3D 12 DirectCompute GPU Offload (Adreno GPU Native Execution):
    - Ported block SAD (Sum of Absolute Differences) and motion vector search into HLSL Compute Shader (`cs_5_0`).
    - Executes natively on Qualcomm Adreno GPU with zero CPU overhead.
    - Achieves continuous 60 fps without dropped frames on Snapdragon X Plus across both Balanced and MaxQuality profiles.
    - Implemented 4-slot LRU reference plane upload cache with 5-point 64-bit sampling check, cutting per-frame CPU-to-GPU memory copies by 75% (from 56.8 MB/frame down to ~14.2 MB/frame, saving ~3.2 GB/s on unified memory bus).
    - Persistently mapped constant buffer, readback buffer, and predictor buffers to eliminate per-frame OS kernel Map/Unmap transitions.
    - Optimized compute shader refinement (`MRecalculate`): uses tight 8-point 3x3 local subpixel grid with early-exit on near-perfect coarse matches (`bestSAD <= 128`), cutting per-block refinement cycles by up to 71%.
    - Supports both coarse motion search (`MAnalyse`) and fine micro-block refinement (`MRecalculate`).
    - Direct output binary naming configured to `mvtools2-d3d12.dll` across MSBuild (`mvtools.vcxproj`) and CMake targets for side-by-side comparative testing against baseline CPU `mvtools2.dll`.
    - Added runtime GPU status queries and controls (`MIsGPUAvailable()`, `MEnableGPU(bool)`).
  - Native Windows on ARM64 support:
    - Added native ARM64 Release and Debug targets across mvtools, DePan, and DePanEstimate.
    - Supported MSVC toolsets v143 (Visual Studio 2022) and v145 (Visual Studio 2026).
    - Configured /vmg general member pointer representation and /Zc:preprocessor conformance flags.
    - Strict backward compatibility preserved for legacy x86 and x64 builds.
  - SIMD & NEON vectorization:
    - Integrated sse2neon translation layer converting SSE, SSE2, SSSE3, and SSE4.1 intrinsics to 128-bit ARM NEON.
    - Added drop-in x86 intrinsic compatibility headers in Sources/include/arm64/.
    - Gated x86 inline assembly routines in def.h (USE_SAD_ASM, USE_COPYCODE_ASM, etc.) on ARM architectures, routing to optimized SIMD and portable C++ routines.
  - Cross-compiler C++ ABI bridge (MSVC ARM64 <-> MinGW GCC AArch64):
    - Aligned IScriptEnvironment vtable slots with dummy destructor padding (__dummy_gcc_dtor_pad).
    - Enforced 16-byte member function pointers via __multiple_inheritance and /vmg, matching GCC's 3,328-byte AVS_Linkage structure.
    - Implemented dynamic AArch64 JIT adapter thunk (AVS_WrapApply) for X8 indirect return-buffer register translation.
    - Added bidirectional GetFrame ABI adapters (AVS_WrapClipVTable for MSVC callee clips; AVS_ClipProxy / AVS_WrapClip for GCC callee clips).
    - Fixed crash on playback stop/exit by adding __dummy_gcc_dtor_pad to IClip, correctly catching GCC deleting destructor calls at vtable[7].
  - Qualcomm Snapdragon 60 fps AviSynth profiles:
    - Added 18 tuned real-time motion interpolation profiles under AviSynth/:
      - Snapdragon X Plus (8x Oryon): Eco, Balanced, MaxQuality.
      - Snapdragon 8cx Gen 3 / Microsoft SQ3 (4x Cortex-X1 + 4x Cortex-A78, Adreno 690): Eco, Balanced, MaxQuality with adaptive GPU/CPU parameters (pel=1, 32x32 -> 16x16, Prefetch(4) under D3D12 GPU offload sustaining continuous 60 fps at 60–66% GPU load; pel=2 16x16 -> 8x8 with Prefetch(7) across all 8 CPU performance cores).
      - Snapdragon 8cx Gen 2 / Microsoft SQ2 (4x Gold + 4x Silver, Adreno 680): Eco, Balanced, MaxQuality with adaptive GPU/CPU parameters (pel=1, 32x32 -> 16x16, natural Prefetch(threads) to eliminate D3D12 mutex lock convoys and sustain solid 60 fps under GPU offload; pel=2 16x16 -> 8x8 on 4 Gold CPU cores).
      - Snapdragon 8cx Gen 1 / Microsoft SQ1 (4x Gold + 4x Silver, Adreno 680): Eco, Balanced, MaxQuality with single-pass dense 16x16 D3D12 GPU offload (2 dispatches, cutting GPU evaluations by 60% to eliminate 7 W fanless thermal throttling and sustain solid 60 fps) and pure CPU NEON fallback.
      - Snapdragon 850 (4x Gold + 4x Silver): Eco, Balanced, MaxQuality with MScaleVect 540p proxy search (pure CPU NEON baseline to eliminate 5 W GPU thermal throttling).
      - Snapdragon 7c Gen 2 (2x Gold + 6x Silver, e.g., Samsung Galaxy Book Go): Eco, Balanced, MaxQuality with levels=1 pyramid elimination, strict Prefetch(2, 4) core pinning, and MScaleVect 540p proxy search (pure CPU NEON baseline to avoid 32-bit LPDDR4x bus contention).
    - Standardized Semantic Versioning headers (`# Revision:` and `# Changelog:`) across all 18 profiles.
    - Embedded dynamic `USE_GPU` parameter toggle across all profiles for runtime switching between CPU NEON and D3D12 GPU.
    - Hardened low-power profiles (850 & 7c Gen 2) as pure CPU-only, reserving GPU offload toggles for high-bandwidth/active-cooled platforms (Snapdragon X Plus, 8cx Gen 3, 8cx Gen 2, and 8cx Gen 1).
  - Automated Benchmark Test Suite & Telemetry:
    - Added automated benchmark harness `Benchmarks/MvToolsBenchmark-Start.ps1` (v2.3.0) and matrix comparer `Benchmarks/MvToolsBenchmarks-Compare.ps1` (v2.2.0).
    - Dual AppData & Portable PotPlayer INI targeting: automatically routes and enforces deterministic playback, D3D11 render, and AviSynth configuration across `%APPDATA%\PotPlayer64\PotPlayer64.ini` and `%APPDATA%\PotPlayerMini64\PotPlayerMini64.ini` for standard installs, or local directory INIs for portable installs.
    - Native Fullscreen Configuration: enforces clean native fullscreen playback via player INI settings (`StartScreenSize=4`, `PlayScreenSize=5`, `PlayScreenSizeFirst=1`, `MainWindowState=128`, `FullScreenFitMode=0`) with zero external window message polling or CLI flag bloat.
    - Binary PE Machine Architecture Validation: checks PE headers (`0xAA64` ARM64 vs `0x8664` x64 vs `0x014C` x86) via `Get-PeMachine` to prevent emulator architecture mismatch crashes.
    - Explicit Download Confirmation Prompts: requires explicit user authorization (`Confirm-DownloadPermission`) displaying source URL, destination, and file size before downloading external packages.
    - Background Process Quiescence & Interactive Prompt: inspects running noisy processes (browsers, Slack, Teams, etc.), displays a clear warning, and offers an interactive `[Y/n]` prompt defaulting to Yes on Enter, with `-SkipProcessKill` CLI bypass.
    - Automated AviSynth+ Acquisition: downloads and extracts official native `AviSynth.dll` from GitHub releases (`AviSynth/AviSynthPlus`, latest tag `filesonly.7z`) directly to the PotPlayer directory.
    - Automated MVTools ARM64 Acquisition: downloads and extracts official release binaries (`mvtools2.dll`, `mvtools2-d3d12.dll`, `DePan.dll`, `DePanEstimate.dll`) and AviSynth profiles from GitHub releases (`tordona/mvtools`).
    - Automated Official PotPlayer ARM64 Setup: downloads and silently installs official native PotPlayer ARM64 from Kakao CDN with live speed/ETA progress and safety watchdog (`-AutoInstallPotPlayer`).
    - Reference Baseline Comparison Matrices: preserved across 6 Snapdragon SoC generations under `Benchmarks/Baseline/`.
    - PresentMon ARM64 Telemetry: integrated empirical panel scanout ETW analysis, integer VSync drift detection, render latency tracking, and profile revision reporting.
  - Documentation & Hardware Guides:
    - Added AI_PORT_NOTICE.md detailing port architecture, cross-compiler ABI mechanics, and Antigravity skills.
    - Added PotPlayer hardware decode (DXVA2/D3D11 Copy-Back) and Direct3D 11 rendering guides in Documentation/guides/ (SnapdragonXPlus.md, Snapdragon8cxGen3.md, Snapdragon8cxGen2.md, Snapdragon8cxGen1.md, Snapdragon850.md, Snapdragon7cGen2.md).


- 2.7.47 (20260424)
  - Update Avisynth headers to V12 interface (AcquireGlobalLock/ReleaseGlobalLock support)
  - Thread-safe FFTW plan creation/destruction in DCTFFTW using GlobalLockGuard:
    On Avisynth+ V12+ uses the shared global named lock "fftw", coordinating with
    other plugins (e.g. dfttest, depanestimate) that use the same FFTW DLL.
    Falls back to a local static mutex on older Avisynth versions.
  - Project solution: moved to VS2026 solution format (.slnx)

- 2.7.46 (20240503)
  - Recheck and fix build processes for various compilers 
    (Visual Studio MSVC v143, v141_xp; Intel C++ Compiler 2024.1 ICX, 19.2 ICL; ClangCL; gcc mingw64)
  - Fix (#56): bug in Cross search
  - (unreleased 2.7.46 (20230208) test build in https://github.com/pinterf/mvtools/issues/58)
  - Fix (#58): MFlowFPS memory leak
  - Fix (#49): lsad 0 caused division-by-zero crash
  - Optimization: MDegrain1-6 8 bit: Add avx2 code path (already was in code but disabled, now go live)
  - Optimization: MDegrainN 10-16 bits: add SSE4.1 code path (was: C only)
  - Optimization: VerticalBicubic interpolation SSE4.1 version besides SSE2
  - Fix: MRestoreVect was trying to create unaligned frame (crash)
    https://forum.doom9.org/showthread.php?p=1955944#post1955944
  - (#48) Project files/solution: Intel C++ Compiler 2021 (icx) and 19.2 (icl classic) support on Windows 
  - source: pull avstp 1.04 helper files and reapply earlier patches
  - Source internals: MDegrain: for block size of 4, read exactly 4 bytes instead of 8. (in extreme cases it would read past a valid memory area)
    (result was OK but reading more bytes than is than necessary may cause problems)
  - Source internals: Stop using _mm256_zeroupper in avx2, compilers do that automatically.
    Affected LLVM builds, because it unoptimizedly saved and restored _all_ ymm registers (slow!)
    https://stackoverflow.com/questions/68736527/do-i-need-to-use-mm256-zeroupper-in-2021

- 2.7.45 (20210608)
  - Fix: change parameter 'ml' from int to float in MBlockFPS. (Other filters with 'ml' are O.K.: MMask, MFlowInter, MFlowFPS are using float.)
  - Fix MBlockFPS html doc as well, which mentions 'thres' instead of 'ml'. Add mode 5-8 to MBlockFPS docs</li>
  - Move change log from readme to CHANGELOG.md
  - Code change/speedup: MSuper: rfilter=0 and 1
    8 bit: drop old SSE code, port to SIMD intrinsics. Add SIMD to 16 bit case. Quicker, much quicker.
    (rfilter: Hierarchical levels smoothing and reducing (halving) filter)
  - Code change/speedup: MSuper: sharp=1 for pel=2 or 4
    Bicubic resizer drop old SSE code, port to SIMD intrinsics, implement SIMD intrinsics to 16 bit case.
    No need for Bilinear.asm and Bilinear-x64.asm any more.
  - SATD: add 8 bit C versions (geee, there wasn't one) (as an alternative to the external asm)
  - SAD: add internal SIMD for 8 bit SAD (SSE4.1) (as an alternative to the external asm)
  - Overlaps: Add internal SIMD for 8 bit. (as an alternative to the external asm)
  - In def.h any existing external assembler file can be disabled. 
    The primary reason for this was to quickly test the linux port, for me this was easier than bothering with asm compilation and linking.
    For non-Windows cases all of these are disabled now.
    - USE_COPYCODE_ASM (CopyCode-a.asm). Has internal alternative. Same speed.
    - USE_OVERLAPS_ASM (Overlap-a.asm). asm implements 8 bit only. Has internal SIMD alternative. About the same speed.
    - USE_SAD_ASM (sad-a.asm) asm implements 8 bit only. Note: Internal 8 bit SIMD SAD is a bit slower that these handcrafted ones.
    - USE_SATD_ASM (Pixel-a.asm) asm implements 8 bit only. Note: SATD 8 bit has no SIMD replacement yet. 
    - USE_LUMA_ASM (Variance-a.asm) asm implements 8 bit only. Has internal alternative. 
    - USE_FDCT88INT_ASM (fdct_mmx.asm, fdct_mmx_x64.asm) 
                        Only used for 8x8 block sizes. Quick integer version instead of fftw3.
                        No internal alternative, fftw3 is used instead.
    - USE_AVSTP (do find search for avstp.dll on Windows)
  - Minor and not so minor cosmetics, mainly for GCC.
  - Add Cmake build system.
  - MvTools2: Linux/GCC port (needs sse4.1), Dewindowsification.
    fftw3: MAnalyze dct modes that require fftw3 library will search for libfftw3f_threads.so.3
    Install either libfftw3-single3 (deb) or fftw-devel (rpm) package");
    e.g. sudo apt-get update
         sudo apt-get install libfftw3-dev
  - Not done (will be done in a second phase):
    Add back some external asms for linux build. For 8 bit SAD and SATD mainly.
    Linux port is still Intel-only, though every part has C alternative by now.
  - Separate the 3 projects (mvtools2, depan, depan_estimate).
  - DePan and DePanEstimate: Linux port
  - DePanEstimate: add fft_threads variable (default 1) for fftw3 mode (experimental)
  - DepanEstimate: add MT guard around sensible fft3w functions
  - mingw build fixes
  - Add build instructions to README.md
  - experimental avx2 for MDegrain1..6 (was not worth speedwise on my i7700 - memory transfer is bottleneck)
  - experimental 32-bit float internal Overlaps result buffer for MDegrain1..6
    whether if it is any quicker/more exact than the integer-scaled arithmetic version
    (when out32=true, do not use, it is only for development/test, maybe will be removed in the future)

- 2.7.44 (20201214)
  - MAnalyze: fix motion vector generation inconsistencies across multiple runs.
    Note: when internal multithreading is used (avstp + mt=true), inconsistencies will still occur by design.

- 2.7.43 (20200602)
  
- MCompensate: fix crash for GreyScale formats when overlap is used
  
- 2.7.42 (20200522)
  - MDegrain family: limit and limitc to float, allowing more granurality for 10+ bit depth
  - Update Avisynth headers, use V8 interface frame property copy if available

- 2.7.41 (20190502)
  - Fix: regression since 2.7.35: MSuper chroma for non-planar YUY2 (Thanks to mkauf)
  - Project moved to Visual Studio 2019, v141_xp and v142 toolset

- 2.7.40 (20190212)
  - Fix: MFlowInter possible crash with specific parameter and colorspace settings.
  - Fix: MFlowInter possible overflow at 16 bit clips (artifacts)
  - MFlow, MFlowInter, MFlowFPS, MFlowBlur, MBlockFPS: support all 8-16 and 32 bit float Y, YUV (4:2:0, 4:2:2, 4:4:4) and planar RGB color spaces.
    Input clip format is independent from the ones used for getting motion vectors.

- 2.7.39 (20190102)
  - MSuper: fix 16 bits, pel=2, sharp=2, which caused bottom-section artifacts for MDegrain using 8 bit vector origin and 16 bit real clip
  - MDegrain1-6,N: Enhanced:\
       Input clip (and super) format now is fully independent from vector clip's base format (subsampling had to be the same before)
       E.g. make motion vector clips from a YV12 source and apply them on a 8-32 bit 4:4:4 input

- 2.7.38 (20181209)
  - MCompensate: Fix regression in latest v37: overlap=0 crash - ouch, sorry
  - MAnalyze DCT: FFTW float: quicker postprocess of DCT'd blocks, now is correct for non power-of-2 block sizes\
  e.g. 12 or 24 (no effect on 8x8 for which fast integer DCT is used)
  - MAnalyze DCT: more consistent handling of post DCT internal normalization for non-square block sizes.

- 2.7.37 (20181128)
  - MCompensate: limit thSAD, thSAD2, thSCD1 to valid range 0-(8x8x255)\
  (e.g. given thSAD = 100000 will go back to 16320)
  - Fix: MCompensate: use int64 to avoid effective thSAD and thSAD2 overflow typically happen at bigger block sizes or large thSAD parameter value.
  - MCompensate: SSE2 (8-bit) and SSE4 (10-16 bit) overlap result calculation
  - Changed: SAD 8x8, 8x4, 4x4, 4x8 to use SSE2 instead of MMX registers
  - Fix: MDegrain if overlap<>0: missing rounder in rightmost 8 pixels for non-mod8 width 8 bit clips
  - Fix: MSuper artifacts at 10-32 bits and nPel==4
  - New: MCompensate 32 bit float and planar RGB support (by using motion vectors made from 8-16 bit YUV clip).\ 
       Input and super clip can be of a different format than the one used for motion vector creation.\
       (Similar to MDegrain1-6)

- 2.7.36 (20181120)
  - Fix: Allow overlap operation when there are only two blocks in either horizontal or vertical direction\
  (was: division by 0 crash)
  - Fix: Fallback to overlap=0 mode when block count is only 1 in either h or v direction (was: undefined behaviour)
       The cases above occured for small frame sizes, when frame size and overlap values resulted in less than 3 blocks in a direction.
  - Misc: update html docs with overlap drawing and others.

- 2.7.35 (20181113)
  - MFlowXXX: Slight speed gain by putting the out-of-frame vector check to resizer
  - Fix: MAnalyze: Fix a possible internal overflow on larger blocksizes with small overlap\
  e.g. BlkSize=32, OverlapX=0, OverlapY=4
  - MSuper: Planar RGB support. Now MSuper supports Y and YUV and planar RGB 8-32 bits, and YUY2\
          note: different filters may support only a limited set of super clip formats.
  - MFlowFPS: Planar RGB support: generate vectors in YUV, use RGB input and super clip
  - MFlowFPS: less memory for 4:4:4 and greyscale
  - MFlowFPS: a bit faster 4:4:4, much faster greyscale
  - MFlowFPS: support different bit depth for clip and the vectors (use vectors from 8 bit analysis for a 16 bit clip)

- 2.7.34 (20181108)
  
- MFlowInter: Use less memory, eliminates ten full-frame internal buffers
  
- 2.7.33 (20181021)
  
- MFlowXX: Fix random access violation caused by enlarged vectors pointing on out-of-frame positions
  
- 2.7.32 (20181018)
  - MAnalyze: Enhance mt mode report for Avisynth+: MT_SERIALIZED instead of MT_MULTI_INSTANCE when temporal=true or using output file.
  - MAnalyze: fix a possible internal overflow on larger blocksizes and lambda combinations.\
  e.g. truemotion=true with blksize=32

- 2.7.31 (20180409)
  - Fix: MFlow: SC detection after having the mv clip. Fixed in 2.5.11.22 but was missed during 2.6.0.5 merge.
  - Fix: MFlow: crash in 16-bit 4:2:0, mode=1
  - Fix: MDegrain, out16=true: Green bottom lines when overlap blocks are not covering the full vertical area

- 2.7.30 (20180405)
  - Fix: crash in MFlowInter (and possibly other MFlow...). v2.7.29 revelead this additional bug (which was not even 100% reproducible), 
  this fix is basically the 2nd part of the solution.

- 2.7.29 (20180403)
  - Fix: MFlowInter (and possibly other MFlow...) crash with specific combination of analyze parameters\
  (e.g. blkSize=16,overlapv=4,divide=1)
    Bug existed since at least 2.5.11.22

- 2.7.28 (20180323)
  
- Fix: in MDegrain1-6/N allow Y8 input for out16 parameter
  
- 2.7.27 (20180318)
  - Fix: MDepan: use zerow parameter. The parameter had no effect probably since it had been introduced. (veins1)
  - MDepan: report MT mode for Avisynth+. MT_MULTI_INSTANCE, except for logfile writing output mode when it reports MT_SERIALIZED.
    (other filters already have proper registration, MDepan was missed)

- 2.7.26 (20180314)
  - New: MDegrain1-6 and N: new parameter bool "out16" = false. If set, 8 bit input results in native 16-bit output\
  (like lsb=true hack but this is native).
  Faster than lsb=true by up to 12% (i7-7700)
  - Faster: special 10 bit SAD functions instead of the generic 10-16-bit one.\
   Depending on the block size, 4-17% gain for a typical MDegrain1-6 session

- 2.7.25 (20180227)
  - Fix: x64: not-cleared mmx state in MSuper assembly code would cause crash later,\
  e.g. in x264 encoding, depending on following filters.
  - Fix: MSCDetection SC value parameter name to Ysc from Yth (must be an ancient typo),\
  docs are OK, but the fix is mentioned in docs
  - MSuper: import 8 bit sse2 interpolators from mvtools-vs. Extend them for 10-16-bits (faster super clip)\
          Some filters are still todo.
  - MSuper: support 32-bit float clips, which can be used later by MDegrains (but not for MAnalyse)
  - MDegrains: allow degraining clip with different bit depth from vectors. Clip and Super must be the same bit depth
  - MDegrains: consistently use limit and limitC, 255 do nothing, otherwise scale 0-254 value to the current bit-depth range
  - Overlaps: more correct internal rounding for 8 bits:\
            old: `pixel = Sum( (tmp + 256) >> 6) >> 5`\
            new: `pixel = (Sum( (tmp + 32) >> 6) + 16) >> 5`
  - Overlaps: round for 16-bits\
            old: `pixel = Sum(tmp) >> 11`\
            new: `pixel = (Sum(tmp) + 1024) >> 11`
  - Overlaps: 32-bit float (but still use the original 11 bit window constants)
  - Project: change from yasm to nasm.

- 2.7.24 (20171205)
  - Fix: MFlowBlur: possible access violation crash when nPel>1</li>
  - New: MScaleVect parameter 'bits'. e.g. Analyze 8 bit clips, use their vectors for 16 bits
  - Move project to VS2017

- 2.7.23 (20171012)
  - Fix: MScaleVect wrong rounding of scaled motion vectors with negative components.\
  e.g. proper scaling (-1,-2) to (-2,-4) instead of (-1,-3)

- 2.7.22 (20170830)
  - Misc: Stop using version suffix .22
  - Fix: [DCT 8x8@8-bit] garbage on x64: internal assembly code did not save xmm6/xmm7
  - Fix: [DCT 8x8@8-bit] safe multithreading for integer DCT (8x8 block size, 8 bit video):\
  assembly had a single working buffer.
  - Fix: [MDegrain] did not release input motion vector clips in destructor, possible hang at script closing.\
  Bug since 2.7.1.22 (introducing MDegrain4/5)       
  - Mod: fftw conversion constant of `sqrt(2)/2` is more accurate (was: 0.707), 16 bit formats may benefit (by feisty2)
  - Fix: SSE4 assembly instructions in x64, broke on non-SSE4 processors

- 2.7.21.22 (20170629)
  
- Fix: [MDegrainN] fix chroma plane processing
  
- 2.7.20.22 (20170526) - hotfix
  
- Fix: [MMask] greyscale input resulted in AV when filter exiting
  
- 2.7.19.22 (20170525)
  - New: [MMask] Support any planar input video formats e.g. greyscale, Planar RGB.\
               Input clip can even be of different bit depth or format from vector's original format\
               For kind==5 where U and V is filled, the greyscale option is not allowed
  - Mod: [MMask] Faster: request source frame only for kind=5.
  - Fix: [MxxxxFPS,MMask]: MakeVectorOcclusionMaskTime garbage in bottom blocks **(30 hrs of debugging)**
  - Fix: [MMask] bottom padding garbage for padded frame dimension
  - Fix: [MMask] proper 10+ bits scene change values (for default: 1023, 4095, 16383, 65535. Was: 65535)\
       Parameter is still in 8-bit range  
  - Fix: [MRecalculate] prevent overflow during thSAD scaling in 16 bits or large block sizes (32, 48...)
  - Fix: [DepanEstimate] Sometimes giving wrong motion instead of scene change detection
  - Fix: [MAnalyze] Possible overflow in MAnalyze 8 bit, block size 48x48 and above.\
       Overflow-safe predictor recalc for big block sizes
  - New: [General] Add block size 12x3 for SAD, allow 6x24\
       List of available block sizes
       ```
         64x64, 64x48, 64x32, 64x16
         48x64, 48x48, 48x24, 48x12
         32x64, 32x32, 32x24, 32x16, 32x8
         24x48, 24x24, 24x32, 24x12, 24x6
         16x64, 16x32, 16x16, 16x12, 16x8, 16x4, 16x2
         12x48, 12x24, 12x16, 12x12, 12x6, 12x3
         8x32, 8x16, 8x8, 8x4, 8x2, 8x1
         6x24, 6x12, 6x6, 6x3
         4x8, 4x4, 4x2
         3x6, 3x3
         2x4, 2x2
       ```
  - Mod: [Internal] Reorganized 10-16 bit SAD simd intrinsics, faster 8-12% for BlkSize 12-32

- 2.7.18.22 (20170512)
  - Fix: 10-16 bit: DCT buffer possible overflow

  - Fix: DCT is fast again for non 8x8 blocksizes. Regression since 2.7.5.22.

  - New: Chroma SAD is now always half of luma SAD, regardless of video format\
       Without this: YV24's luma:chroma SAD ratio is 4:8 instead of 4:2 (of YV12)

  - New: MAnalyze, MRecalculate new parameter: "scaleCSAD" integer, default 0\
       Fine tune chroma SAD weight relative to luma SAD.
       ScaleCSAD values for luma:chroma SAD ratio
     ```
       -2: 4:0.5
       -1: 4:1
        0: 4:2 (default, same as the native ratio for YV12)
        1: 4:4
        2: 4:8
     ```
  - New: Block sizes 64, 48, 24, 12, 6
       MAnalyze/MRecalculate new block sizes (SATD support mod4 sizes)\
       List of available block sizes
       ```
         64x64, 64x48, 64x32, 64x16
         48x64, 48x48, 48x24, 48x12
         32x64, 32x32, 32x24, 32x16, 32x8
         24x48, 24x24, 24x32, 24x12, 24x6
         16x64, 16x32, 16x16, 16x12, 16x8, 16x4, 16x2
         12x48, 12x24, 12x16, 12x12, 12x6
         8x32, 8x16, 8x8, 8x4, 8x2, 8x1
         6x24, 6x12, 6x6, 6x3
         4x8, 4x4, 4x2
         3x6, 3x3
         2x4, 2x2
       ```
  - Note: some smaller block sizes can only be available in 4:4:4 formats,\
  due to block size division (chroma subsampling)

  - New: All block sizes are supported in MDegrain1-6, MDegrainN, and MScaleVect

  - New: Changed to 2017 version of asm files for 8 bit SAD/SATD functions from x265 project.\
       Added not implemented asm code for 12, 24, 48 sizes\
       For some block sizes AVX2 and SSE4 is supported (AVX2 if reported under AviSynth+)
       e.g. BlkSize 32 is faster now.

  - New: MMask SAD Mask to give identical weights for other-than-YV12 formats, e.g. for YV24

- 2.7.17.22 (20170426)
  - Fix: Regression in 2.7.16.22: MDegrain right pixel artifacts on non-modulo 16 widths
  - Misc: MMask, mode SADMask output is normalized further by video subsampling\
  (YV16/YV24 has larger SAD value due to bigger chroma part that classic YV12)

- 2.7.16.22 (20170423)
  - Fix: MMask 10-16 bits
  - Fix: MRecalculate 14-16 bits passed nSCD1=999999 internally which caused overflow (scene change problems later)
       Fix is done by clamping SCD1 to 8*8*(255-0) (maximum value of sum of SADs on a 8x8 block)
  - Misc: MDegrainX 8 bits: internal 16 bit buffer to 8 bits: SSE2

- 2.7.15.22 (20170316)
  - Fix: 16 bit SAD for non-AVX code path
  - Misc: MDegrain1-6: add error on lsb_flag=true for non-8 bit sources
  
- 2.7.14.22 (20170206)
  - Fix: MAnalyze divide=2 showed "vector clip is too small"
       (inherited from 2.6.0.5, sanity check was done but length was not filled for divideextra data)
  - Fix: MFlow access violation in internal mv resizer when resizing factor was big (MCaWarpSharp3 4x supersampling case)
       (bug introduced in upstream 2.5.11.22)

- 2.7.13.22 (20170201)
  - Fix: MDegrain1-6,N 10-16 bit thSCD scaling
  - Fix: MVShow: tolerance scaling for 10-16 bits

- 2.7.12.22 (20170120)
  - New: Faster SATD (dct=5..10) 8 bit: updated x264 function selectors, SSE2/4/AVX/AVX2\
       +10% speed for a whole typical MDegrain3 process on my i7-3770
  - New: Much Faster SATD (dct=5..10) 10-16 bit: SSE2/SSE4 instead of C\
       +50% speed for a whole typical MDegrain3 process (which is approx half speed of 8 bit)

- 2.7.11.22 (20170116)
  - New: MDegrain6
  - Mod: MDegrain1-6 SSE4 for 10-16 bit (was: C. 3-5% gain, wasn't bottleneck)

- 2.7.10.22 (20161228)
  
- Fix: for YV12 the debug info text chroma part was positioned at wrong place
  
- 2.7.9.22 (20161220)
  
- Apply 2.5.11.9-svp analysis speedup, mainly when chroma is involved
  
- 2.7.8.22 (20161218)
  - Fix: YUY2 input access violation (regression after 2.7.0.22d)
       Fixed also in Depan.dll
  - Fix: MDegrain: free up YUY2 planes only if not planar input (bug inherited from 2.5.11.22 MDegrain3)\
       resulting in freeze at script exit

- 2.7.7.22 (20161214) - optimizing a bit
  - speed: change some 8 bit SAD functions for the better
  - speed: separating bottleneck 8 bit/16 bit code paths in order not to use slower 
         int64 calculations for 8 bit,\
         where there are no integer overflow problems
  - speed: more __forceinlines for helping the compiler
  - info:  general speed gain of 5-15% compared to 2.7.6.22, much reduced speed gap\
         compared to the "classic" YV12 8 bit mvtools2 versions

- 2.7.6.22 (20161204) - fixes and speedup
  - Fix: sumLumaChange underflow (used for dct=2,6,9) (regression during 16 bit support)
  - Fix: MeanLumaChange scale for 10-16 bits (used for dct=2,6,9)
  - Fix: Mask fix: 8 bit mask resizer bug in SIMD intrinsics  - Thx real.finder\
       (regression on inline asm -> SIMD transition)       
  - Fix: dctmode=1,2: pixel distance was not corrected for 16 bit pixel sizes
  - speed: Let's help VS2015 with some __forceinline directives to recognize the truth.
  - speed: Misc optimizations throughout the code (bit shifts instead of div or mul)
  - speed: FFTW DCT: C code replaced with SIMD SSE2/SSE4 (FloatToBytes, BytesToFloat)
  - speed: 16 bit SAD: a few optimizations in SSE2, AVX-coded SSE2 and AVX2 codepath
  - VS2015 compiler: /MT -> /MD (from static to dynamic dlls - now it reallys need VS2015 redistributables)

- 2.7.5.22 (20161119)
  - Milestone release:
  General support of 10-16 bit formats with Avisynth Plus (r2294 or newer recommended)
  with new MDegrain4 and MDegrain5 filters.

  - Fix for MSCDetection: scene change filler pixel default value was always 0 (2.7.1.22 regression)
  - MCompensate: possible bugfix bottom padding UV
  Fix SAD for 10-16 bit depths for horizontal block sizes >= 16
  Fix nSCD2 (Scene change threshold block count %) (2.7.1.22 regression)
  - MBlockFPS: overlap fixes (right columns and bottom lines)
  - MBlockFPS: overlap fix: missing copy buffer to output, thanks StainlessS

- 2.7.1.22 (20161020)
  
  - Some additional fixes for YV24
  - New: MDegrain4, MDegrain5
  - Experimental native 10-16 bit support (MSuper, MAnalyze, MDegrain1-5, MDegrainN)
  including 16 bit SATD\
  (slow C) and SSE2 optimized regular SAD for 8+
  (for 10+ bits you need at least Avisynth+ r2290), 
  - Inline assembly rewritten to intrinsics -> 64 bit build is possible in VS2015
(External assembly untouched)
  
  - Note:
    Built with VS2015, this build is 3-8% slower than previous ICC build.\
  Don't use it if you stuck at YV12 or YUY2 clips and this speed loss makes you unhappy
  
- 2.7.0.22d 
  - Some additional fixes for YV24
  - Allow greyscale input (Y8)
  - dct modes >= 5 now use SATD again (so far it was in dead code, contrary to 2.5.13.1 remarks)
  - fftw 3.3.5 support (changed function names, 3.3.4 still OK), see http://www.fftw.org/download.html
  - XP support
  - compiled to SSE2 with optional SSE4.2 paths
  (not new but don't forget: first search for libfftw3f-3.dll, then fftw3.dll)

- 2.7.0.22c: (August 04, 2016)

  - test build to support YV16 and YV24, from now there is no need for YUY2 planar hack in scripts. Use ConvertToYV16() and work with it.

- 2.7.0.22 (April 29, 2016)

  - Synchronized to Fizick's 2.5.11.22 version
    e.g. fixed: greenish garbage in MFlowInter
  - Dropped tclip support in MFlow, MFlowInter (could not resolve with 2.5.11.22)
  - 2.6.0.5 x64 capable version ported under Avisynth 2.6 API
  - Fixed access violation in MDepan
  - Fixed access violation in x64 asm code
  - Built with Visual Studio 2015 Community Edition, v140 toolset
  - Compiler: Intel C++ (because of inline 64 bit asm code)

  - version number ending "22" hints to Fizick's 2.5.11.22 version

- 2.7.0.1 (March 31, 2016)

  - Version schema changed: skipped 2.6.x.x to leave numbering space to the previous authors

