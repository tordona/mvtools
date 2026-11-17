# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 850 (Profile 3: Max Quality)
# Hardware: Qualcomm Snapdragon 850 (4x Kryo 385 Gold @ Cortex-A75, Adreno 630)
# Target: Highest Quality Motion Flow within 5 W Snapdragon 850 Thermal Budget
# Architecture: Native 1080p Quad-Core Saturation (Zero Resizing Overhead)
# Revision: 2.2.4 (2026-11-17)
# Changelog: Enabled full pyramid (levels=0) with plevel=0, threads=3, searchparam=1, and Prefetch(3, 6) to eliminate horizontal pan stutter; Parameterized target_fps (default 60, capped at 60 fps on 4K) with target-relative frame rate bypass
# ==============================================================================

threads     = 3                   # Leaves 1 Kryo 385 Gold core free for DWM/PotPlayer presentation
mem_limit   = 768
target_fps  = 60                  # Target output frame rate (e.g. 60 or 120)

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
# Detect 4K (3840x2160 / 4096x2160) vs 1080p/720p (fallback safeguard if 4K bypass is disabled).
blk_coarse = is_4k ? 64 : 32
blk_fine   = is_4k ? 32 : 16
pad_val    = is_4k ? 8 : 4

# Load Native ARM64 MVTools2 plugin (ARM64 CPU NEON execution)
LoadPlugin("mvtools2.dll")
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}

# 1. Base Motion Super Clip with Edge Protection
# levels=0: Full coarse-to-fine pyramid prevents panning tearing
# pel=1: Whole-pixel base clip paired with MRecalculate keeps CPU low while tracking details
# pad_val boundary padding prevents edge tearing without cache thrashing
# sharp=0: Subpixel interpolation filter is unused when pel=1
super = src.MSuper(levels=0, pel=1, hpad=pad_val, vpad=pad_val, sharp=0)

# 2. Dense Motion Vector Field Analysis (2,040 blocks: 32x32 at 1080p, 64x64 at 4K)
# searchparam=1: Coarse pyramid already tracks wide pans; radius-1 avoids pan-stutter spikes
# badrange=(-24): Early rejection of outlier vectors to prevent haloing
# levels=0, plevel=0: Full pyramid with constant penalty for tear-free panning
backward_coarse = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=1, plevel=0, chroma=false, levels=0, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=1, plevel=0, chroma=false, levels=0, badrange=(-24))

# 3. Fine Refinement Pass (8,160 blocks: 16x16 at 1080p, 32x32 at 4K)
# Resolves small moving objects and eliminates blocky edge artifacts
backward_fine = MRecalculate(super, backward_coarse, blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)

# 4. Direct Frame Synthesis
# mode=0: Fast 2-stream block projection sustains 60 fps without CPU pipeline stalls
# blend=false: Skips blend transparency calculations to conserve ALU cycles
# thSCD1=350, thSCD2=120: Balanced scene-change detection cleanly cuts camera transitions
MBlockFps(src, super, backward_fine, forward_fine, num=target_fps, den=1, mode=0, blend=false, thSCD1=350, thSCD2=120)

# 5. Core Pinning: Strictly 3 Threads with 6-Frame Lookahead Queue
# Leaves 1 Kryo 385 Gold core free for OS, audio, and DWM presentation.
# IMPORTANT: Never set Prefetch > 4 on Snapdragon 850; spilling to Cortex-A55 cores causes severe stutter.
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads, 6)

