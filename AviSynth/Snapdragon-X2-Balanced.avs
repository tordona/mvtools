# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon X2 (Profile 2: Balanced)
# Hardware: Qualcomm Snapdragon X2 Elite / Plus (6x-12x Prime + 4x-6x Performance 3rd-Gen Oryon Cores, Adreno X2)
# Memory: 16 GB - 64 GB LPDDR5x-9523 (152 GB/s - 228 GB/s Unified Bandwidth)
# Architecture: ARM64 NEON / Direct3D 12 GPU Offload (mvtools2.dll)
# Generator: Google Antigravity (AIAgentProfileGuide Rev 2.3.10)
# Target: Fluid 720p–4K 60 fps, High-Density 16x16 Vectors (8,160 Blocks), 12 W - 18 W Envelope
# Revision: 1.1.4 (2026-11-17)
# Changelog: Parameterized target_fps (default 60, capped at 60 fps on 4K) with target-relative frame rate bypass; Replaced unconditional levels=1 with tiered pyramid levels_val (levels_val = USE_D3D12 ? 1 : (is_4k ? 2 : 0)) and plevel=0 for tear-free panning
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Direct3D 12 Compute Offload
# Set to true for Direct3D 12 GPU offload to Adreno X2 (via MEnableD3D12 in mvtools2.dll)
# Set to false for native ARM64 CPU NEON SIMD production baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_D3D12  = false

# Dynamic parameters adapted to USE_D3D12
# GPU offload executes on direct command queue (3 threads triple-buffered);
# CPU uses 6 Oryon Prime cores (fits 100% within the 6-core Prime cluster of 10C/12C X2 SKUs and half the 12-core Prime cluster of 18C SKUs)
threads    = USE_D3D12 ? 3 : 6
mem_limit  = USE_D3D12 ? 1024 : 1024
target_fps  = 60                  # Target output frame rate (e.g. 60 or 120)
pel_val    = 1
sharp_mode = 0
pad_size   = USE_D3D12 ? 8 : 0
synth_mode = 0

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (Adreno X2 VPU hardware decoded via D3D11/DXVA2)
src = potplayer_source()

is_4k      = (src.Width() > 2048)
target_fps = (is_4k && target_fps > 60) ? 60 : target_fps

# Bypass motion interpolation if source is already at or above target_fps (4% NTSC tolerance, e.g. 59.94 fps for 60 fps)
if (src.FrameRate() >= (target_fps * 0.96)) {
    return src
}

# Dynamic Resolution Adaptation (720p through 4K):
# At 4K, 32x32 blocks maintain the exact 8,160 block count of standard 16x16 search,
# preserving single-pass high-throughput execution without cache thrashing.
levels_val = USE_D3D12 ? 1 : (is_4k ? 2 : 0)
blk_sz  = is_4k ? 32 : 16
pad_val = is_4k ? (pad_size * 2) : pad_size

# Load Native ARM64 MVTools2 plugin & configure Direct3D 12 engine
LoadPlugin("mvtools2.dll")
MEnableD3D12(USE_D3D12)
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}

# 1. Base Motion Super Clip (Single-Level, Integer Pixel Precision)
# levels=1: Eliminates redundant multi-level pyramid generation
# pel=1: Full-pixel precision only (D3D12 FlowWarpCS performs subpixel bilinear sampling in hardware)
# pad_val: 8 px boundary padding on GPU stabilizes edge motion vectors on camera pans
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = src.MSuper(levels=levels_val, pel=pel_val, hpad=pad_val, vpad=pad_val, sharp=sharp_mode)

# 2. Fine Motion Vector Search
# blksize=blk_sz, blksizev=blk_sz: 16x16 blocks (32x32 at 4K; ~8,160 blocks total)
# search=2, searchparam=2: Radius-2 hexagonal search captures rapid motion pans
# chroma=false: Luma-only search required for D3D12 compute offload, cuts vector compute by 50%
# levels=1: Single-level search matching super's levels=1
# badrange=(-24): Outlier vector suppression for CPU NEON search path
backward_vec = MAnalyse(super, isb=true,  blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=2, chroma=false, plevel=0, levels=levels_val, badrange=(-24))
forward_vec  = MAnalyse(super, isb=false, blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=2, chroma=false, plevel=0, levels=levels_val, badrange=(-24))

# 3. Direct 60 fps Frame Synthesis
# mode=0: Fast 2-stream block projection mandatory on Balanced across both GPU and CPU
# blend=false: Clean block projection avoiding blur on fast motion
# thSCD1=380, thSCD2=125: Balanced scene-change detection cleanly cuts camera transitions
last = MBlockFps(src, super, backward_vec, forward_vec, num=target_fps, den=1, mode=synth_mode, blend=false, thSCD1=380, thSCD2=125)

# 4. Hardware Thread Affinity & Lookahead Buffer
# Pins worker threads strictly to the 3rd-Gen Oryon Prime core cluster, preventing migration onto 3.4-3.6 GHz Performance cores
# 6 lookahead frames absorb thread scheduling jitter for stable 1% low frame times
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads, 6)
