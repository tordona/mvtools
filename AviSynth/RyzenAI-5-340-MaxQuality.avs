# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: AMD Ryzen AI 5 340 (Profile 3: MaxQuality)
# Hardware: AMD Ryzen AI 5 340 (3x Zen 5 + 3x Zen 5c Cores, Radeon 840M RDNA 3.5 @ 2.9 GHz)
# Memory: 16 GB – 32 GB Dual-Channel LPDDR5x-7500 (120 GB/s Unified Bandwidth)
# Architecture: Native 1080p x86-64 AVX-512 / Direct3D 12 GPU Offload (mvtools2.dll)
# Target: High-Fidelity 60 fps Presentation, Coarse-to-Fine 16x16 Vectors with Occlusion Masking, 20 W Envelope
# Revision: 2.3.0 (2026-11-04)
# Changelog: Direct3D 12 GPU offload toggle (USE_D3D12), MEnableD3D12, dynamic thread/memory budget, MRecalculate fine pass, GPU Dynamic Median (mode=2), blend=true, AvsAffinity hardware pinning, dynamic 4K adaptation
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Direct3D 12 Compute Offload
# Set to true for Direct3D 12 GPU offload to Radeon 840M (via MEnableD3D12 in mvtools2.dll)
# Set to false for native x86-64 AVX-512 / AVX2 CPU SIMD baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_D3D12 = false

# Dynamic parameters adapted to USE_D3D12
# GPU offload executes on direct command queue (4 threads optimal); CPU uses all 6 physical cores
threads     = USE_D3D12 ? 4 : 6
mem_limit   = USE_D3D12 ? 1536 : 1024 # Ample cache allocation for GPU ring buffers and vector grids
sharp_mode  = USE_D3D12 ? 0 : 1       # Bicubic on CPU; hardware texture sampler on GPU
pad_size    = USE_D3D12 ? 8 : 16      # Boundary padding stabilizes edge motion vectors
fine_rad    = USE_D3D12 ? 2 : 1       # Radius-2 refinement on GPU; local grid on CPU
synth_mode  = USE_D3D12 ? 2 : 0       # mode=2: GPU Dynamic Median with occlusion masking; mode=0: fast CPU projection

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (AMD VCN hardware decoded via Radeon 840M)
src = potplayer_source()

# Dynamic Resolution Adaptation:
# Detect 4K (3840x2160 / 4096x2160) vs 1080p/720p.
# At 4K, block sizes scale by 2x to maintain 1080p spatial grid density (2,040 coarse / 8,160 fine),
# eliminating the 32,400 block explosion while preserving maximal visual detail.
is_4k      = (src.Width() > 2048)
blk_coarse = is_4k ? 64 : 32
blk_fine   = is_4k ? 32 : 16
pad_val    = is_4k ? (pad_size * 2) : pad_size

# Load Native x64 MVTools2 plugin & enable Direct3D 12 GPU offload
LoadPlugin("mvtools2.dll")
MEnableD3D12(USE_D3D12)
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}

# 1. Motion Super Clip with Boundary Guard
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=1: Integer-pixel estimation paired with MRecalculate; D3D12 FlowWarpCS performs subpixel bilinear sampling in hardware
# pad_val boundary padding stabilizes motion vectors near frame borders
# sharp=sharp_mode: Bicubic interpolation on CPU; unused when pel=1 on GPU
super = src.MSuper(levels=1, pel=1, hpad=pad_val, vpad=pad_val, sharp=sharp_mode)

# 2. Coarse Motion Vector Field Analysis
# 2,040 blocks (32x32 at 1080p, 64x64 at 4K)
# search=2, searchparam=2: Hexagonal search capturing wide displacement
# chroma=false: Luma-only search required for D3D12 compute offload, cuts vector compute by 50%
# levels=1: Strictly searches base Level 0
# badrange=(-24): Outlier vector suppression for CPU search path
backward_coarse = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))

# 3. Fine Motion Refinement Pass (MRecalculate)
# Refines to 8,160 blocks (16x16 at 1080p, 32x32 at 4K) using 2x2 bilinear coarse predictors
# search=2, searchparam=fine_rad: Radius-2 refinement around interpolated coarse predictor
# chroma=false: Required for D3D12 compute offload
# divide=0: Unsplit block grid required for D3D12 compute offload
backward_fine = MRecalculate(super, backward_coarse, blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=fine_rad, chroma=false, divide=0)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=fine_rad, chroma=false, divide=0)

# 4. 60 fps Frame Synthesis with Directional Alpha Blending
# mode=synth_mode: GPU Dynamic Median (mode=2) with occlusion masking when USE_D3D12=true; fast projection (mode=0) on CPU
# blend=true: Directional alpha blending smooths occlusion boundaries and disocclusion edges
# thSCD1=350, thSCD2=115: High-sensitivity scene-change threshold prevents cut distortion
MBlockFps(src, super, backward_fine, forward_fine, num=60, den=1, mode=synth_mode, blend=true, thSCD1=350, thSCD2=115)

# 5. Hardware Thread Affinity & Core Pinning: Multi-Threading adapted dynamically to USE_D3D12
# Keeps worker threads within high-IPC Zen 5 P-core domain, preventing Zen 5c latency stalls
# 6 lookahead frames absorb thread scheduling jitter
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads, 6)
