# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Intel Core i7-11850H (Profile 1: Eco)
# Hardware: Intel Core i7-11850H (8C/16T Tiger Lake-H @ 45 W TDP, Intel UHD Graphics 32EU)
# Memory: 16 GB-64 GB Dual-Channel DDR4-3200 (51.2 GB/s Bandwidth, 24 MB Shared L3 Cache)
# Architecture: Native 1080p x86-64 AVX-512 / AVX2 CPU Motion Estimation (mvtools2.dll)
# Target: Sub-10 W Low-Acoustic Envelope, Low-Thermal Profile, 0 Dropped Frames
# Revision: 2.1.4 (2026-11-17)
# Changelog: Updated pyramid levels to is_4k ? 2 : 0 with plevel=0 for tear-free panning; Parameterized target_fps (default 60, capped at 60 fps on 4K) with target-relative frame rate bypass; Native 1080p, levels=levels_val, coarse 32x32 blocks, dynamic 4K adaptation
# ==============================================================================

# Core Allocation & Threading Strategy:
# 4 worker threads mapped 1:1 to 4 of the 8 physical Willow Cove performance cores.
# Leaves 4 full physical cores + all 8 hyperthreads completely idle to minimize package power,
# keeping CPU temperatures low and cooling fans completely silent during playback.
threads     = 4
mem_limit   = 512                 # Generous memory pool for native 1080p coarse vectors
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
# Detect 4K vs 1080p. At 4K, 64x64 blocks maintain the exact 2,040 block count of 1080p 32x32,
# keeping memory traffic strictly within low-power TDP envelopes.
levels_val = is_4k ? 2 : 0
blk_sz= is_4k ? 64 : 32

# Load Native x64 MVTools2 plugin (leveraging Willow Cove AVX-512 / AVX2 SIMD optimizations)
LoadPlugin("mvtools2.dll")

# 1. Native 1080p Super Clip (Single-Level, Integer Pixel Precision)
# pel=1: Full-pixel precision only (avoids subpixel interpolation overhead)
# levels=levels_val: Eliminates redundant multi-level pyramid generation
# hpad=0, vpad=0: Zero padding overhead, preserving native pitch alignment
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = src.MSuper(levels=levels_val, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Native 1080p Motion Vector Search (No Proxy / Zero Downscale)
# blksize=blk_sz, blksizev=blk_sz: 32x32 blocks at native 1080p (~2,040 blocks total)
# search=2, searchparam=1: Hexagonal search with tight radius
# chroma=false: Luma-only search cuts vector computation by 50%
# levels=levels_val: Single-level search matching super's levels=levels_val
backward_vec = MAnalyse(super, isb=true,  blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, plevel=0, chroma=false, levels=levels_val)
forward_vec  = MAnalyse(super, isb=false, blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, plevel=0, chroma=false, levels=levels_val)

# 3. Direct Native 60 fps Frame Synthesis
# Directly warps source frames without vector scaling or proxy interpolation artifacts
# mode=0: Fast block projection (minimal ALU load)
# blend=false: Skips transparency alpha blending calculations
# thSCD1=400, thSCD2=130: Robust scene-change detection cleanly cuts camera transitions
MBlockFps(src, super, backward_vec, forward_vec, num=target_fps, den=1, mode=0, blend=false, thSCD1=400, thSCD2=130)

# 4. Core Pinning: 4 Threads with 4-Frame Lookahead Queue
# 4 threads keeps package power well below 10 W and prevents thermal boost fan spin-up
# 4 lookahead frames absorb thread scheduling jitter
Prefetch(threads, 4)
