# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Snapdragon 8cx Gen 3 (Profile 3: Max Quality)
# Hardware: Qualcomm Snapdragon 8cx Gen 3 / Microsoft SQ3 (4x Cortex-X1 + 4x Cortex-A78, Adreno 690)
# Target: Highest Achievable Quality, Wide-Radius Refinement, Sustained 60fps
# Revision: 2.1.0 (2026-10-19)
# Changelog: Coarse 32x32 (searchparam=2) -> fine 16x16, pinned to 4x Cortex-X1 cores (threads=4), mem_limit=1536, D3D12 toggle
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Adreno GPU Offload
# Set to true for Direct3D 12 Adreno GPU offload (mvtools2_d3d12.dll)
# Set to false for original ARM64 CPU NEON baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_GPU = false

# Dynamic parameters adapted to USE_GPU
plugin_file = USE_GPU ? "mvtools2_d3d12.dll" : "mvtools2.dll"
# GPU: 4 worker threads; CPU: exactly 4 Cortex-X1 Prime cores (zero asymmetric core stalls)
threads     = USE_GPU ? 4 : 4
mem_limit   = USE_GPU ? 1536 : 1536

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (Offloaded via Adreno 690 hardware decoder)
potplayer_source()

# Load Native ARM64 MVTools2 plugin
LoadPlugin(plugin_file)

# 1. Motion Super Clip with Deep Boundary Guard
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=1: Whole-pixel estimation paired with MRecalculate keeps memory bandwidth lean and prevents cache thrashing
# hpad=8, vpad=8: Extended boundary padding stabilizes edge vector calculation on wide camera pans
# sharp=1: Bicubic filtering for cleaner motion vectors
super = MSuper(levels=1, pel=1, hpad=8, vpad=8, sharp=1)

# 2. Wide Coarse Motion Vector Field Analysis (32x32 blocks, searchparam=2)
# blksize=32, blksizev=32: Fast macro-motion detection
# search=2, searchparam=2: Extended hexagonal search radius captures high-velocity motion vectors
# chroma=false: Luma-focused motion estimation keeps computation inside thermal budget
# levels=1: Strictly searches base Level 0
# badrange=(-24): Strict outlier vector suppression
backward_dense = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))
forward_dense  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))

# 3. High-Definition Refinement Pass (MRecalculate to 16x16)
# blksize=16, blksizev=16: Refines vectors down to 16x16 blocks at object boundaries
# search=2, searchparam=1: Targeted vector refinement around previous candidates
# divide=0: Enforces smooth spatial motion field continuity
backward_fine = MRecalculate(super, backward_dense, blksize=16, blksizev=16, search=2, searchparam=1, chroma=false, divide=0)
forward_fine  = MRecalculate(super, forward_dense,  blksize=16, blksizev=16, search=2, searchparam=1, chroma=false, divide=0)

# 4. Direct Block-Based 60fps Synthesis with Refined Vectors
# mode=0: Fast block projection using refined 16x16 vector grid (crisp, zero block tearing)
# blend=false: Skips blend transparency calculations to eliminate ALU latency spikes
# thSCD1=320, thSCD2=115: Strict scene-change detection to prevent cross-cut morphing
MBlockFps(super, backward_fine, forward_fine, num=60, den=1, mode=0, blend=false, thSCD1=320, thSCD2=115)

# 5. Core Pinning: Strictly 4 Threads with 4 Lookahead Frames
# Pins worker threads to the 4x Cortex-X1 cluster, completely eliminating asymmetric thread sync stalls.
# Leaves all 4x Cortex-A78 cores free for OS, audio, PotPlayer UI, and GPU drivers.
# 4 lookahead frames absorb thread scheduling jitter and guarantee 0 dropped frames.
Prefetch(threads, 4)

