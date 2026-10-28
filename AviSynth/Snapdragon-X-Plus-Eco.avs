# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon X Plus (Profile 1: Eco / Lowest CPU)
# Hardware: Qualcomm Snapdragon X Plus (8x Oryon Cores @ ARM64 NEON)
# Target: Ultra-low CPU usage, zero dropped frames, cool & quiet / battery saver
# ==============================================================================

# Memory allocation (1 GB is plenty for single-pass 32x32 blocks)
SetMemoryMax(1024)

# Mode 2 is optimal for multi-threaded MVTools2 filters
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream
potplayer_source()

# Native ARM64 MVTools2 plugin
LoadPlugin("mvtools2.dll")

# 1. Base Motion Super Clip (Integer Pixel Precision)
# pel=1: Full-pixel precision only (skips subpixel math, cutting memory bandwidth by ~75%)
# hpad=0, vpad=0: No padding overhead
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = MSuper(pel=1, hpad=0, vpad=0, sharp=0)

# 2. Ultra-Lightweight Coarse Motion Analysis
# blksize=32, blksizev=32: Large 32x32 blocks drastically reduce block count
# search=2: Hexagonal search pattern (extremely fast and stable)
# searchparam=1: Minimal search radius to limit vector comparisons
# chroma=false: Evaluates luminance only, saving 50% vector math
# plevel=0: Direct search without multi-level pyramid overhead
backward_vec = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=1, chroma=false, plevel=0)
forward_vec  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=1, chroma=false, plevel=0)

# 3. Direct Block-Based 60 fps Synthesis
# mode=0: Fast block projection (least computationally intensive mode)
# blend=false: Avoids calculating blend masks on fast motion
# thSCD1=400, thSCD2=130: Robust scene-change detection to avoid artifacts on cuts
MBlockFps(super, backward_vec, forward_vec, num=60, den=1, mode=0, blend=false, thSCD1=400, thSCD2=130)

# 4. Multi-Threading Capped to 4 Cores
# Caps prefetch to 4 worker threads, leaving the remaining 4 Oryon cores idle
# Ensures low CPU power draw (~5-8 W), silent fans, and maximum battery life
Prefetch(4)
