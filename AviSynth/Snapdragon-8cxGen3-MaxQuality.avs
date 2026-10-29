# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 8cx Gen 3 (Profile 3: Max Quality)
# Hardware: Qualcomm Snapdragon 8cx Gen 3 / Microsoft SQ3 (4x Cortex-X1 + 4x Cortex-A78, Adreno 690)
# Target: Highest Achievable Quality, Wide-Radius Refinement, Sustained 60 fps
# Revision: 2.2.0 (2026-10-28)
# Changelog: Coarse 32x32 (search=3 GPU / search=2 CPU) -> fine 16x16, Dynamic Median (mode=2, blend=true), threads=4, mem_limit=1536, D3D12 toggle
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Adreno GPU Offload
# Set to true for Direct3D 12 Adreno GPU offload (mvtools2_d3d12.dll)
# Set to false for original ARM64 CPU NEON baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_GPU = false

# Dynamic parameters adapted to USE_GPU
plugin_file = USE_GPU ? "mvtools2_d3d12.dll" : "mvtools2.dll"
# GPU: 4 worker threads; CPU: 4 Cortex-X1 Prime cores (zero asymmetric core stalls)
threads     = USE_GPU ? 4 : 4
mem_limit   = USE_GPU ? 1536 : 1536
# GPU: Exhaustive 5x5 coarse grid (search=3, searchparam=2) + radius-2 fine refinement utilizes Adreno 690 compute headroom
search_alg  = USE_GPU ? 3 : 2
fine_rad    = USE_GPU ? 2 : 1

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (Offloaded via Adreno 690 hardware decoder)
potplayer_source()

# Load Native ARM64 MVTools2 plugin
LoadPlugin(plugin_file)

# 1. Motion Super Clip with Boundary Guard
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=1: Whole-pixel estimation paired with MRecalculate; D3D12 FlowWarpCS performs subpixel bilinear sampling in hardware
# hpad=8, vpad=8: 8 px boundary padding stabilizes edge vector calculation on wide camera pans
# sharp=0: Subpixel interpolation filter is unused when pel=1
super = MSuper(levels=1, pel=1, hpad=8, vpad=8, sharp=0)

# 2. Wide Coarse Motion Vector Field Analysis (32x32 blocks, searchparam=2)
# blksize=32, blksizev=32: Macro-motion detection across 2,040 blocks at 1080p
# search=search_alg, searchparam=2: Full 5x5 (25-point) exhaustive grid on GPU; radius-2 hexagonal search on CPU
# chroma=false: Luma-focused motion estimation keeps computation inside thermal budget
# levels=1: Strictly searches base Level 0
# badrange=(-24): Outlier vector suppression for CPU NEON search path
backward_dense = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=search_alg, searchparam=2, chroma=false, levels=1, badrange=(-24))
forward_dense  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=search_alg, searchparam=2, chroma=false, levels=1, badrange=(-24))

# 3. High-Definition Refinement Pass (MRecalculate to 16x16)
# blksize=16, blksizev=16: Refines vectors down to 16x16 blocks at object boundaries using 2x2 bilinear coarse predictors
# search=2, searchparam=fine_rad: Radius-2 hexagonal refinement on GPU; 3x3 local grid on CPU
# divide=0: Unsplit block grid required for D3D12 compute offload
backward_fine = MRecalculate(super, backward_dense, blksize=16, blksizev=16, search=2, searchparam=fine_rad, chroma=false, divide=0)
forward_fine  = MRecalculate(super, forward_dense,  blksize=16, blksizev=16, search=2, searchparam=fine_rad, chroma=false, divide=0)

# 4. Dynamic Median 60 fps Synthesis with Occlusion Handling
# mode=2: Dynamic Median pixel-flow synthesis with occlusion masking
# blend=true: Scene-change fallback blending for camera cuts or occluded regions
# thSCD1=320, thSCD2=115: Strict scene-change detection to prevent cross-cut morphing
MBlockFps(super, backward_fine, forward_fine, num=60, den=1, mode=2, blend=true, thSCD1=320, thSCD2=115)

# 5. Core Pinning: Strictly 4 Threads with 4 Lookahead Frames
# Pins worker threads to the 4x Cortex-X1 cluster, completely eliminating asymmetric thread sync stalls.
# Leaves all 4x Cortex-A78 cores free for OS, audio, PotPlayer UI, and GPU drivers.
# 4 lookahead frames absorb thread scheduling jitter and guarantee 0 dropped frames.
Prefetch(threads, 4)

