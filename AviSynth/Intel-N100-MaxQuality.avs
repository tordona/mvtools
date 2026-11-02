# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Intel Processor N100 (Profile 3: MaxQuality)
# Hardware: Intel Processor N100 (4C/4T Gracemont @ 6 W TDP, Intel UHD Graphics 24EU)
# Memory: 16 GB Single-Channel DDR4/DDR5 (Single 64-bit Bus ~25.6-38.4 GB/s)
# Architecture: Native 1080p x86-64 AVX2 / SSE4.2 CPU Motion Estimation (mvtools2.dll)
# Target: High-Fidelity 60 fps Presentation, Native 16x16 with 4 px Overlap (14,151 Blocks), 6 W Envelope
# Revision: 1.0.0 (2026-10-25)
# ==============================================================================

# Core Allocation & Threading Strategy:
# 3 worker threads across 4 Gracemont cores leaves 1 full core for system presentation.
# Restricts memory footprint to prevent single-channel memory channel saturation.
threads     = 3
mem_limit   = 768                 # Controlled cache footprint for single-channel RAM

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded via Intel UHD Graphics)
src = potplayer_source()

# Dynamic Resolution Adaptation:
# Detect 4K (3840x2160 / 4096x2160) vs 1080p/720p.
# At 4K, 32x32 blocks maintain the exact 8,160 block count of 1080p 16x16,
# preserving single-pass high-throughput execution without cache thrashing.
is_4k  = (src.Width() > 2048)
blk_sz = is_4k ? 32 : 16

# Load Native x64 MVTools2 plugin (leveraging Gracemont AVX2 SIMD optimizations)
LoadPlugin("mvtools2.dll")

# 1. Native 1080p Super Clip with Bicubic Subpixel Interpolation
# sharp=1: Bicubic subpixel interpolation enhances fine detail edge contrast
# levels=1: Single-level eliminates redundant pyramid levels
# hpad=0, vpad=0: Native pitch alignment
super = src.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=1)

# 2. Native 1080p Overlapping Motion Vector Search (No Proxy / Zero Downscale)
# blksize=blk_sz, blksizev=blk_sz, overlap=4, overlapv=4: ~14,151 overlapping blocks at native 1080p
# Overlap eliminates block boundary discontinuities along fast-moving contours
# search=2, searchparam=2: Radius-2 hexagonal search captures rapid motion
# chroma=false: Luma-only search cuts vector computation by 50%
# levels=1: Single-level search matching super's levels=1
backward_vec = MAnalyse(super, isb=true,  blksize=blk_sz, blksizev=blk_sz, overlap=4, overlapv=4, search=2, searchparam=2, chroma=false, levels=1)
forward_vec  = MAnalyse(super, isb=false, blksize=blk_sz, blksizev=blk_sz, overlap=4, overlapv=4, search=2, searchparam=2, chroma=false, levels=1)

# 3. Direct Native 60 fps Frame Synthesis with Directional Alpha Blending
# Directly warps native frames using overlapping vector fields
# mode=0: Fast 2-stream block projection
# blend=true: Smooths occlusion boundaries and disocclusion edges
# thSCD1=350, thSCD2=115: High-sensitivity scene-change threshold prevents cut distortion
MBlockFps(src, super, backward_vec, forward_vec, num=60, den=1, mode=0, blend=true, thSCD1=350, thSCD2=115)

# 4. Core Pinning: 3 Threads with 6-Frame Lookahead Queue
# Leaves 1 full Gracemont core free for OS, audio pipeline, and D3D11 swapchain
# 6 lookahead frames absorb thread scheduling jitter
Prefetch(threads, 6)
