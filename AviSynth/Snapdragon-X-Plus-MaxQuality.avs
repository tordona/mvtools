# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon X Plus (Profile 3: Max Quality)
# Hardware: Qualcomm Snapdragon X Plus (8x Oryon Cores @ ARM64 NEON)
# Target: Highest visual fidelity, exhaustive 2D grid motion search, sustained 60 fps
# Revision: 2.1.0 (2026-10-28)
# Changelog: Oryon architecture, levels=1, search=3 (Exhaustive 7x7 coarse / 5x5 GPU fine), threads=4/8, Prefetch(threads), mem_limit=2048/4096, D3D12 toggle
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Adreno GPU Offload
# Set to true for Direct3D 12 Adreno GPU offload (mvtools2_d3d12.dll)
# Set to false for original ARM64 CPU NEON baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_GPU = false

# Dynamic parameters adapted to USE_GPU
plugin_file = USE_GPU ? "mvtools2_d3d12.dll" : "mvtools2.dll"
# Adreno GPU offload evaluates luma (chroma=false required for D3D12); CPU evaluates luma + chroma
use_chroma  = USE_GPU ? false : true
# GPU offload executes on command queue (4 threads optimal); CPU uses 8 Oryon cores
threads     = USE_GPU ? 4 : 8
mem_limit   = USE_GPU ? 2048 : 4096

# Subpixel, Block & Exhaustive Search Parameters:
# pel_val: pel=1 on GPU avoids CPU scalar subplane generation (FlowWarpCS performs subpixel bilinear sampling on GPU); pel=2 on CPU
pel_val     = USE_GPU ? 1 : 2
# sharp_mode: Only active when pel > 1 (sharp=2 6-tap Wiener filter for CPU pel=2; no-op when pel=1 on GPU)
sharp_mode  = USE_GPU ? 0 : 2
pad_size    = USE_GPU ? 8 : 16
# Dual-pass coarse-to-fine: 32x32 -> 16x16 on GPU (2,040 -> 8,160 blocks); 16x16 -> 8x8 on CPU
blk_coarse  = USE_GPU ? 32 : 16
blk_fine    = USE_GPU ? 16 : 8
# Exhaustive 2D grid search (search=3) on both GPU and CPU:
# GPU evaluates 7x7 (49 points) on 32x32 coarse blocks and 5x5 (25 points, fine_rad=2) on 16x16 fine blocks
fine_rad    = USE_GPU ? 2 : 1

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream
potplayer_source()

# Load Native ARM64 MVTools2 plugin
LoadPlugin(plugin_file)

# 1. Motion Super Clip
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=pel_val: Integer grid on GPU (paired with hardware bilinear texture warp); half-pel on CPU
# hpad, vpad: Boundary padding (8 px on GPU, 16 px on CPU)
# sharp=sharp_mode: 6-tap Wiener interpolation when pel=2 on CPU; unused when pel=1 on GPU
super = MSuper(levels=1, pel=pel_val, hpad=pad_size, vpad=pad_size, sharp=sharp_mode)

# 2. Exhaustive Coarse Motion Vector Field Analysis
# blksize=blk_coarse: 32x32 on GPU (2,040 blocks), 16x16 on CPU (8,160 blocks)
# search=3, searchparam=3: Full 7x7 (49-point) 2D exhaustive grid search for wide-radius motion capture
# chroma=use_chroma: Luma-only on GPU; luma + chroma on CPU
# levels=1: Strictly searches base Level 0
# badrange=(-24): Outlier vector suppression for CPU NEON search path
backward_coarse = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=3, searchparam=3, chroma=use_chroma, levels=1, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=3, searchparam=3, chroma=use_chroma, levels=1, badrange=(-24))

# 3. Exhaustive Micro-Block Refinement (MRecalculate)
# blksize=blk_fine: 16x16 on GPU (8,160 blocks), 8x8 on CPU (32,640 blocks)
# search=3, searchparam=fine_rad: Full 5x5 (25-point) 2D exhaustive refinement on GPU (3x3 on CPU) around 2x2 bilinear coarse predictor
# chroma=use_chroma: Dynamic based on USE_GPU
# divide=0: Unsplit block grid required for D3D12 compute offload
backward_fine = MRecalculate(super, backward_coarse, blksize=blk_fine, blksizev=blk_fine, search=3, searchparam=fine_rad, chroma=use_chroma, divide=0)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=blk_fine, blksizev=blk_fine, search=3, searchparam=fine_rad, chroma=use_chroma, divide=0)

# 4. Dynamic Median Pixel-Flow Motion Interpolation
# mode=2: Dynamic Median synthesis with occlusion masking
# blend=true: Scene-change fallback blending without edge tearing
# thSCD1=320, thSCD2=115: Strict scene-change detection to isolate camera cuts
MBlockFps(super, backward_fine, forward_fine, num=60, den=1, mode=2, blend=true, thSCD1=320, thSCD2=115)

# 5. Full Core Utilization (adapted dynamically to USE_GPU)
Prefetch(threads)

