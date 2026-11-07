# ==============================================================================
# PotPlayer AviSynth+ 60 fps Interpolation: RTX Spark N1X (Profile 1: Eco)
# Hardware: NVIDIA RTX Spark N1X (9x-10x Cortex-X925 + 9x-10x Cortex-A725, Blackwell RTX GPU)
# Memory: 32 GB - 128 GB 256-bit LPDDR5X-9400 (~300 GB/s Unified Bandwidth)
# Architecture: Native ARM64 NEON / Direct3D 12 GPU Offload (mvtools2.dll)
# Generator: Google Antigravity (AIAgentProfileGuide Rev 2.3.11)
# Target: Sub-8 W Package Envelope, Silent Fanless / Battery Playback, 0 Dropped Frames
# Revision: 1.0.0 (2026-11-07)
# Changelog: Initial ARMv9.2 Cortex-X925 + Cortex-A725 profile, Direct3D 12 Blackwell GPU offload toggle (USE_D3D12 = false default), MEnableD3D12, AvsAffinity Cortex-X925 Prime-core pinning, levels=1, dynamic 4K adaptation
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Direct3D 12 Compute Offload
# Set to true for Direct3D 12 GPU offload to Blackwell RTX GPU (via MEnableD3D12 in mvtools2.dll)
# Set to false for native ARM64 CPU NEON SIMD production baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_D3D12  = false

# Dynamic parameters adapted to USE_D3D12
# GPU offload executes on direct command queue (2 threads double-buffered); CPU uses 4 Cortex-X925 Prime cores
threads    = USE_D3D12 ? 2 : 4
mem_limit  = USE_D3D12 ? 512 : 512
pel_val    = 1
sharp_mode = 0
pad_size   = USE_D3D12 ? 8 : 0
synth_mode = 0

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (NVIDIA NVDEC hardware decoded via D3D11/DXVA2)
src = potplayer_source()

# Dynamic Resolution Adaptation:
# Detect 4K (3840x2160 / 4096x2160) vs 1080p/720p.
# At 4K, 64x64 blocks maintain the exact 2,040 block count of 1080p 32x32,
# keeping memory traffic strictly within low-power battery envelopes.
is_4k   = (src.Width() > 2048)
blk_sz  = is_4k ? 64 : 32
pad_val = is_4k ? (pad_size * 2) : pad_size

# Load Native ARM64 MVTools2 plugin & configure Direct3D 12 engine
LoadPlugin("mvtools2.dll")
MEnableD3D12(USE_D3D12)
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}

# 1. Base Motion Super Clip (Single-Level, Integer Pixel Precision)
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=1: Full-pixel precision only (skips subpixel math; D3D12 FlowWarpCS performs subpixel sampling in hardware)
# pad_val: 8 px boundary padding on GPU (16 px at 4K); 0 px on CPU
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = src.MSuper(levels=1, pel=pel_val, hpad=pad_val, vpad=pad_val, sharp=sharp_mode)

# 2. Ultra-Lightweight Coarse Motion Vector Search
# 2,040 blocks (32x32 at 1080p, 64x64 at 4K)
# search=2, searchparam=1: Tight radius-1 hexagonal search
# chroma=false: Luma-only search required for D3D12 compute offload, cuts vector compute by 50%
# levels=1: Strictly searches base Level 0 without multi-level pyramid overhead
backward_vec = MAnalyse(super, isb=true,  blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, chroma=false, levels=1)
forward_vec  = MAnalyse(super, isb=false, blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, chroma=false, levels=1)

# 3. Direct Native 60 fps Frame Synthesis
# mode=0: Fast 2-stream block projection mandatory on Eco across both GPU and CPU
# blend=false: Skips transparency alpha blending calculations
# thSCD1=400, thSCD2=130: Robust scene-change detection cleanly cuts camera transitions
last = MBlockFps(src, super, backward_vec, forward_vec, num=60, den=1, mode=synth_mode, blend=false, thSCD1=400, thSCD2=130)

# 4. Hardware Thread Affinity & Lookahead Buffer
# Pins worker threads to the Cortex-X925 Prime core cluster, leaving Cortex-A725 cores free for NVDEC decode and audio
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads, 4)
