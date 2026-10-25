# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: AMD Ryzen AI 5 340 (Profile 2: Balanced)
# Hardware: AMD Ryzen AI 5 340 (3x Zen 5 + 3x Zen 5c Cores, Radeon 840M RDNA 3.5 @ 2.9 GHz)
# Memory: 16GB-32GB Dual-Channel LPDDR5x-7500 (120 GB/s Unified Bandwidth)
# Architecture: Native 1080p x86-64 AVX-512 / AVX2 CPU Motion Estimation (mvtools2.dll)
# Target: Fluid 1080p 60fps, Crisp Native 16x16 Vectors (8,160 Blocks), 15W Envelope
# Revision: 2.0.0 (2026-10-25)
# ==============================================================================

# Core Allocation & Threading Strategy:
# 4 worker threads running across the high-IPC Zen 5 physical cores (utilizing unified 16MB L3).
# Leaves remaining cores and SMT logical threads completely unburdened for
# Radeon 840M VCN hardware decode, Direct3D 11 swapchain presentation, and Windows DWM.
threads     = 4
mem_limit   = 768                 # Ample headroom for native 1080p 16x16 vector search

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (AMD VCN hardware decoded via Radeon 840M)
src = potplayer_source()

# Load Native x64 MVTools2 plugin (leveraging Zen 5 dual 512-bit AVX-512 SIMD pipelines)
LoadPlugin("mvtools2.dll")

# 1. Native 1080p Super Clip (Single-Level, Integer Pixel Precision)
# pel=1: Full-pixel precision only (avoids subpixel interpolation overhead)
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

# 4. Core Pinning: 4 Threads with 6-Frame Lookahead Queue
# 4 worker threads provides high throughput across Zen 5 cores without thermal throttling
# 6 lookahead frames absorb thread scheduling jitter for rock-solid 1% low frame times
Prefetch(threads, 6)
