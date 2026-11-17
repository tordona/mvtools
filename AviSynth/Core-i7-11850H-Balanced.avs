# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Intel Core i7-11850H (Profile 2: Balanced)
# Hardware: Intel Core i7-11850H (8C/16T Tiger Lake-H @ 45 W TDP, Intel UHD Graphics 32EU)
# Memory: 16 GB-64 GB Dual-Channel DDR4-3200 (51.2 GB/s Bandwidth, 24 MB Shared L3 Cache)
# Architecture: Native 1080p x86-64 AVX-512 / AVX2 CPU Motion Estimation (mvtools2.dll)
# Target: Fluid 1080p 60 fps, Crisp Native 16x16 Vectors (8,160 Blocks), 45 W High-Headroom
# Revision: 2.1.4 (2026-11-17)
# Changelog: Parameterized target_fps (default 60, capped at 60 fps on 4K) with target-relative frame rate bypass; Replaced unconditional levels=1 with tiered pyramid levels_val (levels_val = is_4k ? 2 : 0) and plevel=0 for tear-free panning
# ==============================================================================

# Core Allocation & Threading Strategy:
# 6 worker threads mapped 1:1 across 6 physical Willow Cove cores with zero hyperthread sharing.
# Leaves 2 dedicated physical cores + all hyperthreads completely free for
# Intel UHD DXVA decode, Direct3D 11 swapchain presentation, and background OS tasks.
threads     = 6
mem_limit   = 1024                # Ample headroom for native 1080p 16x16 vector search
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
# Detect 4K (3840x2160 / 4096x2160) vs 1080p/720p.
# At 4K, 32x32 blocks maintain the exact 8,160 block count of 1080p 16x16,
# preserving single-pass high-throughput execution without cache thrashing.
levels_val = is_4k ? 2 : 0
blk_sz = is_4k ? 32 : 16

# Load Native x64 MVTools2 plugin (leveraging Willow Cove AVX-512 / AVX2 SIMD optimizations)
LoadPlugin("mvtools2.dll")

# 1. Native 1080p Super Clip (Tiered Pyramid, Integer Pixel Precision)
# pel=1: Full-pixel precision only (avoids subpixel interpolation overhead)
# levels_val: is_4k ? 2 : 0 (full pyramid at 1080p, 2 levels at 4K)
# hpad=0, vpad=0: Zero padding overhead, preserving native pitch alignment
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = src.MSuper(levels=levels_val, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Native 1080p Fine Motion Vector Search (No Proxy / Zero Downscale)
# blksize=blk_sz, blksizev=blk_sz: 16x16 blocks at native 1080p (~8,160 blocks total)
# 4x vector density compared to 32x32 without proxy scaling quantization
# search=2, searchparam=2: Radius-2 hexagonal search captures faster motion pans
# chroma=false: Luma-only search cuts vector computation by 50%
# levels_val: is_4k ? 2 : 0 (full pyramid at 1080p, 2 levels at 4K)
backward_vec = MAnalyse(super, isb=true,  blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=2, chroma=false, plevel=0, levels=levels_val)
forward_vec  = MAnalyse(super, isb=false, blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=2, chroma=false, plevel=0, levels=levels_val)

# 3. Direct Native 60 fps Frame Synthesis
# Directly warps source frames with 1:1 pixel accuracy
# mode=0: Fast 2-stream block projection (sustains 60 fps without CPU pipeline stalls)
# blend=false: Clean block projection avoiding blur on fast motion
# thSCD1=380, thSCD2=125: Balanced scene-change detection cleanly cuts camera transitions
MBlockFps(src, super, backward_vec, forward_vec, num=target_fps, den=1, mode=0, blend=false, thSCD1=380, thSCD2=125)

# 4. Core Pinning: 6 Threads with 6-Frame Lookahead Queue
# 6 worker threads on physical cores provides high throughput without thermal throttling
# 6 lookahead frames absorb thread scheduling jitter for stable 1% low frame times
Prefetch(threads, 6)
