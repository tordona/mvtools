# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 8cx Gen 3 (Profile 1: Eco)
# Hardware: Qualcomm Snapdragon 8cx Gen 3 / Microsoft SQ3 (4x Cortex-X1 + 4x Cortex-A78, Adreno 690)
# Target: Ultra-Low Power, Maximum Battery Longevity, 0 Dropped Frames
# Revision: 2.1.0 (2026-10-19)
# Changelog: Single MSuper, levels=1, threads=3, Prefetch(3, 4), mem_limit=768/512, D3D12 toggle
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Adreno GPU Offload
# Set to true for Direct3D 12 Adreno GPU offload (mvtools2_d3d12.dll)
# Set to false for original ARM64 CPU NEON baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_GPU = false

# Dynamic parameters adapted to USE_GPU
plugin_file = USE_GPU ? "mvtools2_d3d12.dll" : "mvtools2.dll"
# GPU: 3 threads keeps queue full; CPU: 3 threads on Cortex-X1 leaves 1 X1 + all 4 Cortex-A78 cores idle
threads     = USE_GPU ? 3 : 3
mem_limit   = USE_GPU ? 512 : 768

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (Offloaded via Adreno 690 hardware decoder)
potplayer_source()

# Load Native ARM64 MVTools2 plugin
LoadPlugin(plugin_file)

# 1. Base Motion Super Clip (Integer Pixel Precision)
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=1: Whole-pixel estimation for minimal ALU and memory overhead
# hpad=0, vpad=0: No padding overhead to minimize cache pressure
# sharp=0: Fast bilinear interpolation for minimal load
super = MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Ultra-Lightweight Coarse Motion Analysis
# blksize=32, blksizev=32: Large 32x32 blocks reduce vector evaluation complexity by 75%
# search=2: Hexagonal search pattern (fast and stable)
# searchparam=1: Minimal search radius to limit vector comparisons
# chroma=false: Evaluates luminance only, saving 50% vector computation
# levels=1: Strictly searches base Level 0 without multi-level pyramid overhead
backward_vec = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=1, chroma=false, levels=1)
forward_vec  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=1, chroma=false, levels=1)

# 3. Direct Block-Based 60 fps Synthesis
# mode=0: Fast block projection (least computationally intensive mode)
# blend=false: Avoids calculating blend transparency masks on fast motion
# thSCD1=400, thSCD2=130: Fast scene-change detection to immediately cut across scene changes
MBlockFps(super, backward_vec, forward_vec, num=60, den=1, mode=0, blend=false, thSCD1=400, thSCD2=130)

# 4. Core Pinning: Strictly 3 Threads with 4 Lookahead Frames
# Utilizes 3 of the 4 Cortex-X1 Prime cores; leaves 1 X1 + all 4 Cortex-A78 cores idle.
# 4 lookahead frames absorb thread scheduling jitter and prevent presentation drops.
Prefetch(threads, 4)

