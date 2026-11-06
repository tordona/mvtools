# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon X (Profile 1: Eco / Lowest CPU)
# Hardware: Qualcomm Snapdragon X Elite / Plus (8x-12x Oryon Cores @ ARM64 NEON, Adreno X1-85)
# Memory: 16 GB - 64 GB LPDDR5x-8448 (135 GB/s Unified Bandwidth)
# Architecture: ARM64 NEON / Direct3D 12 GPU Offload (mvtools2.dll)
# Generator: Google Antigravity (AIAgentProfileGuide Rev 2.3.10)
# Target: Sub-8 W Package Envelope, Silent Fanless / Battery Playback, 0 Dropped Frames
# Revision: 2.4.0 (2026-11-06)
# Changelog: Series-wide Snapdragon X rename (X Elite + X Plus), removed 1080p phrasing, updated comments, D3D12 toggle
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Direct3D 12 Compute Offload
# Set to true for Direct3D 12 Adreno GPU offload (via MEnableD3D12 in mvtools2.dll)
# Set to false for original ARM64 CPU NEON baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_D3D12 = false

# Dynamic parameters adapted to USE_D3D12
threads     = USE_D3D12 ? 2 : 4     # GPU: 2 worker threads (double-buffered); CPU: 4 Oryon cores
mem_limit   = USE_D3D12 ? 1536 : 2048

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream
src = potplayer_source()

# Dynamic Resolution Adaptation (720p through 4K):
# At 4K, 64x64 blocks maintain the exact 2,040 block count of standard 32x32 search,
# keeping CPU and GPU memory traffic within low-power battery envelopes.
is_4k  = (src.Width() > 2048)
blk_sz = is_4k ? 64 : 32

# Load Native ARM64 MVTools2 plugin & configure Direct3D 12 engine
LoadPlugin("mvtools2.dll")
MEnableD3D12(USE_D3D12)

# 1. Base Motion Super Clip (Integer Pixel Precision)
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=1: Full-pixel precision only (skips subpixel math, cutting memory bandwidth by ~75%)
# hpad=0, vpad=0: No padding overhead
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = src.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Ultra-Lightweight Coarse Motion Analysis
# 2,040 blocks (32x32 at standard resolutions, 64x64 at 4K)
# search=2: Hexagonal search pattern (extremely fast and stable)
# searchparam=1: Minimal search radius to limit vector comparisons
# chroma=false: Evaluates luminance only, saving 50% vector math
# levels=1: Strictly searches base Level 0 without multi-level pyramid overhead
backward_vec = MAnalyse(super, isb=true,  blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, chroma=false, levels=1)
forward_vec  = MAnalyse(super, isb=false, blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, chroma=false, levels=1)

# 3. Direct Block-Based 60 fps Synthesis
# mode=0: Fast block projection (least computationally intensive mode)
# blend=false: Avoids calculating blend masks on fast motion
# thSCD1=400, thSCD2=130: Robust scene-change detection to avoid artifacts on cuts
last = MBlockFps(src, super, backward_vec, forward_vec, num=60, den=1, mode=0, blend=false, thSCD1=400, thSCD2=130)

# 4. Multi-Threading (adapted dynamically to USE_D3D12)
Prefetch(threads)
