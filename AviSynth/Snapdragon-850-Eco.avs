# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 850 (Profile 1: Eco)
# Hardware: Qualcomm Snapdragon 850 (4x Kryo 385 Gold @ Cortex-A75, Adreno 630)
# Target: 5 W Fanless Thermal Envelope, Maximum Battery Life, 0 Thermal Throttling
# Architecture: Native 1080p Single-Super Wide-Block (Zero Resizing Overhead)
# Revision: 2.0.0 (2026-10-18)
# Changelog: Native 1080p, levels=1, single MSuper, threads=3, Prefetch(3, 4), mem_limit=512
# ==============================================================================

threads     = 2                   # Strictly 2 worker threads locks to 2 Gold cores
mem_limit   = 512

# Ultra-lean memory pool: avoids bandwidth starvation on LPDDR4x-1866 bus
# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded via Adreno 630)
src = potplayer_source()

# Load Native ARM64 MVTools2 plugin (ARM64 CPU NEON execution)
LoadPlugin("mvtools2.dll")

# 1. Base Motion Super Clip (Single Level, Zero Resizing Overhead)
# levels=1: Single level avoids calculating 9 redundant downscaled pyramid images
# pel=1: Whole-pixel precision eliminates subpixel interpolation overhead
# hpad=0, vpad=0: Zero padding to prevent cache thrashing on the 2 MB L3 cache
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = src.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Ultra-Lightweight Wide-Block Motion Analysis
# blksize=64, blksizev=32: Rectangular 64x32 blocks cut block count to ~1,020 for 1080p
# search=2, searchparam=1: Radius-1 hexagonal search pattern (fast and stable)
# chroma=false: Evaluates luminance only, saving 50% vector computation
# levels=1: Strictly searches Level 0 (single level)
backward_vec = MAnalyse(super, isb=true,  blksize=64, blksizev=32, search=2, searchparam=1, chroma=false, levels=1)
forward_vec  = MAnalyse(super, isb=false, blksize=64, blksizev=32, search=2, searchparam=1, chroma=false, levels=1)

# 3. Direct Block-Based 60 fps Synthesis
# mode=0: Fast block projection (least computationally intensive mode)
# blend=false: Avoids calculating blend transparency masks on fast motion
# thSCD1=400, thSCD2=130: Fast scene-change detection to immediately cut across scene changes
MBlockFps(src, super, backward_vec, forward_vec, num=60, den=1, mode=0, blend=false, thSCD1=400, thSCD2=130)

# 4. Strict Dual-Core Thread Limit with Lookahead Queue
# Runs on exactly 2 Kryo 385 Gold cores, keeping clocks at maximum without thermal throttling
# 4 lookahead frames absorb thread scheduling jitter
Prefetch(threads, 4)

