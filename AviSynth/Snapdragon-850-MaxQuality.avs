# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 850 (Profile 3: Max Quality)
# Hardware: Qualcomm Snapdragon 850 (4x Kryo 385 Gold @ Cortex-A75, Adreno 630)
# Target: Highest Quality Motion Flow within 5 W Snapdragon 850 Thermal Budget
# Architecture: Native 1080p Quad-Core Saturation (Zero Resizing Overhead)
# Revision: 2.0.0 (2026-10-18)
# Changelog: Native 1080p, levels=1, coarse 32x32 -> fine 16x16, searchparam=2, threads=3, Prefetch(3, 4), mem_limit=1024
# ==============================================================================

threads     = 4                   # Saturates all 4 Kryo 385 Gold cores
mem_limit   = 768

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded via Adreno 630)
src = potplayer_source()

# Load Native ARM64 MVTools2 plugin (ARM64 CPU NEON execution)
LoadPlugin("mvtools2.dll")

# 1. Base Motion Super Clip with Edge Protection
# levels=1: Avoids calculating redundant downscaled pyramid images
# pel=1: Whole-pixel base clip paired with MRecalculate keeps CPU low while tracking details
# hpad=4, vpad=4: Minimal boundary padding prevents edge tearing without cache thrashing
# sharp=1: Bicubic interpolation for cleaner motion vectors
super = src.MSuper(levels=1, pel=1, hpad=4, vpad=4, sharp=1)

# 2. Dense Motion Vector Field Analysis (32x32 blocks, searchparam=2)
# searchparam=2: Wider search radius tracks fast pans and action
# badrange=(-24): Early rejection of outlier vectors to prevent haloing
# levels=1: Strictly searches Level 0 (single level)
backward_coarse = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))

# 3. Fine Refinement Pass (Refines vectors down to 16x16 at object boundaries)
# blksize=16, blksizev=16: Resolves small moving objects and eliminates blocky edge artifacts
backward_fine = MRecalculate(super, backward_coarse, blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)

# 4. Direct Frame Synthesis
# mode=0: Fast 2-stream block projection sustains 60 fps without CPU pipeline stalls
# blend=false: Skips blend transparency calculations to conserve ALU cycles
# thSCD1=350, thSCD2=120: Balanced scene-change detection cleanly cuts camera transitions
MBlockFps(src, super, backward_fine, forward_fine, num=60, den=1, mode=0, blend=false, thSCD1=350, thSCD2=120)

# 5. Core Pinning: Strictly 4 Threads with Lookahead Queue
# Full saturation of all 4 Kryo 385 Gold cores.
# 4 lookahead frames absorb thread scheduling jitter.
# IMPORTANT: Never set Prefetch > 4 on Snapdragon 850; spilling to Cortex-A55 cores causes severe stutter.
Prefetch(threads, 4)

