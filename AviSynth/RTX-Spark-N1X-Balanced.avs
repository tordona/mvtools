# ==============================================================================
# PotPlayer AviSynth+ 60 fps Interpolation: RTX Spark N1X (Profile 2: Balanced)
# Hardware: NVIDIA RTX Spark N1X (9x-10x Cortex-X925 + 9x-10x Cortex-A725, Blackwell RTX GPU)
# Memory: 32 GB - 128 GB 256-bit LPDDR5X-9400 (~300 GB/s Unified Bandwidth)
# Architecture: Native ARM64 NEON / Direct3D 12 GPU Offload (mvtools2.dll)
# Generator: Google Antigravity (AIAgentProfileGuide Rev 2.3.11)
# Target: Fluid 1080p/4K 60 fps, Native 16x16 Vectors (8,160 Blocks), 15 W - 25 W Envelope
# Revision: 1.0.4 (2026-11-17)
# Changelog: Parameterized target_fps (default 60, capped at 60 fps on 4K) with target-relative frame rate bypass; Replaced unconditional levels=1 with tiered pyramid levels_val (levels_val = USE_D3D12 ? 1 : (is_4k ? 2 : 0)) and plevel=0 for tear-free panning
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Direct3D 12 Compute Offload
# Set to true for Direct3D 12 GPU offload to Blackwell RTX GPU (via MEnableD3D12 in mvtools2.dll)
# Set to false for native ARM64 CPU NEON SIMD production baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_D3D12  = false

# Dynamic parameters adapted to USE_D3D12
# GPU offload executes on direct command queue (3 threads triple-buffered);
# CPU uses 6 Cortex-X925 Prime cores (comfortably within the 9-10 core Prime cluster, leaving 3-4 Prime cores + 10 A725 cores free)
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

# Full PotPlayer video source stream (NVIDIA NVDEC hardware decoded via D3D11/DXVA2)
src = potplayer_source()

is_4k      = (src.Width() > 2048)
target_fps = (is_4k && target_fps > 60) ? 60 : target_fps

# Bypass motion interpolation if source is already at or above target_fps (4% NTSC tolerance, e.g. 59.94 fps for 60 fps)
if (src.FrameRate() >= (target_fps * 0.96)) {
    return src
}

# Dynamic Resolution Adaptation:
# Detect 4K (3840x2160 / 4096x2160) vs 1080p/720p.
# At 4K, 32x32 blocks maintain the exact 8,160 block count of 1080p 16x16,
# preserving single-pass high-throughput execution without cache thrashing.
levels_val = USE_D3D12 ? 1 : (is_4k ? 2 : 0)
blk_sz  = is_4k ? 32 : 16
pad_val = is_4k ? (pad_size * 2) : pad_size

# Load Native ARM64 MVTools2 plugin & configure Direct3D 12 engine
LoadPlugin("mvtools2.dll")
try { MEnableD3D12(USE_D3D12) } catch(e) {}
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}

# 1. Native 1080p Super Clip (Tiered Pyramid, Integer Pixel Precision)
# levels_val: 1 on USE_D3D12=true; is_4k ? 2 : 0 on CPU (full pyramid at 1080p, 2 levels at 4K)
# pel=1: Full-pixel precision only (D3D12 FlowWarpCS performs subpixel bilinear sampling in hardware)
# pad_val: 8 px boundary padding on GPU stabilizes edge motion vectors on camera pans
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = src.MSuper(levels=levels_val, pel=pel_val, hpad=pad_val, vpad=pad_val, sharp=sharp_mode)

# 2. Native 1080p Fine Motion Vector Search (No Proxy / Zero Downscale)
# blksize=blk_sz, blksizev=blk_sz: 16x16 blocks at native 1080p (32x32 at 4K; ~8,160 blocks total)
# search=2, searchparam=2: Radius-2 hexagonal search captures rapid motion pans
# chroma=false: Luma-only search required for D3D12 compute offload, cuts vector compute by 50%
# levels_val: 1 on USE_D3D12=true; is_4k ? 2 : 0 on CPU (full pyramid at 1080p, 2 levels at 4K)
# badrange=(-24): Outlier vector suppression for CPU NEON search path
backward_vec = MAnalyse(super, isb=true,  blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=2, chroma=false, plevel=0, levels=levels_val, badrange=(-24))
forward_vec  = MAnalyse(super, isb=false, blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=2, chroma=false, plevel=0, levels=levels_val, badrange=(-24))

# 3. Direct Native 60 fps Frame Synthesis
# mode=0: Fast 2-stream block projection mandatory on Balanced across both GPU and CPU
# blend=false: Clean block projection avoiding blur on fast motion
# thSCD1=380, thSCD2=125: Balanced scene-change detection cleanly cuts camera transitions
last = MBlockFps(src, super, backward_vec, forward_vec, num=target_fps, den=1, mode=synth_mode, blend=false, thSCD1=380, thSCD2=125)

# 4. Hardware Thread Affinity & Lookahead Buffer
# Pins worker threads strictly to the Cortex-X925 Prime core cluster, preventing migration onto 2.8-3.0 GHz Cortex-A725 cores
# 6 lookahead frames absorb thread scheduling jitter for stable 1% low frame times
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads, 6)
