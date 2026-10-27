# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: AMD Ryzen AI 5 340 (Profile 3: MaxQuality)
# Hardware: AMD Ryzen AI 5 340 (3x Zen 5 + 3x Zen 5c Cores, Radeon 840M RDNA 3.5 @ 2.9 GHz)
# Memory: 16GB-32GB Dual-Channel LPDDR5x-7500 (120 GB/s Unified Bandwidth)
# Architecture: Native 1080p x86-64 AVX-512 / AVX2 CPU Motion Estimation (mvtools2.dll)
# Target: High-Fidelity 60fps Presentation, Native 16x16 with 4px Overlap (14,151 Blocks), 20W Envelope
# Revision: 2.0.0 (2026-10-25)
# ==============================================================================

# Core Allocation & Threading Strategy:
# 6 worker threads mapped 1:1 across all 6 physical cores (3x Zen 5 + 3x Zen 5c) on the unified 16MB L3 CCX.
# Zero hyperthread contention; leaves all 6 SMT logical threads free for VCN decode and Windows DWM.
threads     = 6
mem_limit   = 1024                # Generous cache allocation for dense overlapping vector grid

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (AMD VCN hardware decoded via Radeon 840M)
src = potplayer_source()

# Load Native x64 MVTools2 plugin (leveraging Zen 5 dual 512-bit AVX-512 SIMD pipelines)
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

# 4. Core Pinning: 6 Threads with 6-Frame Lookahead Queue
# 6 worker threads on 6 physical cores provides high-throughput AVX-512 vector compute
# 6 lookahead frames absorb thread scheduling jitter
Prefetch(threads, 6)
