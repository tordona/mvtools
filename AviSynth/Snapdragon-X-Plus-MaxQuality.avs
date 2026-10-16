# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Snapdragon X Plus (Profile 3: Max Quality)
# Hardware: Qualcomm Snapdragon X Plus (8x Oryon Cores @ ARM64 NEON)
# Target: Highest visual fidelity, subpixel precision, chroma tracking, 8x8 refinement
# ==============================================================================

# Memory allocation (4 GB for deep hierarchical pyramids and subpixel buffers)
SetMemoryMax(4096)

# Multi-threading filter mode
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream
potplayer_source()

# Native ARM64 MVTools2 plugin
LoadPlugin(ScriptDir() + "mvtools2.dll")

# 1. High-Precision Subpixel Motion Super Clip
# pel=2: Half-pixel subpixel interpolation for ultra-fine subpixel motion accuracy
# hpad=16, vpad=16: Full edge padding to prevent border artifact distortion
# sharp=2: Wiener filter interpolation for sharpest subpixel planes
super = MSuper(pel=2, hpad=16, vpad=16, sharp=2)

# 2. Dense Motion Vector Field Analysis
# blksize=16, blksizev=16: Dense initial block grid (4x denser than 32x32)
# search=3: Unequal Multi-Hexagon Search (UMH / Exhaustive-like pattern for fast motion tracking)
# searchparam=3: Broad search radius covering fast pans and multi-directional action
# chroma=true: Motion vectors account for color differences (avoids errors on low-luma-contrast colored objects)
# plevel=1: Hierarchical coarse-to-fine search starting from level 1
# badrange=(-24): Strict outlier suppression
backward_dense = MAnalyse(super, isb=true,  blksize=16, blksizev=16, search=3, searchparam=3, chroma=true, plevel=1, badrange=(-24))
forward_dense  = MAnalyse(super, isb=false, blksize=16, blksizev=16, search=3, searchparam=3, chroma=true, plevel=1, badrange=(-24))

# 3. High-Definition 8x8 Micro-Block Refinement (MRecalculate)
# blksize=8, blksizev=8: Micro-blocks resolve fine details (hair, particles, complex texture edges)
# search=3, searchparam=1: Precision vector refinement around previous candidates
# chroma=true: Chroma-aware refinement
# divide=0: Smooth continuous motion field
backward_fine = MRecalculate(super, backward_dense, blksize=8, blksizev=8, search=3, searchparam=1, chroma=true, divide=0)
forward_fine  = MRecalculate(super, forward_dense,  blksize=8, blksizev=8, search=3, searchparam=1, chroma=true, divide=0)

# 4. Advanced Pixel-Flow Motion Interpolation
# mode=2: Advanced pixel-flow motion synthesis with occlusion masking
# blend=true: Seamless occlusion blending without edge tearing
# thSCD1=300, thSCD2=110: Strict scene-change detection to immediately isolate camera cuts
MBlockFps(super, backward_fine, forward_fine, num=60, den=1, mode=2, blend=true, thSCD1=300, thSCD2=110)

# 5. Full Core Utilization (8 Threads)
# Fully leverages all 8 Oryon performance cores for peak interpolation throughput
Prefetch(8)
