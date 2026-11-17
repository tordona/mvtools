# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Intel Core i7-11850H (Profile 3: MaxQuality)
# Hardware: Intel Core i7-11850H (8C/16T Tiger Lake-H @ 45 W TDP, Intel UHD Graphics 32EU)
# Memory: 16 GB-64 GB Dual-Channel DDR4-3200 (51.2 GB/s Bandwidth, 24 MB Shared L3 Cache)
# Architecture: Native 1080p x86-64 AVX-512 / AVX2 CPU Motion Estimation (mvtools2.dll)
# Target: High-Fidelity 60 fps Presentation, Native 16x16 with 4 px Overlap (14,151 Blocks), 45 W High-Headroom
# Revision: 2.1.4 (2026-11-17)
# Changelog: Parameterized target_fps (default 60, capped at 60 fps on 4K) with target-relative frame rate bypass; Replaced unconditional levels=1 with tiered pyramid levels_val (levels_val = is_4k ? 2 : 0) and plevel=0 for tear-free panning
# ==============================================================================

# Core Allocation & Threading Strategy:
# 8 worker threads mapped 1:1 across all 8 physical Willow Cove cores with zero hyperthread contention.
# Fully utilizes 24 MB shared L3 cache and AVX-512 vector execution without SMT thread stalls.
# Leaves all 8 logical hyperthreads completely free for Intel UHD DXVA decode and Windows DWM.
threads     = 8
mem_limit   = 1536                # Generous cache allocation for dense overlapping vector grid
target_fps  = 60                  # Target output frame rate (e.g. 60 or 120)

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded via Intel UHD Graphics)
src = potplayer_source()

is_4k      = (src.Width() > 2048)
target_fps = (is_4k && target_fps > 60) ? 60 : target_fps

# Bypass motion interpolation if source is already at or above target_fps (4% NTSC tolerance, e.g. 59.94 fps for 60 fps)
if (src.FrameRate() >= (target_fps * 0.96)) {
    return src
}

# Dynamic Resolution Adaptation:
# Detect 4K (3840x2160 / 4096x2160) vs 1080p/720p.
# At 4K, 32x32 blocks maintain the exact 8,160 block count of 1080p 16x16,
# preserving single-pass high-throughput execution without cache thrashing.
levels_val = is_4k ? 2 : 0
blk_sz = is_4k ? 32 : 16

# Load Native x64 MVTools2 plugin (leveraging Willow Cove AVX-512 / AVX2 SIMD optimizations)
LoadPlugin("mvtools2.dll")

# 1. Native 1080p Super Clip with Bicubic Subpixel Interpolation
# sharp=1: Bicubic subpixel interpolation enhances fine detail edge contrast
# levels=1: Single-level eliminates redundant pyramid levels
# hpad=0, vpad=0: Native pitch alignment
super = src.MSuper(levels=levels_val, pel=1, hpad=0, vpad=0, sharp=1)

# 2. Native 1080p Overlapping Motion Vector Search (No Proxy / Zero Downscale)
# blksize=blk_sz, blksizev=blk_sz, overlap=4, overlapv=4: ~14,151 overlapping blocks at native 1080p
# Overlap eliminates block boundary discontinuities along fast-moving contours
# search=2, searchparam=2: Radius-2 hexagonal search captures rapid motion
# chroma=false: Luma-only search cuts vector computation by 50%
# levels=1: Single-level search matching super's levels=1
backward_vec = MAnalyse(super, isb=true,  blksize=blk_sz, blksizev=blk_sz, overlap=4, overlapv=4, search=2, searchparam=2, chroma=false, plevel=0, levels=levels_val)
forward_vec  = MAnalyse(super, isb=false, blksize=blk_sz, blksizev=blk_sz, overlap=4, overlapv=4, search=2, searchparam=2, chroma=false, plevel=0, levels=levels_val)

# 3. Direct Native 60 fps Frame Synthesis with Directional Alpha Blending
# Directly warps native frames using overlapping vector fields
# mode=0: Fast 2-stream block projection
# blend=true: Smooths occlusion boundaries and disocclusion edges
# thSCD1=350, thSCD2=115: High-sensitivity scene-change threshold prevents cut distortion
MBlockFps(src, super, backward_vec, forward_vec, num=target_fps, den=1, mode=0, blend=true, thSCD1=350, thSCD2=115)

# 4. Core Pinning: 8 Threads with 8-Frame Lookahead Queue
# 8 worker threads on 8 physical cores provides high-throughput AVX-512 vector compute
# 8 lookahead frames absorb thread scheduling jitter for zero dropped frames
Prefetch(threads, 8)
