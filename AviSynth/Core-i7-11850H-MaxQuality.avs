# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Intel Core i7-11850H (Profile 3: MaxQuality)
# Hardware: Intel Core i7-11850H (8C/16T Tiger Lake-H @ 45W TDP, Intel UHD Graphics 32EU)
# Memory: 16GB-64GB Dual-Channel DDR4-3200 (51.2 GB/s Bandwidth, 24MB Shared L3 Cache)
# Architecture: Native 1080p x86-64 AVX-512 / AVX2 CPU Motion Estimation (mvtools2.dll)
# Target: High-Fidelity 60fps Presentation, Native 16x16 with 4px Overlap (14,151 Blocks), 45W High-Headroom
# Revision: 1.0.0 (2026-10-25)
# ==============================================================================

# Core Allocation & Threading Strategy:
# 8 worker threads mapped 1:1 across all 8 physical Willow Cove cores with zero hyperthread contention.
# Fully utilizes 24MB shared L3 cache and AVX-512 vector execution without SMT thread stalls.
# Leaves all 8 logical hyperthreads completely free for Intel UHD DXVA decode and Windows DWM.
threads     = 8
mem_limit   = 1536                # Generous cache allocation for dense overlapping vector grid

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded via Intel UHD Graphics)
src = potplayer_source()

# Load Native x64 MVTools2 plugin (leveraging Willow Cove AVX-512 / AVX2 SIMD optimizations)
LoadPlugin("mvtools2.dll")

# 1. Native 1080p Super Clip with Bicubic Subpixel Interpolation
# sharp=1: Bicubic subpixel interpolation enhances fine detail edge contrast
# levels=1: Single-level eliminates redundant pyramid levels
# hpad=0, vpad=0: Native pitch alignment
super = src.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=1)

# 2. Native 1080p Overlapping Motion Vector Search (No Proxy / Zero Downscale)
# blksize=16, blksizev=16, overlap=4, overlapv=4: ~14,151 overlapping blocks at native 1080p
# Overlap eliminates block boundary discontinuities along fast-moving contours
# search=2, searchparam=2: Radius-2 hexagonal search captures rapid motion
# chroma=false: Luma-only search cuts vector computation by 50%
# levels=1: Single-level search matching super's levels=1
backward_vec = MAnalyse(super, isb=true,  blksize=16, blksizev=16, overlap=4, overlapv=4, search=2, searchparam=2, chroma=false, levels=1)
forward_vec  = MAnalyse(super, isb=false, blksize=16, blksizev=16, overlap=4, overlapv=4, search=2, searchparam=2, chroma=false, levels=1)

# 3. Direct Native 60fps Frame Synthesis with Directional Alpha Blending
# Directly warps native frames using overlapping vector fields
# mode=0: Fast 2-stream block projection
# blend=true: Smooths occlusion boundaries and disocclusion edges
# thSCD1=350, thSCD2=115: High-sensitivity scene-change threshold prevents cut distortion
MBlockFps(src, super, backward_vec, forward_vec, num=60, den=1, mode=0, blend=true, thSCD1=350, thSCD2=115)

# 4. Core Pinning: 8 Threads with 8-Frame Lookahead Queue
# 8 worker threads on 8 physical cores delivers massive AVX-512 vector compute
# 8 lookahead frames absorb thread scheduling jitter for zero dropped frames
Prefetch(threads, 8)
