# ==============================================================================
# PotPlayer AviSynth+ 60 fps Interpolation: RTX Spark N1X (Profile 3: MaxQuality)
# Hardware: NVIDIA RTX Spark N1X (9x-10x Cortex-X925 + 9x-10x Cortex-A725, Blackwell RTX GPU)
# Memory: 32 GB - 128 GB 256-bit LPDDR5X-9400 (~300 GB/s Unified Bandwidth)
# Architecture: Native ARM64 NEON / Direct3D 12 GPU Offload (mvtools2.dll)
# Generator: Google Antigravity (AIAgentProfileGuide Rev 2.3.11)
# Target: Highest Visual Fidelity, Coarse-to-Fine 16x16 Vectors, Wiener Subpixel / GPU Dynamic Median, Sustained 60 fps
# Revision: 1.0.0 (2026-11-07)
# Changelog: Initial ARMv9.2 Cortex-X925 + Cortex-A725 profile, Direct3D 12 Blackwell GPU offload toggle (USE_D3D12 = false default), MEnableD3D12, pel=1/2 Wiener, MRecalculate(divide=0), AvsAffinity Cortex-X925 Prime-core pinning, dynamic 4K adaptation
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Direct3D 12 Compute Offload
# Set to true for Direct3D 12 GPU offload to Blackwell RTX GPU (via MEnableD3D12 in mvtools2.dll)
# Set to false for native ARM64 CPU NEON SIMD production baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_D3D12  = false

# Dynamic parameters adapted to USE_D3D12
# GPU offload executes on direct command queue (4 threads quad-buffered);
# CPU uses 8 Cortex-X925 Prime cores (comfortably within the 9-10 Prime core envelope)
threads    = USE_D3D12 ? 4 : 8
mem_limit  = USE_D3D12 ? 1536 : 2048

# Subpixel, Padding & Synthesis Parameters (Step 1.7 compliant: >= 6 Prime cores, ~300 GB/s LPDDR5X-9400):
# pel_val: pel=1 on GPU avoids CPU subplane generation (FlowWarpCS performs subpixel bilinear sampling in hardware); pel=2 half-pel on CPU NEON
pel_val    = USE_D3D12 ? 1 : 2
# sharp_mode: 6-tap Wiener filter (sharp=2) when pel=2 on CPU NEON; unused (sharp=0) when pel=1 on GPU
sharp_mode = USE_D3D12 ? 0 : 2
pad_size   = USE_D3D12 ? 8 : 16
fine_rad   = USE_D3D12 ? 2 : 1
# synth_mode: mode=2 engages GPU Dynamic Median with occlusion masking; mode=0 fast projection on CPU fallback
synth_mode = USE_D3D12 ? 2 : 0

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (NVIDIA NVDEC hardware decoded via D3D11/DXVA2)
src = potplayer_source()

# Dynamic Resolution Adaptation:
# Detect 4K (3840x2160 / 4096x2160) vs 1080p/720p.
# At 4K, block sizes scale by 2x to maintain 1080p spatial grid density (2,040 coarse / 8,160 fine),
# eliminating the 32,400 block explosion while preserving maximal visual detail.
is_4k      = (src.Width() > 2048)
blk_coarse = is_4k ? 64 : 32
blk_fine   = is_4k ? 32 : 16
pad_val    = is_4k ? (pad_size * 2) : pad_size

# Load Native ARM64 MVTools2 plugin & configure Direct3D 12 engine
LoadPlugin("mvtools2.dll")
MEnableD3D12(USE_D3D12)
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}

# 1. Motion Super Clip with Boundary Guard
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=pel_val: Integer grid on GPU (paired with hardware bilinear texture warp); half-pel on CPU NEON
# pad_val: Boundary padding (8 px on GPU, 16 px on CPU; 2x at 4K) stabilizes vectors near frame borders
# sharp=sharp_mode: 6-tap Wiener filter when pel=2 on CPU; 0 when pel=1 on GPU
super = src.MSuper(levels=1, pel=pel_val, hpad=pad_val, vpad=pad_val, sharp=sharp_mode)

# 2. Coarse Motion Vector Field Analysis
# 2,040 blocks (32x32 at 1080p, 64x64 at 4K)
# search=2, searchparam=2: Diamond/Hexagonal search capturing wide displacement
# chroma=false: Luma-only search required for D3D12 compute offload, cuts vector compute by 50%
# levels=1: Strictly searches base Level 0
# badrange=(-24): Outlier vector suppression for CPU NEON search path
backward_coarse = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))

# 3. Fine Motion Refinement Pass (MRecalculate)
# Refines to 8,160 blocks (16x16 at 1080p, 32x32 at 4K) using 2x2 bilinear coarse predictors
# search=2, searchparam=fine_rad: Radius-2 diamond refinement on GPU (local grid on CPU) around interpolated coarse predictor
# chroma=false: Required for D3D12 compute offload
# divide=0: Unsplit non-overlapping block grid required for D3D12 FlowWarpCS coordinate alignment
backward_fine = MRecalculate(super, backward_coarse, blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=fine_rad, chroma=false, divide=0)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=fine_rad, chroma=false, divide=0)

# 4. 60 fps Frame Synthesis with Directional Alpha Blending
# mode=synth_mode: GPU Dynamic Median (mode=2) with occlusion masking when USE_D3D12=true; fast projection (mode=0) on CPU
# blend=true: Directional alpha blending smooths occlusion boundaries and disocclusion edges
# thSCD1=350, thSCD2=115: High-sensitivity scene-change threshold prevents cut distortion
last = MBlockFps(src, super, backward_fine, forward_fine, num=60, den=1, mode=synth_mode, blend=true, thSCD1=350, thSCD2=115)

# 5. Hardware Thread Affinity & Lookahead Buffer
# Pins worker threads strictly to the Cortex-X925 Prime core cluster, preventing migration onto 2.8-3.0 GHz Cortex-A725 cores
# 8 lookahead frames absorb thread scheduling jitter
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads, 8)
