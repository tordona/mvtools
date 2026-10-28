# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 8cx Gen 2 (Profile 2: Balanced)
# Hardware: Qualcomm Snapdragon 8cx Gen 2 / Microsoft SQ2 (4x Kryo 495 Gold + 4x Silver, Adreno 680)
# Target: Fluid 1080p 60 fps, Sharp Edge Tracking, Stable Thermal Ceiling
# Revision: 2.0.0 (2026-10-18)
# Changelog: Native 1080p, levels=1, coarse 32x32 -> fine 16x16, threads=4, Prefetch(4, 4), mem_limit=1024, D3D12 toggle
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Adreno GPU Offload
# Set to true for Direct3D 12 Adreno GPU offload (mvtools2_d3d12.dll)
# Set to false for original ARM64 CPU NEON baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_GPU = false

# Dynamic parameters adapted to USE_GPU
plugin_file = USE_GPU ? "mvtools2_d3d12.dll" : "mvtools2.dll"
threads     = USE_GPU ? 3 : 4     # GPU: 3 threads leaves Gold cores free; CPU: exactly 4 Gold cores
mem_limit   = USE_GPU ? 1024 : 1536

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (Offloaded via Adreno 680 hardware decoder)
potplayer_source()

# Load Native ARM64 MVTools2 plugin
LoadPlugin(plugin_file)

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

# 5. Core Pinning (adapted dynamically to USE_GPU)
Prefetch(threads)

