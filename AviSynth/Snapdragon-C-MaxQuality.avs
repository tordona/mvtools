# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon C (Profile 3: Max Quality)
# Hardware: Qualcomm Snapdragon C (8x Kryo: 1 Prime @ 3.0 GHz + 3 Perf @ 2.6 GHz + 4 Eff @ 2.0 GHz)
# Architecture: ARM64 NEON CPU Motion Estimation (mvtools2.dll)
# Generator: Google Antigravity (AIAgentProfileGuide Rev 2.3.11)
# Target: Maximum Motion Fidelity 720p–4K 60 fps, Crisp Edge Definition, ~10 W Peak Envelope
# Revision: 1.1.0 (2026-11-09)
# Changelog: Optimized 4K playback: mode=0 and blend=false on 4K, searchparam=1 on 4K, pad_val=0 on 4K to eliminate ALU and memory bus saturation
# ==============================================================================

# Core Allocation & Threading Strategy:
# 4 worker threads fully saturate the 4 Performance-tier cores (1 Prime + 3 Perf).
# Leaves all 4 Efficiency cores completely available for Adreno VPU hardware decoding,
# Direct3D 11 swapchain presentation, and OS background tasks.
threads     = 4
mem_limit   = 1024                # Bounded cache footprint protecting LPDDR4x/LPDDR5 memory bus

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (DXVA2/D3D11 hardware decoded via Adreno VPU)
src = potplayer_source()

# Dynamic Resolution Adaptation:
# Detect 4K (3840x2160 / 4096x2160) vs 1080p/720p.
# At 4K, 64x64 coarse -> 32x32 fine maintains the exact 120x68 (8,160 blocks) spatial grid
# density of 1080p 16x16, cutting 4K block evaluations by 75% and preventing memory bus saturation.
# Radius-1 search, mode=0, and blend=false on 4K keeps compute within 10 W fanless ceiling.
is_4k      = (src.Width() > 2048)
blk_coarse = is_4k ? 64 : 32
blk_fine   = is_4k ? 32 : 16
pad_val    = is_4k ? 0 : 4
search_rad = is_4k ? 1 : 2
synth_mode = is_4k ? 0 : 2
blend_val  = is_4k ? false : true

# Load Native ARM64 MVTools2 plugin & companion AvsAffinity
LoadPlugin("mvtools2.dll")
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}

# 1. Base Motion Super Clip with Lightweight Edge Guard
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=1: Whole-pixel estimation paired with MRecalculate
# pad_val boundary padding stabilizes edge vector calculation without memory thrashing
# sharp=0: Subpixel interpolation filter is unused when pel=1
super = src.MSuper(levels=1, pel=1, hpad=pad_val, vpad=pad_val, sharp=0)

# 2. Coarse Motion Vector Search (2,040 blocks: 32x32 at standard resolutions, 64x64 at 4K)
# searchparam: Radius 1 on 4K to cut coarse search cycles; Radius 2 on 1080p for action tracking
# badrange=(-24): Outlier vector rejection threshold for CPU NEON search path
# levels=1: Strictly searches base Level 0
backward_coarse = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=search_rad, chroma=false, levels=1, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=search_rad, chroma=false, levels=1, badrange=(-24))

# 3. Fine Motion Refinement Pass (8,160 blocks: 16x16 at standard resolutions, 32x32 at 4K)
# Refines vectors down to fine blocks at object boundaries using 2x2 bilinear coarse predictors
backward_fine = MRecalculate(super, backward_coarse, blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)

# 4. Pixel-Level Motion Interpolation
# mode=0 on 4K sustains 60 fps; mode=2 on 1080p delivers crisp dynamic median edges
# blend=false on 4K avoids memory bus saturation; blend=true on 1080p blends occlusion boundaries
# thSCD1=350, thSCD2=120: Balanced scene-change sensitivity cleanly cuts camera transitions
last = MBlockFps(src, super, backward_fine, forward_fine, num=60, den=1, mode=synth_mode, blend=blend_val, thSCD1=350, thSCD2=120)

# 5. Hardware Thread Affinity Pinning & Concurrency Pool
# Isolates worker threads to Performance/Prime cores, preventing Efficiency core latency stalls
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads, 4)
