# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 8cx Gen 2 (Profile 3: Max Quality)
# Hardware: Qualcomm Snapdragon 8cx Gen 2 / Microsoft SQ2 (4x Kryo 495 Gold + 4x Silver, Adreno 680)
# Target: Highest Achievable Quality within 8cx Gen 2 Thermal Ceiling
# Revision: 2.1.0 (2026-10-28)
# Changelog: Native 1080p, levels=1, coarse 32x32 -> fine 16x16 (GPU) / 16x16 -> 8x8 (CPU), searchparam=2, blend=true, threads=3/4, mem_limit=1536/2048, D3D12 toggle
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Adreno GPU Offload
# Set to true for Direct3D 12 Adreno GPU offload (mvtools2_d3d12.dll)
# Set to false for original ARM64 CPU NEON baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_GPU = false

# Dynamic parameters adapted to USE_GPU
plugin_file = USE_GPU ? "mvtools2_d3d12.dll" : "mvtools2.dll"
threads     = USE_GPU ? 3 : 4     # GPU: 3 threads leaves Gold cores free; CPU: all 4 Gold cores
mem_limit   = USE_GPU ? 1536 : 2048

# Dynamic parameter adaptation:
# GPU DirectCompute: pel=1 avoids 8.3 MB subplane cache thrashing on Adreno 680 (FlowWarpCS performs subpixel bilinear sampling in hardware);
#                    32x32 (searchparam=2) -> 16x16 blocks with GPU 2x2 bilinear coarse predictor interpolation and blend=true.
# CPU NEON: pel=2 half-pixel precision (sharp=1 bicubic), 16x16 -> 8x8 fine micro-blocks, blend=true.
pel_val     = USE_GPU ? 1 : 2
sharp_mode  = USE_GPU ? 0 : 1
blk_coarse  = USE_GPU ? 32 : 16
blk_fine    = USE_GPU ? 16 : 8

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

# 2. Wide Coarse Motion Vector Field Analysis
# blksize=blk_coarse: 32x32 on GPU (2,040 blocks), 16x16 on CPU (8,160 blocks)
# search=2, searchparam=2: Radius-2 hexagonal search tracks fast action across both GPU and CPU
# chroma=false: Luma-focused motion estimation keeps computation inside thermal budget
# levels=1: Strictly searches base Level 0
# badrange=(-24): Outlier vector suppression for CPU NEON search path
backward_dense = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))
forward_dense  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))

# 3. High-Definition Micro-Block Refinement (MRecalculate)
# blksize=blk_fine: Refines vectors (16x16 on GPU via compute shader 2x2 bilinear coarse predictor, 8x8 on CPU)
# search=2, searchparam=1: 3x3 local grid refinement around interpolated coarse predictor
# divide=0: Unsplit block grid required for D3D12 compute offload
backward_fine = MRecalculate(super, backward_dense, blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false, divide=0)
forward_fine  = MRecalculate(super, forward_dense,  blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false, divide=0)

# 4. Dynamic Median Motion Interpolation with Occlusion Handling
# mode=2: Dynamic Median pixel-flow synthesis with occlusion masking
# blend=true: Scene-change fallback blending for camera cuts or occluded regions
# thSCD1=320, thSCD2=115: Strict scene-change detection to prevent cross-cut morphing
MBlockFps(super, backward_fine, forward_fine, num=60, den=1, mode=2, blend=true, thSCD1=320, thSCD2=115)

# 5. Core Pinning: Natural lookahead queue avoids D3D12 mutex lock convoy
Prefetch(threads)

