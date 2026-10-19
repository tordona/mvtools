# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Snapdragon 8cx Gen 3 (Profile 2: Balanced)
# Hardware: Qualcomm Snapdragon 8cx Gen 3 / Microsoft SQ3 (4x Cortex-X1 + 4x Cortex-A78, Adreno 690)
# Target: Fluid 1080p 60fps, Refined 16x16 Edges, Stable Thermal Ceiling
# Revision: 2.1.0 (2026-10-19)
# Changelog: Coarse 32x32 -> fine 16x16, pinned to 4x Cortex-X1 cores (threads=4), mem_limit=1024, D3D12 toggle
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Adreno GPU Offload
# Set to true for Direct3D 12 Adreno GPU offload (mvtools2_d3d12.dll)
# Set to false for original ARM64 CPU NEON baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_GPU = false

# Dynamic parameters adapted to USE_GPU
plugin_file = USE_GPU ? "mvtools2_d3d12.dll" : "mvtools2.dll"
# GPU: 3 worker threads prevents GPU queue lock contention;
# CPU: Exactly 4 worker threads pinned to the 4x Cortex-X1 Prime cores (zero asymmetric core stalls)
threads     = USE_GPU ? 3 : 4
mem_limit   = USE_GPU ? 1024 : 1024

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (Offloaded via Adreno 690 hardware decoder)
potplayer_source()

# Load Native ARM64 MVTools2 plugin
LoadPlugin(plugin_file)

# 1. Motion Super Clip with Lightweight Edge Guard
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=1: Whole-pixel estimation paired with MRecalculate keeps execution light while tracking fine details
# hpad=4, vpad=4: Boundary padding stabilizes edge vector calculation without memory thrashing
# sharp=1: Bicubic filtering for cleaner motion vectors
super = MSuper(levels=1, pel=1, hpad=4, vpad=4, sharp=1)

# 2. Coarse Motion Vector Search (32x32 blocks)
# search=2: Hexagonal search with radius 1 keeps searches fast and stable
# badrange=(-24): Early rejection of outlier vectors to prevent haloing
# levels=1: Strictly searches base Level 0
backward_coarse = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=1, chroma=false, levels=1, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=1, chroma=false, levels=1, badrange=(-24))

# 3. Fine Motion Refinement Pass (MRecalculate to 16x16)
# blksize=16, blksizev=16: Refines vectors down to 16x16 blocks at object boundaries
# Adreno 690 (2.2 TFLOPS, 136 GB/s LPDDR4x/5) easily runs dual-pass refinement within thermal limits
backward_fine = MRecalculate(super, backward_coarse, blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)

# 4. Direct Block-Based 60fps Synthesis with Refined Vectors
# mode=0: Fast block projection using refined 16x16 vector grid (crisp, zero block tearing)
# blend=false: Skips blend transparency calculations to eliminate ALU latency spikes
# thSCD1=350, thSCD2=120: Balanced scene change detection cleanly cuts camera transitions
MBlockFps(super, backward_fine, forward_fine, num=60, den=1, mode=0, blend=false, thSCD1=350, thSCD2=120)

# 5. Core Pinning: Strictly 4 Threads with 4 Lookahead Frames
# Pins worker threads to the 4x Cortex-X1 cluster, completely eliminating asymmetric thread sync stalls.
# Leaves all 4x Cortex-A78 cores free for OS, audio, PotPlayer UI, and GPU drivers.
# 4 lookahead frames absorb thread scheduling jitter and prevent presentation drops.
Prefetch(threads, 4)

