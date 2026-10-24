# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Generic x86-64 (Profile 3: Max Quality)
# Hardware: Generic 64-bit x86 (Intel Core i5/i7/i9 / AMD Ryzen / High-Clock Quad+)
# Target: Subpixel Precision, Occlusion Handling, Crisp Motion Edges
# Revision: 2.0.0 (2026-10-24)
# ==============================================================================

threads     = 4                   # 4 worker threads for standard quad/multi-core x86
mem_limit   = 1024

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded)
src = potplayer_source()

# Load MVTools2 plugin
LoadPlugin("mvtools2.dll")

# 1. High-Precision Subpixel Motion Super Clip
# pel=2: Half-pixel subpixel interpolation for fine-grained motion vectors
# hpad=8, vpad=8: Boundary padding stabilizes vectors near image borders
# sharp=1: Bicubic interpolation for clean vector estimation
super = src.MSuper(pel=2, hpad=8, vpad=8, sharp=1)

# 2. Coarse Motion Vector Field Analysis
# blksize=32: Fast macro-motion detection
# search=2, searchparam=2: Hexagonal search with radius 2
backward_coarse = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, badrange=(-24))

# 3. Fine Motion Refinement Pass (Refines vectors down to 16x16)
backward_fine = MRecalculate(super, backward_coarse, blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)

# 4. Pixel-Level Motion Interpolation with Occlusion Handling
# mode=2: Pixel-flow synthesis removes block artifacts
# blend=true: Graceful fallback blending for fast complex motions or occluded areas
# thSCD1=350, thSCD2=120: Balanced scene change detection
MBlockFps(src, super, backward_fine, forward_fine, num=60, den=1, mode=2, blend=true, thSCD1=350, thSCD2=120)

# 5. Thread Pool with Lookahead Queue
Prefetch(threads, 4)
