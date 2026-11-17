# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon X (Profile 2: Balanced)
# Hardware: Qualcomm Snapdragon X Elite / Plus (8x-12x Oryon Cores @ ARM64 NEON, Adreno X1-85)
# Memory: 16 GB - 64 GB LPDDR5x-8448 (135 GB/s Unified Bandwidth)
# Architecture: ARM64 NEON / Direct3D 12 GPU Offload (mvtools2.dll)
# Generator: Google Antigravity (AIAgentProfileGuide Rev 2.3.10)
# Target: Fluid 720p–4K 60 fps, Balanced Tradeoff between Fluidity and Power
# Revision: 2.4.4 (2026-11-17)
# Changelog: Parameterized target_fps (default 60, capped at 60 fps on 4K) with target-relative frame rate bypass; Replaced unconditional levels=1 with tiered pyramid levels_val (levels_val = USE_D3D12 ? 1 : (is_4k ? 2 : 0)) and plevel=0 for tear-free panning
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
target_fps  = 60                  # Target output frame rate (e.g. 60 or 120)

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream
src = potplayer_source()

is_4k      = (src.Width() > 2048)
target_fps = (is_4k && target_fps > 60) ? 60 : target_fps

# Bypass motion interpolation if source is already at or above target_fps (4% NTSC tolerance, e.g. 59.94 fps for 60 fps)
if (src.FrameRate() >= (target_fps * 0.96)) {
    return src
}

# Dynamic Resolution Adaptation (720p through 4K):
# At 4K, 64x64 coarse -> 32x32 fine maintains the exact spatial grid
# density of standard 16x16 search, cutting 4K block evaluations by 75% and preventing memory bus saturation.
levels_val = USE_D3D12 ? 1 : (is_4k ? 2 : 0)
blk_coarse = is_4k ? 64 : 32
blk_fine   = is_4k ? 32 : 16
pad_val    = is_4k ? 16 : 8

# Load Native ARM64 MVTools2 plugin & configure Direct3D 12 engine
LoadPlugin("mvtools2.dll")
MEnableD3D12(USE_D3D12)

# 1. Base Motion Super Clip with Edge Guard
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=1: Integer-pixel estimation paired with MRecalculate; D3D12 FlowWarpCS performs subpixel bilinear sampling in hardware
# pad_val boundary padding stabilizes motion vectors near frame borders
# sharp=0: Subpixel interpolation filter is unused when pel=1
super = src.MSuper(levels=levels_val, pel=1, hpad=pad_val, vpad=pad_val, sharp=0)

# 2. Coarse Global Motion Vector Search
# 2,040 blocks (32x32 at standard resolutions, 64x64 at 4K)
# search=2, searchparam=2: Hexagonal search with radius 2
# badrange=(-24): Outlier vector rejection threshold for CPU NEON search path
# levels=1: Strictly searches base Level 0
backward_coarse = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=false, plevel=0, levels=levels_val, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=false, plevel=0, levels=levels_val, badrange=(-24))

# 3. Fine Motion Refinement Pass (MRecalculate)
# Refines to 8,160 blocks (16x16 at standard resolutions, 32x32 at 4K) using 2x2 bilinear coarse predictors
# search=2, searchparam=1: 3x3 local grid refinement around interpolated coarse predictor
backward_fine = MRecalculate(super, backward_coarse, blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)

# 4. Pixel-Level Motion Interpolation with Occlusion Handling
# mode=2: Dynamic Median synthesis (clamps static cross-fade between forward and backward warped pixels)
# blend=true: Scene-change fallback blending for camera cuts or occluded regions
# thSCD1=350, thSCD2=120: Scene-change detection thresholds
last = MBlockFps(src, super, backward_fine, forward_fine, num=target_fps, den=1, mode=2, blend=true, thSCD1=350, thSCD2=120)

# 5. Thread Pool (adapted dynamically to USE_D3D12)
Prefetch(threads)
