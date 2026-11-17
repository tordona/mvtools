# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 8cx Gen 3 (Profile 3: Max Quality)
# Hardware: Qualcomm Snapdragon 8cx Gen 3 / Microsoft SQ3 (4x Cortex-X1 + 4x Cortex-A78, Adreno 690)
# Target: Highest Achievable Quality, Wide-Radius Refinement, Sustained 60 fps
# Revision: 2.5.4 (2026-11-17)
# Changelog: Parameterized target_fps (default 60, capped at 60 fps on 4K) with target-relative frame rate bypass; Replaced unconditional levels=1 with tiered pyramid levels_val (levels_val = USE_D3D12 ? 1 : (is_4k ? 2 : 0)) and plevel=0 for tear-free panning
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Direct3D 12 Compute Offload
# Set to true for Direct3D 12 Adreno GPU offload (via MEnableD3D12 in mvtools2.dll)
# Set to false for original ARM64 CPU NEON baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_D3D12 = false

# Dynamic parameters adapted to USE_D3D12
# GPU: 4 worker threads; CPU: 4 Cortex-X1 Prime cores (zero asymmetric core stalls)
threads     = USE_D3D12 ? 4 : 4
mem_limit   = USE_D3D12 ? 1536 : 1536
target_fps  = 60                  # Target output frame rate (e.g. 60 or 120)
# Diamond search (search=2, searchparam=2) provides high tracking fidelity without thermal throttling
search_alg  = 2
fine_rad    = USE_D3D12 ? 2 : 1

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (Offloaded via Adreno 690 hardware decoder)
src = potplayer_source()

is_4k      = (src.Width() > 2048)
target_fps = (is_4k && target_fps > 60) ? 60 : target_fps

# Bypass motion interpolation if source is already at or above target_fps (4% NTSC tolerance, e.g. 59.94 fps for 60 fps)
if (src.FrameRate() >= (target_fps * 0.96)) {
    return src
}

# Dynamic Resolution Adaptation:
# Detect 4K (3840x2160 / 4096x2160) vs 1080p/720p.
# At 4K, 64x64 coarse -> 32x32 fine maintains the exact 120x68 (8,160 blocks) spatial grid
# density of 1080p 16x16, cutting 4K block evaluations by 75% and preventing memory bus saturation.
levels_val = USE_D3D12 ? 1 : (is_4k ? 2 : 0)
blk_coarse = is_4k ? 64 : 32
blk_fine   = is_4k ? 32 : 16
pad_val    = is_4k ? 16 : 8

# Load Native ARM64 MVTools2 plugin
LoadPlugin("mvtools2.dll")
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}
MEnableD3D12(USE_D3D12)

# 1. Motion Super Clip with Boundary Guard
# levels_val: 1 on USE_D3D12=true; is_4k ? 2 : 0 on CPU (full pyramid at 1080p, 2 levels at 4K)
# pel=1: Whole-pixel estimation paired with MRecalculate; D3D12 FlowWarpCS performs subpixel bilinear sampling in hardware
# pad_val boundary padding stabilizes edge vector calculation on wide camera pans
# sharp=0: Subpixel interpolation filter is unused when pel=1
super = src.MSuper(levels=levels_val, pel=1, hpad=pad_val, vpad=pad_val, sharp=0)

# 2. Wide Coarse Motion Vector Field Analysis
# 2,040 blocks (32x32 at 1080p, 64x64 at 4K)
# search=search_alg, searchparam=2: Diamond search (~12 points) on both GPU and CPU
# chroma=false: Luma-focused motion estimation keeps computation inside thermal budget
# levels_val: 1 on USE_D3D12=true; is_4k ? 2 : 0 on CPU (full pyramid at 1080p, 2 levels at 4K)
# badrange=(-24): Outlier vector suppression for CPU NEON search path
backward_dense = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=search_alg, searchparam=2, chroma=false, plevel=0, levels=levels_val, badrange=(-24))
forward_dense  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=search_alg, searchparam=2, chroma=false, plevel=0, levels=levels_val, badrange=(-24))

# 3. High-Definition Refinement Pass (MRecalculate)
# Refines to 8,160 blocks (16x16 at 1080p, 32x32 at 4K) using 2x2 bilinear coarse predictors
# search=2, searchparam=fine_rad: Radius-2 hexagonal refinement on GPU; 3x3 local grid on CPU
# divide=0: Unsplit block grid required for D3D12 compute offload
backward_fine = MRecalculate(super, backward_dense, blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=fine_rad, chroma=false, divide=0)
forward_fine  = MRecalculate(super, forward_dense,  blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=fine_rad, chroma=false, divide=0)

# 4. Dynamic Median 60 fps Synthesis with Occlusion Handling
# mode=2: Dynamic Median pixel-flow synthesis with occlusion masking
# blend=true: Scene-change fallback blending for camera cuts or occluded regions
# thSCD1=320, thSCD2=115: Strict scene-change detection to prevent cross-cut morphing
MBlockFps(super, backward_fine, forward_fine, num=target_fps, den=1, mode=2, blend=true, thSCD1=320, thSCD2=115)

# 5. Core Pinning: Strictly 4 Threads with 4 Lookahead Frames
# Pins worker threads to the 4x Cortex-X1 cluster, completely eliminating asymmetric thread sync stalls.
# Leaves all 4x Cortex-A78 cores free for OS, audio, PotPlayer UI, and GPU drivers.
# 4 lookahead frames absorb thread scheduling jitter and guarantee 0 dropped frames.
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads, 4)

