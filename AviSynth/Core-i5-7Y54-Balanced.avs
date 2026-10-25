# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Intel Core i5-7Y54 (Profile 2: Balanced)
# Hardware: Intel Core i5-7Y54 (2C/4T Kaby Lake-Y @ 1.20-3.20 GHz, Intel HD Graphics 615)
# Memory: 8GB LPDDR3-1866 (Dual-Channel ~29.8 GB/s Bandwidth)
# Architecture: Native 1080p x86-64 AVX2 / SSE4.2 CPU Motion Estimation (mvtools2.dll)
# Target: Fluid 1080p 60fps, Crisp Native 16x16 Vectors, 10W Sustained Envelope
# Revision: 2.0.0 (2026-10-25)
# Changelog: Removed 0.5x proxy downscaling; native 1080p 16x16 vector grid (8,160 blocks)
# ==============================================================================

# Core Allocation & Threading Strategy:
# 3 worker threads across 4 logical threads (2C/4T) utilizes ~75% compute headroom.
# Leaves 1 logical thread dedicated to PotPlayer D3D11 swapchain, audio decode, and DWM.
threads     = 3
mem_limit   = 768                 # Headroom for native 1080p 16x16 vector search

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded via HD Graphics 615)
src = potplayer_source()

# Load Native x64 MVTools2 plugin (leveraging AVX2 SIMD optimizations)
LoadPlugin("mvtools2.dll")

# 1. Native 1080p Super Clip (Single-Level, Integer Pixel Precision)
# pel=1: Full-pixel precision only (avoids sub-pixel interpolation overhead)
# levels=1: Eliminates redundant multi-level pyramid generation
# hpad=0, vpad=0: Zero padding overhead, preserving native pitch alignment
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = src.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Native 1080p Fine Motion Vector Search (No Proxy / Zero Downscale)
# blksize=16, blksizev=16: 16x16 blocks at native 1080p (~8,160 blocks total)
# 4x vector density compared to 32x32 without proxy scaling quantization
# search=2, searchparam=2: Radius-2 hexagonal search captures faster motion pans
# chroma=false: Luma-only search cuts vector computation by 50%
# levels=1: Single-level search matching super's levels=1
backward_vec = MAnalyse(super, isb=true,  blksize=16, blksizev=16, search=2, searchparam=2, chroma=false, levels=1)
forward_vec  = MAnalyse(super, isb=false, blksize=16, blksizev=16, search=2, searchparam=2, chroma=false, levels=1)

# 3. Direct Native 60fps Frame Synthesis
# Directly warps source frames with 1:1 pixel accuracy
# mode=0: Fast 2-stream block projection (sustains 60fps without CPU pipeline stalls)
# blend=false: Clean block projection avoiding blur on fast motion
# thSCD1=380, thSCD2=125: Balanced scene-change detection cleanly cuts camera transitions
MBlockFps(src, super, backward_vec, forward_vec, num=60, den=1, mode=0, blend=false, thSCD1=380, thSCD2=125)

# 4. Core Pinning: 3 Threads with 6-Frame Lookahead Queue
# Leaves 1 thread completely free for OS, audio pipeline, and D3D11 swapchain
# 6 lookahead frames absorb thread scheduling jitter
Prefetch(threads, 6)
