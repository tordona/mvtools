# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Generic x86-64 (Profile 2: Balanced)
# Hardware: Generic 64-bit x86 (Intel Pentium/Celeron N-Series / Core i3/i5 / AMD)
# Target: Fluid 1080p 60 fps, Refined 16x16 Edges, Broad Compatibility Baseline
# Architecture: Native 1080p Coarse-to-Fine Refinement (Zero Resizing Overhead)
# Revision: 2.0.0 (2026-10-24)
# ==============================================================================

threads     = 3                   # 3 worker threads leaves 1 core free on quad-core CPUs
mem_limit   = 768

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded)
src = potplayer_source()

# Load MVTools2 plugin
LoadPlugin("mvtools2.dll")

# 1. Base Motion Super Clip (Single Level, Shared across Pipeline)
# levels=1: Avoids calculating redundant downscaled pyramid images
# pel=1: Whole-pixel base clip paired with MRecalculate keeps CPU low while tracking details
# hpad=0, vpad=0: Zero padding to prevent cache thrashing
# sharp=0: Fast bilinear interpolation
super = src.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Coarse Global Motion Vector Search (32x32 blocks, 2,040 blocks for 1080p)
# blksize=32, blksizev=32: Fast macro-motion detection
# search=2, searchparam=1: Hexagonal search with radius 1 keeps search lightweight
# badrange=(-24): Early rejection of outlier vectors to prevent haloing
# levels=1: Strictly searches Level 0 (single level)
backward_coarse = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=1, chroma=false, levels=1, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=1, chroma=false, levels=1, badrange=(-24))

# 3. Fine Refinement Pass (Refines vectors down to 16x16 at object boundaries)
# blksize=16, blksizev=16: Resolves small moving objects and eliminates blocky edge artifacts
backward_fine = MRecalculate(super, backward_coarse, blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)

# 4. Direct Frame Synthesis with Refined Vectors
# mode=0: Fast block projection using refined 16x16 vector grid (crisp, zero block tearing)
# blend=false: Skips blend transparency calculations to conserve ALU cycles
# thSCD1=380, thSCD2=125: Balanced scene-change detection cleanly cuts camera transitions
MBlockFps(src, super, backward_fine, forward_fine, num=60, den=1, mode=0, blend=false, thSCD1=380, thSCD2=125)

# 5. Core Allocation: 3 Threads with Lookahead Queue
# Leaves 1 core completely free for OS, audio, and video renderer
# 4 lookahead frames absorb thread scheduling jitter
Prefetch(threads, 4)
