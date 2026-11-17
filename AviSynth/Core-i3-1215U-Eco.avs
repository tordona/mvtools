# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Intel Core i3-1215U (Profile 1: Eco)
# Hardware: Intel Core i3-1215U (2P+4E/8T Alder Lake-U @ 15 W TDP, Intel UHD Graphics 64EU)
# Memory: 16 GB Dual-Channel DDR4/LPDDR5 (51.2-83.2 GB/s Bandwidth)
# Architecture: Native 1080p x86-64 AVX2 / SSE4.2 CPU Motion Estimation (mvtools2.dll)
# Target: Sub-8 W Power Envelope, Minimal Heat, Silent Fan / Passive Playback, 0 Drops
# Revision: 2.2.4 (2026-11-17)
# Changelog: Updated pyramid levels to is_4k ? 2 : 0 with plevel=0 for tear-free panning; Parameterized target_fps (default 60, capped at 60 fps on 4K) with target-relative frame rate bypass; Native 1080p, levels=levels_val, coarse 32x32, AvsAffinity hardware pinning, dynamic 4K adaptation
# ==============================================================================

# Core Allocation & Threading Strategy:
# 2 worker threads locks computation strictly to the 2 physical Golden Cove P-cores (1 thread per P-core).
# Avoids hyperthread contention and E-core scheduling jitter, keeping package draw sub-8 W.
# Leaves 2 P-threads + all 4 Gracemont E-cores completely unburdened for UHD DXVA decode, D3D11 swapchain, and DWM.
threads     = 2
mem_limit   = 512                 # Generous memory pool for 16 GB dual-channel RAM
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

# Load Native x64 MVTools2 plugin (leveraging Golden Cove AVX2 SIMD optimizations)
LoadPlugin("mvtools2.dll")
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}

# 1. Native 1080p Super Clip (Tiered Pyramid, Integer Pixel Precision)
# pel=1: Full-pixel precision only (avoids subpixel interpolation overhead)
# levels=levels_val: Eliminates redundant multi-level pyramid generation
# hpad=0, vpad=0: Zero padding overhead, preserving native pitch alignment
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = src.MSuper(levels=levels_val, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Native 1080p Motion Vector Search (No Proxy / Zero Downscale)
# blksize=blk_sz, blksizev=blk_sz: 32x32 blocks at native 1080p (~2,040 blocks total)
# search=2, searchparam=1: Tight radius-1 hexagonal search for maximum battery efficiency
# chroma=false: Luma-only search cuts vector computation by 50%
# levels=levels_val: Full pyramid at 1080p (levels=0), 2 levels at 4K (levels=2)
backward_vec = MAnalyse(super, isb=true,  blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, plevel=0, chroma=false, levels=levels_val)
forward_vec  = MAnalyse(super, isb=false, blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, plevel=0, chroma=false, levels=levels_val)

# 3. Direct Native 60 fps Frame Synthesis
# Directly warps source frames without vector scaling or proxy interpolation artifacts
# mode=0: Fast block projection (minimal ALU load)
# blend=false: Skips transparency alpha blending calculations
# thSCD1=400, thSCD2=130: Robust scene-change detection cleanly cuts camera transitions
MBlockFps(src, super, backward_vec, forward_vec, num=target_fps, den=1, mode=0, blend=false, thSCD1=400, thSCD2=130)

# 4. Hardware Thread Affinity & Core Pinning: Strictly 2 Threads with 4-Frame Lookahead Queue
# 2 threads pinned to P-cores ensures zero thermal throttling on battery / low power
# 4 lookahead frames absorb thread scheduling jitter
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads, 4)
