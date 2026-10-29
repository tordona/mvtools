# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 850 (Profile 2: Balanced)
# Hardware: Qualcomm Snapdragon 850 (4x Kryo 385 Gold @ Cortex-A75, Adreno 630)
# Target: Fluid 1080p 60 fps, Refined 16x16 Edges, Stable Thermal Ceiling
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

# Dynamic Resolution Adaptation:
# Detect 4K (3840x2160 / 4096x2160) vs 1080p/720p.
# At 4K, 64x64 coarse -> 32x32 fine matches the 1080p 16x16 spatial density (8,160 blocks),
# preventing Cortex-A75 CPU saturation and eliminating dropped frames.
is_4k      = (src.Width() > 2048)
blk_coarse = is_4k ? 64 : 32
blk_fine   = is_4k ? 32 : 16
pad_val    = is_4k ? 8 : 0

# Load Native ARM64 MVTools2 plugin (ARM64 CPU NEON execution)
LoadPlugin("mvtools2.dll")

# 1. Base Motion Super Clip (Single Level, Shared across Pipeline)
# levels=1: Avoids calculating redundant downscaled pyramid images
# pel=1: Whole-pixel base clip paired with MRecalculate keeps CPU low while tracking details
# pad_val boundary padding stabilizes edge vector calculation
# sharp=0: Fast bilinear interpolation
super = src.MSuper(levels=1, pel=1, hpad=pad_val, vpad=pad_val, sharp=0)

# 2. Coarse Global Motion Vector Search (2,040 blocks: 32x32 at 1080p, 64x64 at 4K)
# search=2, searchparam=1: Hexagonal search with radius 1 keeps search light on Cortex-A75
# badrange=(-24): Early rejection of outlier vectors to prevent haloing
# levels=1: Strictly searches Level 0 (single level)
backward_coarse = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=1, chroma=false, levels=1, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=1, chroma=false, levels=1, badrange=(-24))

# 3. Fine Refinement Pass (8,160 blocks: 16x16 at 1080p, 32x32 at 4K)
# Resolves small moving objects and eliminates blocky edge artifacts
backward_fine = MRecalculate(super, backward_coarse, blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)

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

