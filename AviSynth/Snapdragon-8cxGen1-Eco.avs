# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 8cx Gen 1 (Profile 1: Eco)
# Hardware: Qualcomm Snapdragon 8cx Gen 1 (4x Kryo 495 Gold + 4x Silver, Adreno 680)
# Target: 7 W Fanless Thermal Envelope, Maximum Battery Life, 0 Dropped Frames
# Revision: 2.0.0 (2026-10-18)
# Changelog: Native 1080p, levels=1, single MSuper, threads=3, Prefetch(3, 4), mem_limit=768/512, D3D12 toggle
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Direct3D 12 Compute Offload
# Set to true for Direct3D 12 Adreno GPU offload (via MEnableD3D12 in mvtools2.dll)
# Set to false for original ARM64 CPU NEON baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_D3D12 = false

# Dynamic parameters adapted to USE_D3D12
threads     = USE_D3D12 ? 2 : 3     # GPU: 2 worker threads; CPU: 3 Gold cores
mem_limit   = USE_D3D12 ? 512 : 768

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (Offloaded via Adreno 680 hardware decoder)
potplayer_source()

# Load Native ARM64 MVTools2 plugin
LoadPlugin("mvtools2.dll")
MEnableD3D12(USE_D3D12)

# 1. Base Motion Super Clip (Integer Pixel Precision)
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=1: Full-pixel precision only (avoids heavy subpixel math on Cortex-A76 cores)
# hpad=0, vpad=0: No padding overhead to minimize cache pressure
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Ultra-Lightweight Coarse Motion Analysis
# blksize=32, blksizev=32: Large 32x32 blocks reduce vector evaluation complexity by 75%
# search=2: Hexagonal search pattern (extremely fast and stable)
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

# 4. Multi-Threading (adapted dynamically to USE_D3D12)
Prefetch(threads)

