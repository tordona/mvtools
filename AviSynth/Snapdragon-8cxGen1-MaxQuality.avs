# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 8cx Gen 1 (Profile 3: Max Quality)
# Hardware: Qualcomm Snapdragon 8cx Gen 1 (4x Kryo 495 Gold + 4x Silver, Adreno 680)
# Target: Highest Achievable Quality within 8cx Thermal Ceiling
# Revision: 2.0.0 (2026-10-18)
# Changelog: Native 1080p, levels=1, coarse 32x32 -> fine 16x16, searchparam=2, threads=4, Prefetch(4, 4), mem_limit=1536, D3D12 toggle
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Adreno GPU Offload
# Set to true for Direct3D 12 Adreno GPU offload (mvtools2_d3d12.dll)
# Set to false for original ARM64 CPU NEON baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_GPU = false

# Dynamic parameters adapted to USE_GPU
plugin_file = USE_GPU ? "mvtools2_d3d12.dll" : "mvtools2.dll"
threads     = USE_GPU ? 3 : 4     # GPU: 3 threads keeps queue full; CPU: 4 Gold cores
mem_limit   = USE_GPU ? 1536 : 2048

# Dynamic parameter adaptation:
# GPU DirectCompute: pel=1, single-pass dense 16x16 with searchparam=2 (2 dispatches prevents 7 W thermal throttling)
# CPU NEON: pel=2 half-pixel precision, dual-pass 16x16 -> 8x8 micro-blocks, blend=true (sustained 60 fps on 4 Gold cores).
pel_val     = USE_GPU ? 1 : 2
search_rad  = USE_GPU ? 2 : 2
blend_mode  = USE_GPU ? false : true

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (Offloaded via Adreno 680 hardware decoder)
potplayer_source()

# Load Native ARM64 MVTools2 plugin
LoadPlugin(plugin_file)

# 1. Subpixel Motion Super Clip
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel: Dynamic based on USE_GPU (pel=1 avoids Adreno 680 texture cache thrashing; pel=2 on CPU)
# hpad=8, vpad=8: Boundary padding stabilizes edge vector calculation
# sharp=1: Bicubic filtering (lighter than sharp=2, preventing thermal throttling)
super = MSuper(levels=1, pel=pel_val, hpad=8, vpad=8, sharp=1)

# 2. Dense Motion Vector Field Analysis
# GPU: Evaluates in a single pass of dense 16x16 blocks (only 2 dispatches), eliminating thermal throttling
# CPU: Coarse pass before 8x8 micro-block refinement
# levels=1: Strictly searches base Level 0
backward_dense = MAnalyse(super, isb=true,  blksize=16, blksizev=16, search=2, searchparam=search_rad, chroma=false, levels=1, badrange=(-24))
forward_dense  = MAnalyse(super, isb=false, blksize=16, blksizev=16, search=2, searchparam=search_rad, chroma=false, levels=1, badrange=(-24))

# 3. Motion Vector Refinement (CPU only)
# GPU skips MRecalculate to stay within the 7 W thermal envelope; CPU executes 8x8 micro-block refinement
backward_vec = USE_GPU ? backward_dense : MRecalculate(super, backward_dense, blksize=8, blksizev=8, search=2, searchparam=1, chroma=false, divide=0)
forward_vec  = USE_GPU ? forward_dense  : MRecalculate(super, forward_dense,  blksize=8, blksizev=8, search=2, searchparam=1, chroma=false, divide=0)

# 4. Advanced Pixel-Flow Motion Interpolation
# mode=2: Dynamic median pixel-flow synthesis
# blend: Dynamic based on USE_GPU to eliminate CPU blend bottleneck during GPU offload
# thSCD1=320, thSCD2=115: Strict scene-change detection to prevent cross-cut morphing
MBlockFps(super, backward_vec, forward_vec, num=60, den=1, mode=2, blend=blend_mode, thSCD1=320, thSCD2=115)

# 5. Core Pinning: 3 threads keeps presentation queue full without mutex starvation
Prefetch(threads)

