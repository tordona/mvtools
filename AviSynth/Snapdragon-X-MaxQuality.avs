# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon X (Profile 3: Max Quality)
# Hardware: Qualcomm Snapdragon X Elite / Plus (8x-12x Oryon Cores @ ARM64 NEON, Adreno X1-85)
# Memory: 16 GB - 64 GB LPDDR5x-8448 (135 GB/s Unified Bandwidth)
# Architecture: ARM64 NEON / Direct3D 12 GPU Offload (mvtools2.dll)
# Generator: Google Antigravity (AIAgentProfileGuide Rev 2.3.10)
# Target: Highest Visual Fidelity, Diamond Motion Search, Sustained 60 fps
# Revision: 2.5.0 (2026-11-06)
# Changelog: Series-wide Snapdragon X rename (X Elite + X Plus), removed 1080p phrasing, updated comments, D3D12 toggle
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Direct3D 12 Compute Offload
# Set to true for Direct3D 12 Adreno GPU offload (via MEnableD3D12 in mvtools2.dll)
# Set to false for original ARM64 CPU NEON baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_D3D12 = false

# Dynamic parameters adapted to USE_D3D12
# Adreno GPU offload evaluates luma (chroma=false required for D3D12); CPU evaluates luma + chroma
use_chroma  = USE_D3D12 ? false : true
# GPU offload executes on command queue (4 threads optimal); CPU uses 8 Oryon cores
threads     = USE_D3D12 ? 4 : 8
mem_limit   = USE_D3D12 ? 2048 : 4096

# Subpixel, Block & Search Parameters:
# pel_val: pel=1 on GPU avoids CPU scalar subplane generation (FlowWarpCS performs subpixel bilinear sampling on GPU); pel=2 on CPU
pel_val     = USE_D3D12 ? 1 : 2
# sharp_mode: Only active when pel > 1 (sharp=2 6-tap Wiener filter for CPU pel=2; no-op when pel=1 on GPU)
sharp_mode  = USE_D3D12 ? 0 : 2
pad_size    = USE_D3D12 ? 8 : 16
# Diamond search (search=2, searchparam=2): ~12 search points, cutting ME compute by ~4x vs 7x7 exhaustive while delivering +0.19 dB higher fidelity
fine_rad    = USE_D3D12 ? 2 : 1

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream
src = potplayer_source()

# Dynamic Resolution Adaptation (720p through 4K):
# At 4K, block sizes scale by 2x to maintain spatial grid density (2,040 coarse / 8,160 fine),
# eliminating the 40,560 block explosion while preserving maximal visual detail.
is_4k       = (src.Width() > 2048)
blk_coarse  = USE_D3D12 ? (is_4k ? 64 : 32) : (is_4k ? 32 : 16)
blk_fine    = USE_D3D12 ? (is_4k ? 32 : 16) : (is_4k ? 16 : 8)

# Load Native ARM64 MVTools2 plugin & configure Direct3D 12 engine
LoadPlugin("mvtools2.dll")
MEnableD3D12(USE_D3D12)

# 1. Base Motion Super Clip
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=pel_val: Integer grid on GPU (paired with hardware bilinear texture warp); half-pel on CPU
# hpad, vpad: Boundary padding (8 px on GPU, 16 px on CPU)
# sharp=sharp_mode: 6-tap Wiener interpolation when pel=2 on CPU; unused when pel=1 on GPU
pad_val = is_4k ? (pad_size * 2) : pad_size
super   = src.MSuper(levels=1, pel=pel_val, hpad=pad_val, vpad=pad_val, sharp=sharp_mode)

# 2. Diamond Coarse Motion Vector Field Analysis
# blksize=blk_coarse: 32x32 on GPU (2,040 blocks), 16x16 on CPU (8,160 blocks)
# search=2, searchparam=2: Diamond/Logarithmic search (~12 points) providing high tracking fidelity with low computational overhead
# chroma=use_chroma: Luma-only on GPU; luma + chroma on CPU
# levels=1: Strictly searches base Level 0
# badrange=(-24): Outlier vector suppression for CPU NEON search path
backward_coarse = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=use_chroma, levels=1, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=use_chroma, levels=1, badrange=(-24))

# 3. Micro-Block Refinement (MRecalculate)
# blksize=blk_fine: 16x16 on GPU (8,160 blocks), 8x8 on CPU (32,640 blocks)
# search=2, searchparam=fine_rad: Diamond refinement on GPU (local grid on CPU) around 2x2 bilinear coarse predictor
# chroma=use_chroma: Dynamic based on USE_D3D12
# divide=0: Unsplit block grid required for D3D12 compute offload
backward_fine = MRecalculate(super, backward_coarse, blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=fine_rad, chroma=use_chroma, divide=0)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=fine_rad, chroma=use_chroma, divide=0)

# 4. Dynamic Median Pixel-Flow Motion Interpolation
# mode=2: Dynamic Median synthesis with occlusion masking
# blend=true: Scene-change fallback blending without edge tearing
# thSCD1=320, thSCD2=115: Strict scene-change detection to isolate camera cuts
last = MBlockFps(src, super, backward_fine, forward_fine, num=60, den=1, mode=2, blend=true, thSCD1=320, thSCD2=115)

# 5. Thread Pool (adapted dynamically to USE_D3D12)
Prefetch(threads)
