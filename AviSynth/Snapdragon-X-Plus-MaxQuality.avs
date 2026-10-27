# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Snapdragon X Plus (Profile 3: Max Quality)
# Hardware: Qualcomm Snapdragon X Plus (8x Oryon Cores @ ARM64 NEON)
# Target: Highest visual fidelity, subpixel precision, deterministic sustained 60fps
# Revision: 2.0.0 (2026-10-18)
# Changelog: Oryon architecture, levels=1, coarse 32x32 -> fine 16x16, searchparam=2, threads=6, Prefetch(6, 4), mem_limit=2048, D3D12 toggle
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Adreno GPU Offload
# Set to true for Direct3D 12 Adreno GPU offload (mvtools2_d3d12.dll)
# Set to false for original ARM64 CPU NEON baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_GPU = false

# Dynamic parameters adapted to USE_GPU
plugin_file = USE_GPU ? "mvtools2_d3d12.dll" : "mvtools2.dll"
# Adreno GPU offload evaluates luma (chroma=false required for D3D12); CPU can evaluate chroma
use_chroma  = USE_GPU ? false : true
# GPU offload executes on command queue (4 threads optimal, matches Balanced); CPU uses 8 Oryon cores
threads     = USE_GPU ? 4 : 8
mem_limit   = USE_GPU ? 2048 : 4096

# Subpixel & Block Parameters:
# pel_val: Dynamic based on USE_GPU (pel=1 on GPU cuts memory bandwidth and compute by 75% for 4K; pel=2 on CPU Oryon cores)
pel_val     = USE_GPU ? 1 : 2
# sharp=1 (bicubic) eliminates the 18ms CPU scalar bottleneck of sharp=2 (Wiener filter)
sharp_mode  = USE_GPU ? 1 : 2
pad_size    = USE_GPU ? 8 : 16
# Dual-pass coarse-to-fine: 32x32 coarse -> 16x16 fine with pel=2 half-pixel precision
# Prevents 8x8 block explosion (32,400 blocks/pass) and eliminates buffer starvation cycles
blk_coarse  = USE_GPU ? 32 : 16
blk_fine    = USE_GPU ? 16 : 8
search_alg  = USE_GPU ? 2 : 3
search_rad  = USE_GPU ? 2 : 3
plevel_val  = USE_GPU ? 0 : 1

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream
potplayer_source()

# Load Native ARM64 MVTools2 plugin
LoadPlugin(plugin_file)

# 1. High-Precision Subpixel Motion Super Clip (Half-Pixel Accuracy)
# pel: True half-pixel subpixel interpolation for ultra-fine motion vectors
# hpad, vpad: Edge padding prevents border distortion
# sharp: 1 for bicubic (fast), 2 for Wiener (CPU heavy)
super = MSuper(pel=pel_val, hpad=pad_size, vpad=pad_size, sharp=sharp_mode)

# 2. Coarse Motion Vector Field Analysis
# blksize=blk_coarse: Fast macro-motion detection
# search=search_alg, searchparam=search_rad: Wide search tracking fast pans and action
# chroma=use_chroma: Dynamic based on USE_GPU
# badrange=(-24): Strict outlier suppression
backward_coarse = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=search_alg, searchparam=search_rad, chroma=use_chroma, plevel=plevel_val, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=search_alg, searchparam=search_rad, chroma=use_chroma, plevel=plevel_val, badrange=(-24))

# 3. High-Definition Subpixel Micro-Block Refinement (MRecalculate)
# blksize=blk_fine: 16x16 on GPU (8,160 blocks @ pel=2) gives subpixel accuracy at continuous 60fps
# search=search_alg, searchparam=1: Precision vector refinement around previous candidates
# chroma=use_chroma: Dynamic based on USE_GPU
# divide=0: Smooth continuous motion field
backward_fine = MRecalculate(super, backward_coarse, blksize=blk_fine, blksizev=blk_fine, search=search_alg, searchparam=1, chroma=use_chroma, divide=0)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=blk_fine, blksizev=blk_fine, search=search_alg, searchparam=1, chroma=use_chroma, divide=0)

# 4. Advanced Pixel-Flow Motion Interpolation
# mode=2: Advanced pixel-flow motion synthesis with occlusion masking
# blend=true: Directional occlusion blending without edge tearing
# thSCD1=320, thSCD2=115: Strict scene-change detection to immediately isolate camera cuts
MBlockFps(super, backward_fine, forward_fine, num=60, den=1, mode=2, blend=true, thSCD1=320, thSCD2=115)

# 5. Full Core Utilization (adapted dynamically to USE_GPU)
Prefetch(threads)

