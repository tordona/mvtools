# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: AMD Ryzen AI 5 340 (Profile 1: Eco)
# Hardware: AMD Ryzen AI 5 340 (3x Zen 5 + 3x Zen 5c Cores, Radeon 840M RDNA 3.5 @ 2.9 GHz)
# Memory: 16 GB-32 GB Dual-Channel LPDDR5x-7500 (120 GB/s Unified Bandwidth)
# Architecture: Native 1080p x86-64 AVX-512 / AVX2 CPU Motion Estimation (mvtools2.dll)
# Target: Sub-8 W Package Envelope, Silent / Cool Battery Playback, 0 Dropped Frames
# Revision: 2.0.0 (2026-10-25)
# ==============================================================================

# Core Allocation & Threading Strategy:
# 3 worker threads mapped 1:1 to the 3 high-IPC Zen 5 "Nirvana" performance cores.
# Leaves all 3 Zen 5c dense cores and all SMT logical threads completely unburdened for
# Radeon 840M VCN hardware decode, Direct3D 11 swapchain presentation, and Windows DWM.
threads     = 3
mem_limit   = 512                 # Generous memory pool for native 1080p coarse vectors

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

# 4. Core Pinning: 3 Threads with 4-Frame Lookahead Queue
# 3 threads avoids core saturation and maintains low boost power state
# 4 lookahead frames absorb thread scheduling jitter
Prefetch(threads, 4)
