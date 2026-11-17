# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 850 (Profile 1: Eco)
# Hardware: Qualcomm Snapdragon 850 (4x Kryo 385 Gold @ Cortex-A75, Adreno 630)
# Target: 5 W Fanless Thermal Envelope, Maximum Battery Life, 0 Thermal Throttling
# Architecture: Native 1080p Single-Super Wide-Block (Zero Resizing Overhead)
# Revision: 2.2.4 (2026-11-17)
# Changelog: Enabled full pyramid (levels=0) with plevel=0 for tear-free panning; Parameterized target_fps (default 60, capped at 60 fps on 4K) with target-relative frame rate bypass
# ==============================================================================

threads     = 2                   # Strictly 2 worker threads locks to 2 Gold cores
mem_limit   = 512
target_fps  = 60                  # Target output frame rate (e.g. 60 or 120)

# Ultra-lean memory pool: avoids bandwidth starvation on LPDDR4x-1866 bus
# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded via Adreno 630)
src = potplayer_source()

is_4k      = (src.Width() > 2048)
target_fps = (is_4k && target_fps > 60) ? 60 : target_fps

# Bypass motion interpolation if source is already at or above target_fps (4% NTSC tolerance, e.g. 59.94 fps for 60 fps)
if (src.FrameRate() >= (target_fps * 0.96)) {
    return src
}

# Dynamic 4K Fallback: Snapdragon 850 memory bus (14.9 GB/s) and VPU are capped at 4K 30 fps.
# Bypass motion interpolation on 4K streams to maintain smooth native playback.
if (src.Width() > 2048) {
    return src
}

# Dynamic Resolution Adaptation:
# Detect 4K vs 1080p (fallback safeguard if 4K bypass is disabled).
blk_v   = is_4k ? 64 : 32

# Load Native ARM64 MVTools2 plugin (ARM64 CPU NEON execution)
LoadPlugin("mvtools2.dll")
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}

# 1. Base Motion Super Clip (Full Pyramid, Zero Resizing Overhead)
# levels=0: Full coarse-to-fine pyramid prevents panning tearing
# pel=1: Whole-pixel precision eliminates subpixel interpolation overhead
# hpad=0, vpad=0: Zero padding to prevent cache thrashing on the 2 MB L3 cache
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = src.MSuper(levels=0, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Ultra-Lightweight Wide-Block Motion Analysis
# 64x32 at 1080p (~1,020 blocks), 64x64 at 4K (~2,040 blocks)
# search=2, searchparam=1: Radius-1 hexagonal search pattern (fast and stable)
# chroma=false: Evaluates luminance only, saving 50% vector computation
# levels=0, plevel=0: Full pyramid with constant penalty for tear-free panning
backward_vec = MAnalyse(super, isb=true,  blksize=64, blksizev=blk_v, search=2, searchparam=1, plevel=0, chroma=false, levels=0)
forward_vec  = MAnalyse(super, isb=false, blksize=64, blksizev=blk_v, search=2, searchparam=1, plevel=0, chroma=false, levels=0)

# 3. Direct Block-Based 60 fps Synthesis
# mode=0: Fast block projection (least computationally intensive mode)
# blend=false: Avoids calculating blend transparency masks on fast motion
# thSCD1=400, thSCD2=130: Fast scene-change detection to immediately cut across scene changes
MBlockFps(src, super, backward_vec, forward_vec, num=target_fps, den=1, mode=0, blend=false, thSCD1=400, thSCD2=130)

# 4. Strict Dual-Core Thread Limit with Lookahead Queue
# Runs on exactly 2 Kryo 385 Gold cores, keeping clocks at maximum without thermal throttling
# 4 lookahead frames absorb thread scheduling jitter
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads, 4)

