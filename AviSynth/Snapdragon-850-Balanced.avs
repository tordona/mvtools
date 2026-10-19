# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Snapdragon 850 (Profile 2: Balanced)
# Hardware: Qualcomm Snapdragon 850 (4x Kryo 385 Gold @ Cortex-A75, Adreno 630)
# Target: Fluid 1080p 60fps, Refined 16x16 Edges, Stable Thermal Ceiling
# Architecture: Native 1080p Coarse-to-Fine Refinement (Zero Resizing Overhead)
# Revision: 2.0.0 (2026-10-18)
# Changelog: Native 1080p, levels=1, coarse 32x32 -> fine 16x16, threads=3, Prefetch(3, 4), mem_limit=768
# ==============================================================================

threads     = 3                   # 3 Kryo 385 Gold cores
mem_limit   = 768

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded via Adreno 630)
src = potplayer_source()

# Load Native ARM64 MVTools2 plugin (ARM64 CPU NEON execution)
LoadPlugin("mvtools2.dll")

# 1. Base Motion Super Clip (Single Level, Shared across Pipeline)
# levels=1: Avoids calculating redundant downscaled pyramid images
# pel=1: Whole-pixel base clip paired with MRecalculate keeps CPU low while tracking details
# hpad=0, vpad=0: Zero padding to prevent cache thrashing on the 2 MB L3 cache
# sharp=0: Fast bilinear interpolation
super = src.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Coarse Global Motion Vector Search (32x32 blocks, 2,040 blocks for 1080p)
# blksize=32, blksizev=32: Fast macro-motion detection
# search=2, searchparam=1: Hexagonal search with radius 1 keeps search light on Cortex-A75
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

# 5. Core Pinning: Strictly 3 Threads with Lookahead Queue
# Utilizes 3 of the 4 Kryo 385 Gold cores.
# Leaves 1 Gold core + all 4 Silver cores completely free for OS, audio, and Adreno 630 GPU driver.
# 4 lookahead frames absorb thread scheduling jitter and prevent thermal throttling.
Prefetch(threads, 4)

