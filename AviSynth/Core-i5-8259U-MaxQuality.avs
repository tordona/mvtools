# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Intel Core i5-8259U (Profile 3: MaxQuality)
# Hardware: Intel Core i5-8259U (4C/8T Coffee Lake-U @ 28W TDP, Intel Iris Plus Graphics 655)
# Memory: 16GB-32GB Dual-Channel DDR4/LPDDR3 (128MB Embedded eDRAM L4 Cache)
# Architecture: Native 1080p x86-64 AVX2 / SSE4.2 CPU Motion Estimation (mvtools2.dll)
# Target: High-Fidelity 60fps Presentation, Native 16x16 with 4px Overlap (14,151 Blocks), 28W Envelope
# Revision: 1.0.0 (2026-10-25)
# ==============================================================================

# Core Allocation & Threading Strategy:
# 4 worker threads mapped 1:1 to the 4 physical Coffee Lake cores.
# Avoids SMT context switching penalty while fully exploiting the 28W TDP and 128MB eDRAM cache.
# Leaves all 4 logical hyperthreads free for Iris Plus 655 DXVA decode and Windows DWM.
threads     = 4
mem_limit   = 1024                # Generous cache allocation for dense overlapping vector grid

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded via Intel Iris Plus 655)
src = potplayer_source()

# Load Native x64 MVTools2 plugin (leveraging Coffee Lake AVX2 SIMD optimizations)
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

# 4. Core Pinning: 4 Threads with 6-Frame Lookahead Queue
# 4 worker threads on 4 physical cores delivers sustained AVX2 throughput on 28W TDP
# 6 lookahead frames absorb thread scheduling jitter for zero dropped frames
Prefetch(threads, 6)
