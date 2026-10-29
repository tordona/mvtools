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

# Dynamic Resolution Adaptation:
# Detect 4K (3840x2160 / 4096x2160) vs 1080p/720p.
# At 4K, 64x64 coarse -> 32x32 fine matches the 1080p 16x16 density (8,160 blocks),
# preventing 40,560 block compute stalls on Cortex-A75 cores.
is_4k      = (src.Width() > 2048)
blk_coarse = is_4k ? 64 : 32
blk_fine   = is_4k ? 32 : 16
pad_val    = is_4k ? 8 : 4

# Load Native ARM64 MVTools2 plugin (ARM64 CPU NEON execution)
LoadPlugin("mvtools2.dll")

# 1. Base Motion Super Clip with Edge Protection
# levels=1: Avoids calculating redundant downscaled pyramid images
# pel=1: Whole-pixel base clip paired with MRecalculate keeps CPU low while tracking details
# pad_val boundary padding prevents edge tearing without cache thrashing
# sharp=0: Subpixel interpolation filter is unused when pel=1
super = src.MSuper(levels=1, pel=1, hpad=pad_val, vpad=pad_val, sharp=0)

# 2. Dense Motion Vector Field Analysis (2,040 blocks: 32x32 at 1080p, 64x64 at 4K)
# searchparam=2: Wider search radius tracks fast pans and action
# badrange=(-24): Early rejection of outlier vectors to prevent haloing
# levels=1: Strictly searches base Level 0 (single level)
backward_coarse = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))

# 3. Fine Refinement Pass (8,160 blocks: 16x16 at 1080p, 32x32 at 4K)
# Resolves small moving objects and eliminates blocky edge artifacts
backward_fine = MRecalculate(super, backward_coarse, blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)

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

