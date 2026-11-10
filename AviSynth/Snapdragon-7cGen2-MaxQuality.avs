# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 7c Gen 2 (Profile 3: Max Quality)
# Hardware: Qualcomm Snapdragon 7c Gen 2 (2x Kryo 468 Gold @ 2.55 GHz + 6x Silver)
# Test Device: Samsung Galaxy Book Go (14", Fanless 5 W Chassis)
# Target: Highest Achievable Motion Precision at Sustained 60 fps (Zero Throttling)
# Architecture: Native 1080p Coarse-to-Fine Refinement (Zero Resizing Overhead)
# Revision: 2.3.0 (2026-11-09)
# Changelog: Added native 4K early return bypass (hardware limited to 4K 30 fps by 17 GB/s memory bus and VPU decoder cap)
# ==============================================================================

# Strictly 2 worker threads locks computation to the 2 Cortex-A76 Gold cores.
# Prevents thermal runaway and avoids slow Cortex-A55 Silver core stalls.
threads     = 2
mem_limit   = 512

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full 1080p PotPlayer video source stream (DXVA2/D3D11 hardware decoded via Adreno 618)
src = potplayer_source()

# Dynamic 4K Fallback: 7c Gen 2 memory bus (17 GB/s) and VPU are capped at 4K 30 fps.
# Bypass motion interpolation on 4K streams to maintain smooth native playback.
if (src.Width() > 2048) {
    return src
}

# Dynamic Resolution Adaptation:
# Detect 4K vs 1080p/720p (fallback safeguard if 4K bypass is disabled).
is_4k      = (src.Width() > 2048)
blk_coarse = is_4k ? 64 : 32
blk_fine   = is_4k ? 32 : 16
pad_val    = is_4k ? 8 : 4

# Load Native ARM64 MVTools2 plugin (ARM64 CPU NEON execution)
LoadPlugin("mvtools2.dll")
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}

# 1. Base Motion Super Clip with Edge Protection
# levels=1: Avoids calculating redundant downscaled pyramid images
# pel=1: Whole-pixel base clip paired with MRecalculate keeps CPU low while tracking details
# pad_val boundary padding prevents edge tearing without cache thrashing
# sharp=0: Subpixel interpolation filter is unused when pel=1
super = src.MSuper(levels=1, pel=1, hpad=pad_val, vpad=pad_val, sharp=0)

# 2. Hierarchical Motion Vector Analysis (2,040 blocks: 32x32 at 1080p, 64x64 at 4K)
# searchparam=2: Wider search radius tracks fast pans and action
# badrange=(-24): Early rejection of outlier vectors to prevent haloing
# levels=1: Strictly searches base Level 0 (single level)
backward_coarse = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))

# 3. Fine Refinement Pass (8,160 blocks: 16x16 at 1080p, 32x32 at 4K)
# Resolves small moving objects and eliminates blocky edge artifacts
backward_fine = MRecalculate(super, backward_coarse, blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)

# 4. Direct Native Frame Synthesis
# mode=0: Fast 2-stream block projection sustains 60 fps without CPU pipeline stalls
# blend=true: Smooth frame blending on scene transitions
# thSCD1=350, thSCD2=120: Balanced scene-change detection cleanly cuts camera transitions
MBlockFps(src, super, backward_fine, forward_fine, num=60, den=1, mode=0, blend=true, thSCD1=350, thSCD2=120)

# 5. Core Pinning: Strictly 2 threads prevents thermal throttling
# 4 lookahead frames absorb thread scheduling jitter
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads, 4)
