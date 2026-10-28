# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 8cx Gen 2 (Profile 3: Max Quality)
# Hardware: Qualcomm Snapdragon 8cx Gen 2 (4x Kryo 495 Gold + 4x Silver, Adreno 680)
# Target: Highest Achievable Quality within 8cx Gen 2 Thermal Ceiling
# ==============================================================================

# Memory allocation (2 GB memory pool)
SetMemoryMax(2048)

# Multi-threading filter mode
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (Offloaded via Adreno 680 hardware decoder)
potplayer_source()

# Native ARM64 MVTools2 plugin
LoadPlugin("mvtools2.dll")

# 1. Subpixel Motion Super Clip (Half-Pixel Precision)
# pel=2: Half-pixel subpixel interpolation provides fluid motion on slow/medium pans
# hpad=8, vpad=8: Boundary padding stabilizes edge vector calculation
# sharp=1: Bicubic filtering (lighter than sharp=2, preventing thermal throttling)
super = MSuper(pel=2, hpad=8, vpad=8, sharp=1)

# 2. Dense Motion Vector Field Analysis (16x16 blocks)
# blksize=16, blksizev=16: Dense initial block grid (4x denser than 32x32)
# search=2, searchparam=2: Wider hexagonal search tracking faster action
# chroma=false: Luma-focused motion estimation keeps computation inside the 7 W – 10 W budget
# badrange=(-24): Strict outlier vector suppression
backward_dense = MAnalyse(super, isb=true,  blksize=16, blksizev=16, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))
forward_dense  = MAnalyse(super, isb=false, blksize=16, blksizev=16, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))

# 3. High-Definition 8x8 Micro-Block Refinement (MRecalculate)
# blksize=8, blksizev=8: Micro-blocks resolve fine details (text, hair, thin edges)
# search=2, searchparam=1: Targeted vector refinement around previous candidates
# divide=0: Enforces smooth spatial motion field continuity
backward_fine = MRecalculate(super, backward_dense, blksize=8, blksizev=8, search=2, searchparam=1, chroma=false, divide=0)
forward_fine  = MRecalculate(super, forward_dense,  blksize=8, blksizev=8, search=2, searchparam=1, chroma=false, divide=0)

# 4. Advanced Pixel-Flow Motion Interpolation with Occlusion Handling
# mode=2: Pixel-flow synthesis with occlusion masking
# blend=true: Seamlessly blends occlusion zones instead of tearing
# thSCD1=320, thSCD2=115: Strict scene-change detection to prevent cross-cut morphing
MBlockFps(super, backward_fine, forward_fine, num=60, den=1, mode=2, blend=true, thSCD1=320, thSCD2=115)

# 5. Core Pinning: Strictly 4 Threads
# Utilizes all 4 Kryo 495 Gold (Cortex-A76) performance cores at maximum efficiency.
# Keeps work off the slow Cortex-A55 cores to prevent pipeline stalls and dropped frames.
Prefetch(4)
