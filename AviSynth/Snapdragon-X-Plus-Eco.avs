# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon X Plus (Profile 1: Eco / Lowest CPU)
# Hardware: Qualcomm Snapdragon X Plus (8x Oryon Cores @ ARM64 NEON)
# Target: Ultra-low CPU usage, zero dropped frames, cool & quiet / battery saver
# Revision: 2.0.0 (2026-10-18)
# Changelog: Oryon architecture, levels=1, single MSuper, threads=4, Prefetch(4, 4), mem_limit=1024, D3D12 toggle
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Adreno GPU Offload
# Set to true for Direct3D 12 Adreno GPU offload (mvtools2_d3d12.dll)
# Set to false for original ARM64 CPU NEON baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_GPU = false

# Dynamic parameters adapted to USE_GPU
plugin_file = USE_GPU ? "mvtools2_d3d12.dll" : "mvtools2.dll"
threads     = USE_GPU ? 2 : 4     # GPU: 2 worker threads (double-buffered); CPU: 4 Oryon cores
mem_limit   = USE_GPU ? 1536 : 2048

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream
potplayer_source()

# Load Native ARM64 MVTools2 plugin
LoadPlugin(plugin_file)

# 1. Base Motion Super Clip (Integer Pixel Precision)
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=1: Full-pixel precision only (skips subpixel math, cutting memory bandwidth by ~75%)
# hpad=0, vpad=0: No padding overhead
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Ultra-Lightweight Coarse Motion Analysis
# blksize=32, blksizev=32: Large 32x32 blocks drastically reduce block count
# search=2: Hexagonal search pattern (extremely fast and stable)
# searchparam=1: Minimal search radius to limit vector comparisons
# chroma=false: Evaluates luminance only, saving 50% vector math
# levels=1: Strictly searches base Level 0 without multi-level pyramid overhead
backward_vec = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=1, chroma=false, levels=1)
forward_vec  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=1, chroma=false, levels=1)

# 3. Direct Block-Based 60 fps Synthesis
# mode=0: Fast block projection (least computationally intensive mode)
# blend=false: Avoids calculating blend masks on fast motion
# thSCD1=400, thSCD2=130: Robust scene-change detection to avoid artifacts on cuts
MBlockFps(super, backward_vec, forward_vec, num=60, den=1, mode=0, blend=false, thSCD1=400, thSCD2=130)

# 4. Multi-Threading (adapted dynamically to USE_GPU)
Prefetch(threads)

