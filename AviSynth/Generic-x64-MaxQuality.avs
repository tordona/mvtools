# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Generic x86-64 (Profile 3: Max Quality)
# Hardware: Generic 64-bit x86 (Intel Core i5/i7/i9 / AMD Ryzen / Modern 25 W+ Quad+ Cores)
# Architecture: Native 1080p x86-64 AVX2 / AVX-512 CPU Motion Estimation (mvtools2.dll)
# Target: High-Fidelity 16x16 Vectors (8,160 Blocks), Subpixel Edge Contrast, 0 Drops
# Revision: 3.0.0 (2026-10-25)
# Changelog: Replaced compute-stalling pel=2 / MRecalculate with native 1080p 16x16 blocks
#            (8,160 blocks) and sharp=1 bicubic subpixel interpolation. Single-level levels=1.
# ==============================================================================

# Core Allocation & Threading Strategy:
# 4 worker threads utilizes compute capacity on modern quad/multi-core x86 processors.
# Native 16x16 block grid resolves fine detail contours, moving text, and complex panning.
threads     = 4
mem_limit   = 768                 # Controlled working set footprint for 8 GB+ system RAM

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded)
src = potplayer_source()

# Dynamic Resolution Adaptation:
# Detect 4K vs 1080p. At 4K, 32x32 blocks maintain exact 8,160 block density.
is_4k  = (src.Width() > 2048)
blk_sz = is_4k ? 32 : 16

# Load Native x64 MVTools2 plugin (leveraging AVX2 / AVX-512 SIMD intrinsics)
LoadPlugin("mvtools2.dll")

# 1. Native 1080p Super Clip with Bicubic Subpixel Interpolation
# sharp=1: Bicubic subpixel interpolation enhances fine detail edge contrast
# levels=1: Single-level eliminates redundant pyramid levels
# hpad=0, vpad=0: Native pitch alignment
super = src.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=1)

# 2. Native 1080p Fine Motion Vector Search (No Proxy / Zero Downscale)
# blksize=blk_sz, blksizev=blk_sz: 16x16 blocks at native 1080p (~8,160 blocks total)
# 4x vector density compared to 32x32 without proxy scaling quantization
# search=2, searchparam=1: Radius-1 hexagonal search stays cache-resident in L2/L3
# chroma=false: Luma-only search cuts vector computation by 50%
# levels=1: Single-level search matching super's levels=1
backward_vec = MAnalyse(super, isb=true,  blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, chroma=false, levels=1)
forward_vec  = MAnalyse(super, isb=false, blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, chroma=false, levels=1)

# 3. Direct Native 60 fps Frame Synthesis
# Directly warps native frames using fine-grained 16x16 vector fields
# mode=0: Fast 2-stream block projection (avoids mode=2 pixel-flow compute collapse)
# blend=false: Crisp block projection avoiding blur on fast motion
# thSCD1=350, thSCD2=115: High-sensitivity scene-change threshold prevents cut distortion
MBlockFps(src, super, backward_vec, forward_vec, num=60, den=1, mode=0, blend=false, thSCD1=350, thSCD2=115)

# 4. Core Pinning: 4 Threads with 6-Frame Lookahead Queue
# 4 threads delivers smooth 60 fps real-time throughput on modern 25 W+ quad-core CPUs
# 6 lookahead frames absorb thread scheduling jitter
Prefetch(threads, 6)
