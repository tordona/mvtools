# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Generic x86-64 (Profile 1: Eco)
# Hardware: Generic 64-bit x86 (Intel Pentium/Celeron N-Series / Atom / Core / AMD)
# Target: Low-Power Fanless Budget Envelopes (~6W TDP e.g. N5000 / N4100 / N100)
# Architecture: Native 1080p Single-Super Wide-Block (Zero Resizing Overhead)
# Revision: 2.0.0 (2026-10-24)
# ==============================================================================

threads     = 2                   # Conservative 2 worker threads avoids overloading entry quad-cores
mem_limit   = 512

# Ultra-lean memory pool: safe for 4GB system RAM configurations
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded)
src = potplayer_source()

# Load MVTools2 plugin
LoadPlugin("mvtools2.dll")

# 1. Base Motion Super Clip (Single Level, Zero Resizing Overhead)
# levels=1: Single level avoids calculating redundant downscaled pyramid images
# pel=1: Whole-pixel precision eliminates subpixel interpolation overhead
# hpad=0, vpad=0: Zero padding to prevent CPU cache thrashing on low-end caches
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = src.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Ultra-Lightweight Wide-Block Motion Analysis
# blksize=64, blksizev=32: Rectangular 64x32 blocks cut block count to ~1,020 for 1080p
# search=2, searchparam=1: Radius-1 hexagonal search pattern (fast and stable)
# chroma=false: Evaluates luminance only, saving 50% vector computation
# levels=1: Strictly searches Level 0 (single level)
backward_vec = MAnalyse(super, isb=true,  blksize=64, blksizev=32, search=2, searchparam=1, chroma=false, levels=1)
forward_vec  = MAnalyse(super, isb=false, blksize=64, blksizev=32, search=2, searchparam=1, chroma=false, levels=1)

# 3. Direct Block-Based 60fps Synthesis
# mode=0: Fast block projection (least computationally intensive mode)
# blend=false: Avoids calculating blend transparency masks on fast motion
# thSCD1=400, thSCD2=130: Fast scene-change detection to immediately cut across scene changes
MBlockFps(src, super, backward_vec, forward_vec, num=60, den=1, mode=0, blend=false, thSCD1=400, thSCD2=130)

# 4. Strict Thread Limit with Lookahead Queue
# Leaves remaining CPU cores free for OS, audio decoding, and video renderer
Prefetch(threads, 4)
