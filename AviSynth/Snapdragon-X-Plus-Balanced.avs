# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon X Plus (Profile 2: Balanced)
# Hardware: Qualcomm Snapdragon X Plus (8x Oryon Cores @ ARM64 NEON)
# Target: Balanced tradeoff between motion fluidity, edge definition, and power consumption
# Revision: 2.0.0 (2026-10-18)
# Changelog: Oryon architecture, levels=1, coarse 32x32 -> fine 16x16, threads=6, Prefetch(6, 4), mem_limit=1536, D3D12 toggle
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Adreno GPU Offload
# Set to true for Direct3D 12 Adreno GPU offload (mvtools2_d3d12.dll)
# Set to false for original ARM64 CPU NEON baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_GPU = false

# Dynamic parameters adapted to USE_GPU
plugin_file = USE_GPU ? "mvtools2_d3d12.dll" : "mvtools2.dll"
threads     = USE_GPU ? 4 : 6     # GPU offload executes on command queue (4 threads optimal); CPU uses 6 Oryon cores
mem_limit   = USE_GPU ? 1536 : 2048

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream
potplayer_source()

# Load Native ARM64 MVTools2 plugin
LoadPlugin(plugin_file)

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

# 5. Thread Pool (adapted dynamically to USE_GPU)
Prefetch(threads)

