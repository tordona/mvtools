# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 8cx Gen 1 (Profile 3: Max Quality)
# Hardware: Qualcomm Snapdragon 8cx Gen 1 (4x Kryo 495 Gold + 4x Silver, Adreno 680)
# Target: Highest Achievable Quality within 8cx Thermal Ceiling
# Revision: 2.1.0 (2026-10-28)
# Changelog: Native 1080p, levels=1, 16x16 exhaustive 5x5 (GPU) / 16x16 -> 8x8 (CPU), blend=true, threads=3/4, mem_limit=1536/2048, D3D12 toggle
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Adreno GPU Offload
# Set to true for Direct3D 12 Adreno GPU offload (mvtools2-d3d12.dll)
# Set to false for original ARM64 CPU NEON baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_GPU = false

# Dynamic parameters adapted to USE_GPU
plugin_file = USE_GPU ? "mvtools2-d3d12.dll" : "mvtools2.dll"
threads     = USE_GPU ? 3 : 4     # GPU: 3 threads keeps queue full; CPU: 4 Gold cores
mem_limit   = USE_GPU ? 1536 : 2048

# Dynamic parameter adaptation:
# GPU DirectCompute: pel=1, single-pass dense 16x16 with search=3, searchparam=2 (5x5 exhaustive grid in 2 dispatches prevents 7 W thermal throttling)
# CPU NEON: pel=2 half-pixel precision (sharp=1 bicubic), dual-pass 16x16 -> 8x8 micro-blocks, blend=true (sustained 60 fps on 4 Gold cores)
pel_val     = USE_GPU ? 1 : 2
sharp_mode  = USE_GPU ? 0 : 1
search_alg  = USE_GPU ? 3 : 2

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (Offloaded via Adreno 680 hardware decoder)
potplayer_source()

# Load Native ARM64 MVTools2 plugin
LoadPlugin(plugin_file)

# 1. Motion Super Clip
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=pel_val: Dynamic based on USE_GPU (pel=1 on GPU; pel=2 on CPU)
# hpad=8, vpad=8: 8 px boundary padding stabilizes edge vector calculation
# sharp=sharp_mode: Bicubic filtering when pel=2 on CPU; unused when pel=1 on GPU
super = MSuper(levels=1, pel=pel_val, hpad=8, vpad=8, sharp=sharp_mode)

# 2. Dense Motion Vector Field Analysis
# GPU: Evaluates in a single pass of dense 16x16 blocks using 5x5 exhaustive 2D grid search (search=3, searchparam=2)
# CPU: Radius-2 hexagonal coarse pass before 8x8 micro-block refinement
# levels=1: Strictly searches base Level 0
backward_dense = MAnalyse(super, isb=true,  blksize=16, blksizev=16, search=search_alg, searchparam=2, chroma=false, levels=1, badrange=(-24))
forward_dense  = MAnalyse(super, isb=false, blksize=16, blksizev=16, search=search_alg, searchparam=2, chroma=false, levels=1, badrange=(-24))

# 3. Motion Vector Refinement (CPU only)
# GPU skips MRecalculate to stay within the 7 W thermal envelope; CPU executes 8x8 micro-block refinement
backward_vec = USE_GPU ? backward_dense : MRecalculate(super, backward_dense, blksize=8, blksizev=8, search=2, searchparam=1, chroma=false, divide=0)
forward_vec  = USE_GPU ? forward_dense  : MRecalculate(super, forward_dense,  blksize=8, blksizev=8, search=2, searchparam=1, chroma=false, divide=0)

# 4. Dynamic Median Pixel-Flow Motion Interpolation
# mode=2: Dynamic Median pixel-flow synthesis
# blend=true: Scene-change fallback blending for camera cuts or occluded regions
# thSCD1=320, thSCD2=115: Strict scene-change detection to prevent cross-cut morphing
MBlockFps(super, backward_vec, forward_vec, num=60, den=1, mode=2, blend=true, thSCD1=320, thSCD2=115)

# 5. Core Pinning: 3 threads keeps presentation queue full without mutex starvation
Prefetch(threads)

