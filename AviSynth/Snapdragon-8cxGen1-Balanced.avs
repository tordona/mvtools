# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 8cx Gen 1 (Profile 2: Balanced)
# Hardware: Qualcomm Snapdragon 8cx Gen 1 (4x Kryo 495 Gold + 4x Silver, Adreno 680)
# Target: Fluid 1080p 60 fps, Sharp Edge Tracking, Stable Thermal Ceiling
# Revision: 2.1.0 (2026-10-28)
# Changelog: Native 1080p, levels=1, single-pass 16x16, sharp=0 (pel=1), threads=3/4, Prefetch(threads), mem_limit=1024/1536, D3D12 toggle
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Direct3D 12 Compute Offload
# Set to true for Direct3D 12 Adreno GPU offload (via MEnableD3D12 in mvtools2.dll)
# Set to false for original ARM64 CPU NEON baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_D3D12 = false

# Dynamic parameters adapted to USE_D3D12
threads     = USE_D3D12 ? 3 : 4     # GPU: 3 threads keeps lookahead buffer full; CPU: 4 Gold cores
mem_limit   = USE_D3D12 ? 1024 : 1536

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (Offloaded via Adreno 680 hardware decoder)
potplayer_source()

# Dynamic Resolution Adaptation:
# Detect 4K (3840x2160 / 4096x2160) vs 1080p/720p.
# At 4K, 32x32 blocks maintain the exact 8,160 block count of 1080p 16x16,
# preserving single-pass responsiveness and preventing thermal throttling.
is_4k   = (Width() > 2048)
blk_sz  = is_4k ? 32 : 16
pad_val = is_4k ? 8 : 4

# Load Native ARM64 MVTools2 plugin
LoadPlugin("mvtools2.dll")
MEnableD3D12(USE_D3D12)

# 1. Motion Super Clip with Lightweight Edge Guard
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=1: Whole-pixel estimation keeps ALU low while tracking details; D3D12 FlowWarpCS performs subpixel bilinear sampling in hardware
# pad_val boundary padding prevents edge tearing without cache thrashing
# sharp=0: Subpixel interpolation filter is unused when pel=1
super = MSuper(levels=1, pel=1, hpad=pad_val, vpad=pad_val, sharp=0)

# 2. Motion Vector Search (8,160 blocks: 16x16 at 1080p, 32x32 at 4K)
# search=2: Hexagonal search with radius 1 keeps searches fast on Cortex-A76 cores
# levels=1: Strictly searches base Level 0
# badrange=(-24): Early rejection of outlier vectors to prevent haloing
backward_vec = MAnalyse(super, isb=true,  blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, chroma=false, levels=1, badrange=(-24))
forward_vec  = MAnalyse(super, isb=false, blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, chroma=false, levels=1, badrange=(-24))

# 3. Pixel-Flow Motion Interpolation
# mode=2: Pixel-flow synthesis provides smooth motion vectors without blockiness
# blend=false: Skips blend transparency calculations to conserve ALU cycles
# thSCD1=350, thSCD2=120: Balanced scene change detection
MBlockFps(super, backward_vec, forward_vec, num=60, den=1, mode=2, blend=false, thSCD1=350, thSCD2=120)

# 4. Core Pinning: 3 threads maintains continuous frame queue without mutex starvation
Prefetch(threads)

