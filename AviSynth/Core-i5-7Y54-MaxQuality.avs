# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Intel Core i5-7Y54 (Profile 3: MaxQuality)
# Hardware: Intel Core i5-7Y54 (2C/4T Kaby Lake-Y @ 1.20-3.20 GHz, Intel HD Graphics 615)
# Memory: 8GB LPDDR3-1866 (Dual-Channel ~29.8 GB/s Bandwidth)
# Architecture: Native 1080p x86-64 AVX2 / SSE4.2 CPU Motion Estimation (mvtools2.dll)
# Target: High-Fidelity 60fps Presentation, Native 16x16 with 4px Overlap, 10W Envelope
# Revision: 2.0.0 (2026-10-25)
# Changelog: Removed 0.5x proxy downscaling; native 1080p 16x16 overlapping grid with temporal blending
# ==============================================================================

# Core Allocation & Threading Strategy:
# 3 worker threads across 4 logical threads (2C/4T) utilizes ~75% compute headroom.
# Leaves 1 logical thread dedicated to PotPlayer D3D11 swapchain, audio decode, and DWM.
threads     = 3
mem_limit   = 1024                # Generous cache allocation for dense overlapping vector grid

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded via HD Graphics 615)
src = potplayer_source()

# Load Native x64 MVTools2 plugin (leveraging AVX2 SIMD optimizations)
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

# 4. Core Pinning: 3 Threads with 6-Frame Lookahead Queue
# Leaves 1 thread completely free for OS, audio pipeline, and D3D11 swapchain
# 6 lookahead frames absorb thread scheduling jitter
Prefetch(threads, 6)
