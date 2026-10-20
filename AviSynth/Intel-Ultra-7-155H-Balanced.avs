# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Intel Core Ultra 7 155H (Profile 2: Balanced)
# Hardware: Intel Core Ultra 7 155H (6P+8E+2LPE Cores, Intel Arc Xe-LPG 8 Xe-Cores @ 2.25 GHz)
# Architecture: Intel Meteor Lake (x64 AVX2 CPU / Direct3D 12 Arc iGPU)
# Target: Fluid 60fps presentation with optimal P-core affinity and D3D12 Arc iGPU offload
# Revision: 1.0.0 (2026-10-20)
# Changelog: Initial Meteor Lake profile, dual-pass 32x32 -> 16x16, P-core thread tuning, D3D12 toggle
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Intel Arc iGPU Offload
# Set to true for Direct3D 12 Intel Arc Xe-LPG GPU offload (mvtools2_d3d12.dll)
# Set to false for native x64 AVX2 CPU execution on Redwood Cove P-cores (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_GPU = false

# Dynamic parameters adapted to USE_GPU
plugin_file = USE_GPU ? "mvtools2_d3d12.dll" : "mvtools2.dll"
# GPU offload executes on command queue (4 worker threads optimal); CPU uses 6 Redwood Cove P-cores
threads     = USE_GPU ? 4 : 6
mem_limit   = USE_GPU ? 2048 : 3072

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (QuickSync DXVA2/D3D11 hardware decoded via Arc VPU)
potplayer_source()

# Load Native MVTools2 plugin (x64 AVX2 or Direct3D 12 GPU)
LoadPlugin(plugin_file)

# 1. Motion Super Clip with Boundary Padding
# pel=1: Whole-pixel estimation paired with MRecalculate keeps CPU low while tracking details
# hpad=8, vpad=8: Boundary padding stabilizes vectors near image borders
# sharp=1: Bicubic interpolation for cleaner motion vectors without Wiener filter latency
super = MSuper(pel=1, hpad=8, vpad=8, sharp=1)

# 2. Coarse Global Motion Vector Search
# blksize=32, blksizev=32: Fast macro-motion detection across 1080p and 4K frames
# search=2, searchparam=2: Hexagonal search with radius 2 for good range without excessive SAD checks
# chroma=false: Evaluates luminance only (matches D3D12 GPU compute shader and maximizes CPU cache residency)
# badrange=(-24): Early rejection of outlier vectors to prevent haloing and edge tearing
backward_coarse = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))

# 3. Fine Motion Refinement Pass (MRecalculate)
# blksize=16, blksizev=16: Refines vectors down to 16x16 blocks at object boundaries
# Resolves small moving objects and prevents blocky edge tearing
backward_fine = MRecalculate(super, backward_coarse, blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)

# 4. Pixel-Level Motion Interpolation with Hardware Dynamic Median Clamp
# mode=2: Pixel-flow synthesis (significantly smoother than mode 0, eliminates block grid artifacts)
# blend=true: Graceful fallback blending for fast complex motions or occluded areas
# thSCD1=350, thSCD2=120: Balanced scene change detection to instantly cut across camera scene transitions
MBlockFps(super, backward_fine, forward_fine, num=60, den=1, mode=2, blend=true, thSCD1=350, thSCD2=120)

# 5. Thread Pool with Lookahead Queue
# On CPU (6 threads): Locks to the 6 P-cores, avoiding scheduler migration jitter to E-cores
# On GPU (4 threads): Asynchronously feeds the D3D12 command queues without lock contention
# 4 lookahead frames absorb thread scheduling jitter
Prefetch(threads, 4)
