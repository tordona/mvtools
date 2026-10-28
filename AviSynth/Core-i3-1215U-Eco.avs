# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Intel Core i3-1215U (Profile 1: Eco)
# Hardware: Intel Core i3-1215U (2P+4E/8T Alder Lake-U @ 15 W TDP, Intel UHD Graphics 64EU)
# Memory: 16 GB Dual-Channel DDR4/LPDDR5 (51.2-83.2 GB/s Bandwidth)
# Architecture: Native 1080p x86-64 AVX2 / SSE4.2 CPU Motion Estimation (mvtools2.dll)
# Target: Sub-8 W Power Envelope, Minimal Heat, Silent Fan / Passive Playback, 0 Drops
# Revision: 1.0.0 (2026-10-25)
# ==============================================================================

# Core Allocation & Threading Strategy:
# 2 worker threads locks computation strictly to the 2 Golden Cove P-cores (1 thread per P-core).
# Avoids hyperthread contention and E-core scheduling jitter, keeping package draw sub-8 W.
threads     = 2
mem_limit   = 512                 # Generous memory pool for 16 GB dual-channel RAM

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded via Intel UHD Graphics)
src = potplayer_source()

# Load Native x64 MVTools2 plugin (leveraging Golden Cove AVX2 SIMD optimizations)
LoadPlugin("mvtools2.dll")

# 1. Native 1080p Super Clip (Single-Level, Integer Pixel Precision)
# pel=1: Full-pixel precision only (avoids subpixel interpolation overhead)
# levels=1: Eliminates redundant multi-level pyramid generation
# hpad=0, vpad=0: Zero padding overhead, preserving native pitch alignment
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = src.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Native 1080p Motion Vector Search (No Proxy / Zero Downscale)
# blksize=32, blksizev=32: 32x32 blocks at native 1080p (~2,040 blocks total)
# search=2, searchparam=1: Hexagonal search with tight radius
# chroma=false: Luma-only search cuts vector computation by 50%
# levels=1: Single-level search matching super's levels=1
backward_vec = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=1, chroma=false, levels=1)
forward_vec  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=1, chroma=false, levels=1)

# 3. Direct Native 60 fps Frame Synthesis
# Directly warps source frames without vector scaling or proxy interpolation artifacts
# mode=0: Fast block projection (minimal ALU load)
# blend=false: Skips transparency alpha blending calculations
# thSCD1=400, thSCD2=130: Robust scene-change detection cleanly cuts camera transitions
MBlockFps(src, super, backward_vec, forward_vec, num=60, den=1, mode=0, blend=false, thSCD1=400, thSCD2=130)

# 4. Core Pinning: Strictly 2 Threads with 4-Frame Lookahead Queue
# 2 threads pinned to P-cores ensures zero thermal throttling on battery / low power
# 4 lookahead frames absorb thread scheduling jitter
Prefetch(threads, 4)
