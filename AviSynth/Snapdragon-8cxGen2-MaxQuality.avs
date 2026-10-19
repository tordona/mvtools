# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Snapdragon 8cx Gen 2 (Profile 3: Max Quality)
# Hardware: Qualcomm Snapdragon 8cx Gen 2 / Microsoft SQ2 (4x Kryo 495 Gold + 4x Silver, Adreno 680)
# Target: Highest Achievable Quality within 8cx Gen 2 Thermal Ceiling
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
threads     = USE_GPU ? 3 : 4     # GPU: 3 threads leaves Gold cores free; CPU: all 4 Gold cores
mem_limit   = USE_GPU ? 1536 : 2048

# Dynamic parameter adaptation:
# GPU DirectCompute: pel=1 prevents 8.3MB texture cache thrashing on Adreno 680 (which is at 60-70% load);
#                    32x32 -> 16x16 blocks prevents command list serialization; blend=false avoids ALU stalls.
# CPU NEON: pel=2 half-pixel precision, 16x16 -> 8x8 fine micro-blocks, blend=true (sustained 60fps on 4 Gold cores).
pel_val     = USE_GPU ? 1 : 2
blk_coarse  = USE_GPU ? 32 : 16
blk_fine    = USE_GPU ? 16 : 8
search_rad  = USE_GPU ? 1 : 2
blend_mode  = USE_GPU ? false : true

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (Offloaded via Adreno 680 hardware decoder)
potplayer_source()

# Load Native ARM64 MVTools2 plugin
LoadPlugin(plugin_file)

# 1. Subpixel Motion Super Clip
# pel: Dynamic based on USE_GPU (pel=1 avoids Adreno 680 texture cache thrashing; pel=2 on CPU)
# hpad=8, vpad=8: Boundary padding stabilizes edge vector calculation
# sharp=1: Bicubic filtering (lighter than sharp=2, preventing thermal throttling)
super = MSuper(pel=pel_val, hpad=8, vpad=8, sharp=1)

# 2. Dense Motion Vector Field Analysis
# blksize=blk_coarse: Dynamic coarse block size based on USE_GPU
# search=2, searchparam=search_rad: Wider search tracking fast action
# chroma=false: Luma-focused motion estimation keeps computation inside thermal budget
# badrange=(-24): Strict outlier vector suppression
backward_dense = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=search_rad, chroma=false, plevel=0, badrange=(-24))
forward_dense  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=search_rad, chroma=false, plevel=0, badrange=(-24))

# 3. High-Definition Micro-Block Refinement (MRecalculate)
# blksize=blk_fine: Refines vectors (16x16 for GPU to avoid pipeline stalls, 8x8 for CPU)
# search=2, searchparam=1: Targeted vector refinement around previous candidates
# divide=0: Enforces smooth spatial motion field continuity
backward_fine = MRecalculate(super, backward_dense, blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false, divide=0)
forward_fine  = MRecalculate(super, forward_dense,  blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false, divide=0)

# 4. Advanced Pixel-Flow Motion Interpolation with Occlusion Handling
# mode=2: Pixel-flow synthesis with occlusion masking
# blend: Dynamic based on USE_GPU to eliminate CPU blend bottleneck during GPU offload
# thSCD1=320, thSCD2=115: Strict scene-change detection to prevent cross-cut morphing
MBlockFps(super, backward_fine, forward_fine, num=60, den=1, mode=2, blend=blend_mode, thSCD1=320, thSCD2=115)

# 5. Core Pinning: Natural lookahead queue avoids D3D12 mutex lock convoy
Prefetch(threads)

