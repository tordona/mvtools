# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Snapdragon 8cx Gen 2 (Profile 2: Balanced)
# Hardware: Qualcomm Snapdragon 8cx Gen 2 (4x Kryo 495 Gold + 4x Silver, Adreno 680)
# Target: Fluid 1080p 60fps, Sharp Edge Tracking, Stable Thermal Ceiling
# ==============================================================================

# Memory allocation (1.5 GB memory pool)
SetMemoryMax(1536)

# Multi-threading filter mode
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (Offloaded via Adreno 680 hardware decoder)
potplayer_source()

# Native ARM64 MVTools2 plugin
LoadPlugin("mvtools2.dll")

# 1. Motion Super Clip with Lightweight Edge Guard
# pel=1: Whole-pixel estimation paired with MRecalculate keeps CPU low while tracking details
# hpad=4, vpad=4: Minimal boundary padding prevents edge tearing without cache thrashing
# sharp=1: Bicubic interpolation for cleaner motion vectors
super = MSuper(pel=1, hpad=4, vpad=4, sharp=1)

# 2. Coarse Motion Vector Search (32x32 blocks)
# search=2: Hexagonal search with radius 1 keeps searches fast on Cortex-A76 cores
# badrange=(-24): Early rejection of outlier vectors to prevent haloing
backward_coarse = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=1, chroma=false, plevel=0, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=1, chroma=false, plevel=0, badrange=(-24))

# 3. Fine Motion Refinement Pass (MRecalculate to 16x16)
# blksize=16, blksizev=16: Refines vectors down to 16x16 blocks at object boundaries
# Resolves small moving objects and eliminates blocky edge artifacts
backward_fine = MRecalculate(super, backward_coarse, blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)

# 4. Pixel-Flow Motion Interpolation
# mode=2: Pixel-flow synthesis provides smooth motion vectors without blockiness
# blend=false: Skips blend transparency calculations to conserve ALU cycles
# thSCD1=350, thSCD2=120: Balanced scene change detection
MBlockFps(super, backward_fine, forward_fine, num=60, den=1, mode=2, blend=false, thSCD1=350, thSCD2=120)

# 5. Core Pinning: Exactly 4 Threads
# Matches the 4 Kryo 495 Gold (Cortex-A76) performance cores 1:1.
# CRITICAL: Setting Prefetch > 4 spills threads onto the weak in-order Cortex-A55 cores,
# which causes thread stalling, frame queue desync, and video stuttering.
Prefetch(4)
