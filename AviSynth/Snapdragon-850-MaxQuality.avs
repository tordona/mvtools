# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Snapdragon 850 (Profile 3: Max Quality)
# Hardware: Qualcomm Snapdragon 850 (4x Kryo 385 Gold @ Cortex-A75, Adreno 630)
# Target: Highest Quality Motion Flow within 5W Snapdragon 850 Thermal Budget
# ==============================================================================

# Memory allocation (1 GB memory pool)
SetMemoryMax(1024)

# Multi-threading filter mode
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (Offloaded via Adreno 630 hardware decoder)
potplayer_source()

# Native ARM64 MVTools2 plugin
LoadPlugin("mvtools2.dll")

# 1. Base Motion Super Clip with Edge Protection
# pel=1: Whole-pixel base clip paired with MRecalculate keeps CPU low while tracking details
# hpad=4, vpad=4: Minimal boundary padding prevents edge tearing without cache thrashing
# sharp=1: Bicubic interpolation for cleaner motion vectors
super = MSuper(pel=1, hpad=4, vpad=4, sharp=1)

# 2. Dense Motion Vector Field Analysis (32x32 blocks, searchparam=2)
backward_coarse = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))

# 3. Fine Refinement Pass (Refines vectors down to 16x16 at object boundaries)
backward_fine = MRecalculate(super, backward_coarse, blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)

# 4. Pixel-Flow Motion Interpolation
# mode=2: Pixel-flow synthesis provides smooth motion vectors without blockiness
# blend=false: Skips blend transparency calculations to conserve ALU cycles
# thSCD1=350, thSCD2=120: Balanced scene change detection
MBlockFps(super, backward_fine, forward_fine, num=60, den=1, mode=2, blend=false, thSCD1=350, thSCD2=120)

# 5. Core Pinning: Strictly 4 Threads (Full Gold Core Saturation)
# Uses all 4 Kryo 385 Gold cores at peak utilization.
# IMPORTANT: Never set Prefetch > 4 on Snapdragon 850; spilling to Cortex-A55 cores causes severe stutter.
Prefetch(4)
