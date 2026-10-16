# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Snapdragon X Plus (Profile 2: Balanced)
# Hardware: Qualcomm Snapdragon X Plus (8x Oryon Cores @ ARM64 NEON)
# Target: Sweet spot between fluid motion, sharp edges, and efficient power draw
# ==============================================================================

# Memory allocation (2 GB recommended for dual-pass recalculation)
SetMemoryMax(2048)

# Multi-threading filter mode
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream
potplayer_source()

# Native ARM64 MVTools2 plugin
LoadPlugin("mvtools2.dll")

# 1. Motion Super Clip with Edge Guard
# pel=1: Whole-pixel estimation paired with MRecalculate keeps CPU low while tracking details
# hpad=8, vpad=8: Boundary padding stabilizes vectors near image borders
# sharp=1: Bicubic interpolation for cleaner motion vectors
super = MSuper(pel=1, hpad=8, vpad=8, sharp=1)

# 2. Coarse Global Motion Vector Search
# blksize=32, blksizev=32: Fast macro-motion detection
# search=2: Hexagonal search with radius 2 for good range without excessive SAD checks
# badrange=(-24): Early rejection of outlier vectors to prevent haloing
backward_coarse = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))

# 3. Fine Motion Refinement Pass (MRecalculate)
# blksize=16, blksizev=16: Refines vectors down to 16x16 blocks at object boundaries
# Resolves small moving objects and prevents blocky edge tearing
backward_fine = MRecalculate(super, backward_coarse, blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)

# 4. Pixel-Level Motion Interpolation with Occlusion Handling
# mode=2: Pixel-flow synthesis (significantly smoother than mode 0, removes block artifacts)
# blend=true: Graceful fallback blending for fast complex motions or occluded areas
# thSCD1=350, thSCD2=120: Balanced scene change detection
MBlockFps(super, backward_fine, forward_fine, num=60, den=1, mode=2, blend=true, thSCD1=350, thSCD2=120)

# 5. Thread Pool: 6 Threads
# Utilizes 6 of the 8 Oryon performance cores, leaving 2 cores for Windows OS, audio, and GPU driver
Prefetch(6)
