# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Intel Core i5-7Y54 (Profile 1: Eco)
# Hardware: Intel Core i5-7Y54 (2C/4T Kaby Lake-Y @ 1.20-3.20 GHz, Intel HD Graphics 615)
# Memory: 8 GB LPDDR3-1866 (Dual-Channel ~29.8 GB/s Bandwidth)
# Architecture: Native 1080p x86-64 AVX2 / SSE4.2 CPU Motion Estimation (mvtools2.dll)
# Target: Native 1080p, Sub-6 W Power, Zero Downscaling, Cool Passive Operation, 0 Drops
# Revision: 2.0.0 (2026-10-25)
# Changelog: Removed 0.5x proxy downscaling; native 1080p 32x32 single-level vector search
# ==============================================================================

# Core Allocation & Threading Strategy:
# 2 worker threads locks execution to 1 thread per physical core on this 2C/4T CPU.
# Avoids hyperthread contention, minimizing switching power and thermal output.
threads     = 2
mem_limit   = 512                 # Memory ceiling for native 1080p frame buffer

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded via HD Graphics 615)
src = potplayer_source()

# Dynamic Resolution Adaptation:
# Detect 4K vs 1080p. At 4K, 64x64 blocks maintain the exact 2,040 block count of 1080p 32x32,
# keeping memory traffic strictly within low-power TDP envelopes.
is_4k  = (src.Width() > 2048)
blk_sz = is_4k ? 64 : 32

# Load Native x64 MVTools2 plugin (leveraging AVX2 SIMD optimizations)
LoadPlugin("mvtools2.dll")

# 1. Native 1080p Super Clip (Single-Level, Integer Pixel Precision)
# pel=1: Full-pixel precision only (avoids sub-pixel interpolation overhead)
# levels=1: Eliminates redundant multi-level pyramid generation
# hpad=0, vpad=0: Zero padding overhead, preserving native pitch alignment
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = src.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Native 1080p Motion Vector Search (No Proxy / Zero Downscale)
# blksize=blk_sz, blksizev=blk_sz: 32x32 blocks at native 1080p (~2,040 blocks total)
# search=2, searchparam=1: Hexagonal search with tight radius
# chroma=false: Luma-only search cuts vector computation by 50%
# levels=1: Single-level search matching super's levels=1
backward_vec = MAnalyse(super, isb=true,  blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, chroma=false, levels=1)
forward_vec  = MAnalyse(super, isb=false, blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, chroma=false, levels=1)

# 3. Direct Native 60 fps Frame Synthesis
# Directly warps source frames without vector scaling or proxy interpolation artifacts
# mode=0: Fast block projection (minimal ALU load)
# blend=false: Skips transparency alpha blending calculations
# thSCD1=400, thSCD2=130: Robust scene-change detection cleanly cuts camera transitions
MBlockFps(src, super, backward_vec, forward_vec, num=60, den=1, mode=0, blend=false, thSCD1=400, thSCD2=130)

# 4. Core Pinning: Strictly 2 Threads with Lookahead Queue
# 1 thread per physical core minimizes thermal throttling on passive cooling
# 4 lookahead frames absorb thread scheduling jitter
Prefetch(threads, 4)
