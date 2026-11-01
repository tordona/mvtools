# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon X Plus (Profile 2: Balanced)
# Hardware: Qualcomm Snapdragon X Plus (8x Oryon Cores @ ARM64 NEON)
# Target: Balanced tradeoff between motion fluidity, edge definition, and power consumption
# Revision: 2.1.0 (2026-10-28)
# Changelog: Oryon architecture, levels=1, coarse 32x32 -> fine 16x16, sharp=0 (pel=1), threads=4/6, Prefetch(threads), mem_limit=1536/2048, D3D12 toggle
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Direct3D 12 Compute Offload
# Set to true for Direct3D 12 Adreno GPU offload (via MEnableD3D12 in mvtools2.dll)
# Set to false for original ARM64 CPU NEON baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_D3D12 = false

# Dynamic parameters adapted to USE_D3D12
threads     = USE_D3D12 ? 4 : 6     # GPU offload executes on command queue (4 threads optimal); CPU uses 6 Oryon cores
mem_limit   = USE_D3D12 ? 1536 : 2048

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream
potplayer_source()

# Dynamic Resolution Adaptation:
# Detect 4K (3840x2160 / 4096x2160) vs 1080p/720p.
# At 4K, 64x64 coarse -> 32x32 fine maintains the exact 120x68 (8,160 blocks) spatial grid
# density of 1080p 16x16, cutting 4K block evaluations by 75% and preventing memory bus saturation.
is_4k      = (Width() > 2048)
blk_coarse = is_4k ? 64 : 32
blk_fine   = is_4k ? 32 : 16
pad_val    = is_4k ? 16 : 8

# Load Native ARM64 MVTools2 plugin
LoadPlugin("mvtools2.dll")
MEnableD3D12(USE_D3D12)

# 1. Motion Super Clip with Edge Guard
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=1: Integer-pixel estimation paired with MRecalculate; D3D12 FlowWarpCS performs subpixel bilinear sampling in hardware
# pad_val boundary padding stabilizes motion vectors near frame borders
# sharp=0: Subpixel interpolation filter is unused when pel=1
super = MSuper(levels=1, pel=1, hpad=pad_val, vpad=pad_val, sharp=0)

# 2. Coarse Global Motion Vector Search
# 2,040 blocks (32x32 at 1080p, 64x64 at 4K)
# search=2, searchparam=2: Hexagonal search with radius 2
# badrange=(-24): Outlier vector rejection threshold for CPU NEON search path
# levels=1: Strictly searches base Level 0
backward_coarse = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))

# 3. Fine Motion Refinement Pass (MRecalculate)
# Refines to 8,160 blocks (16x16 at 1080p, 32x32 at 4K) using 2x2 bilinear coarse predictors
# search=2, searchparam=1: 3x3 local grid refinement around interpolated coarse predictor
backward_fine = MRecalculate(super, backward_coarse, blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)

# 4. Pixel-Level Motion Interpolation with Occlusion Handling
# mode=2: Dynamic Median synthesis (clamps static cross-fade between forward and backward warped pixels)
# blend=true: Scene-change fallback blending for camera cuts or occluded regions
# thSCD1=350, thSCD2=120: Scene-change detection thresholds
MBlockFps(super, backward_fine, forward_fine, num=60, den=1, mode=2, blend=true, thSCD1=350, thSCD2=120)

# 5. Thread Pool (adapted dynamically to USE_D3D12)
Prefetch(threads)

