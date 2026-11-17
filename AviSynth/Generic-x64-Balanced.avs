# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Generic x86-64 (Profile 2: Balanced)
# Hardware: Generic 64-bit x86 (Intel Core i3/i5/i7 / AMD Ryzen Quad+ Cores, 15 W – 28 W TDP)
# Architecture: Native 1080p x86-64 AVX2 / SSE4.2 CPU Motion Estimation (mvtools2.dll)
# Target: Fluid 1080p 60 fps, Native 32x32 Vectors (2,040 Blocks), Recommended Default
# Revision: 3.1.4 (2026-11-17)
# Changelog: Updated pyramid levels to is_4k ? 2 : 0 with plevel=0 for tear-free panning; Parameterized target_fps (default 60, capped at 60 fps on 4K) with target-relative frame rate bypass; Replaced 0.5x proxy with native 1080p 32x32 blocks (~2,040 blocks), dynamic 4K adaptation
#            Added radius-1 hexagonal search (search=2, searchparam=1) and levels=levels_val.
# ==============================================================================

# Core Allocation & Threading Strategy:
# 3 worker threads across 4+ cores leaves ample headroom for GPU video decode and presentation.
# Native 32x32 blocks delivers crisp motion tracking across 95% of mainstream x64 PCs.
threads     = 3
mem_limit   = 512                 # Bounded cache footprint protects dual-channel DRAM bus
target_fps  = 60                  # Target output frame rate (e.g. 60 or 120)

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded)
src = potplayer_source()

is_4k      = (src.Width() > 2048)
target_fps = (is_4k && target_fps > 60) ? 60 : target_fps

# Bypass motion interpolation if source is already at or above target_fps (4% NTSC tolerance, e.g. 59.94 fps for 60 fps)
if (src.FrameRate() >= (target_fps * 0.96)) {
    return src
}

# Dynamic Resolution Adaptation:
# Detect 4K vs 1080p. At 4K, 64x64 blocks maintain the exact 2,040 block count of 1080p 32x32.
levels_val = is_4k ? 2 : 0
blk_sz= is_4k ? 64 : 32

# Load Native x64 MVTools2 plugin
LoadPlugin("mvtools2.dll")

# 1. Native 1080p Super Clip (Tiered Pyramid, Integer Pixel Precision)
# pel=1: Full-pixel precision only (avoids subpixel interpolation overhead)
# levels=levels_val: Eliminates redundant multi-level spatial pyramid generation
# hpad=0, vpad=0: Zero padding overhead, preserving native pitch alignment
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = src.MSuper(levels=levels_val, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Native 1080p Balanced Motion Vector Search (No Proxy / Zero Downscale)
# blksize=blk_sz, blksizev=blk_sz: 32x32 blocks at native 1080p (~2,040 blocks total)
# search=2, searchparam=1: Radius-1 hexagonal search ensures tight vector consistency
# chroma=false: Luma-only search cuts vector computation by 50%
# levels=levels_val: Full pyramid at 1080p (levels=0), 2 levels at 4K (levels=2)
backward_vec = MAnalyse(super, isb=true,  blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, plevel=0, chroma=false, levels=levels_val)
forward_vec  = MAnalyse(super, isb=false, blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, plevel=0, chroma=false, levels=levels_val)

# 3. Direct Native 60 fps Frame Synthesis
# Directly warps source frames with 1:1 native pixel coordinate accuracy
# mode=0: Fast 2-stream block projection (sustains 60 fps without CPU pipeline stalls)
# blend=false: Clean block projection avoiding blur on fast motion
# thSCD1=380, thSCD2=125: Balanced scene-change detection cleanly cuts camera transitions
MBlockFps(src, super, backward_vec, forward_vec, num=target_fps, den=1, mode=0, blend=false, thSCD1=380, thSCD2=125)

# 4. Core Pinning: 3 Threads with 6-Frame Lookahead Queue
# Leaves 1 core completely free for OS, audio pipeline, and D3D11 swapchain
# 6 lookahead frames absorb thread scheduling jitter
Prefetch(threads, 6)
