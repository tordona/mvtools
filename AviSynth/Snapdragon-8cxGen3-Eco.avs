# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 8cx Gen 3 (Profile 1: Eco)
# Hardware: Qualcomm Snapdragon 8cx Gen 3 / Microsoft SQ3 (4x Cortex-X1 + 4x Cortex-A78, Adreno 690)
# Target: Ultra-Low Power, Maximum Battery Longevity, 0 Dropped Frames
# Revision: 2.3.4 (2026-11-17)
# Changelog: Updated pyramid levels to USE_D3D12 ? 1 : (is_4k ? 2 : 0) with plevel=0 for tear-free panning; Parameterized target_fps (default 60, capped at 60 fps on 4K) with target-relative frame rate bypass; Single MSuper, levels=levels_val, threads=3, Prefetch(3, 4), mem_limit=768/512, D3D12 toggle, AvsAffinity pinning, dynamic 4K adaptation, standardized src source clip and src.Width() 4K adaptation
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Direct3D 12 Compute Offload
# Set to true for Direct3D 12 Adreno GPU offload (via MEnableD3D12 in mvtools2.dll)
# Set to false for original ARM64 CPU NEON baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_D3D12 = false

# Dynamic parameters adapted to USE_D3D12
# GPU: 3 threads keeps queue full; CPU: 3 threads on Cortex-X1 leaves 1 X1 + all 4 Cortex-A78 cores idle
threads     = USE_D3D12 ? 3 : 3
mem_limit   = USE_D3D12 ? 512 : 768
target_fps  = 60                  # Target output frame rate (e.g. 60 or 120)

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
# At 4K, 64x64 blocks maintain the exact 2,040 block count of 1080p 32x32,
# keeping CPU and GPU memory traffic within low-power battery envelopes.
levels_val = USE_D3D12 ? 1 : (is_4k ? 2 : 0)
blk_sz= is_4k ? 64 : 32

# Load Native ARM64 MVTools2 plugin
LoadPlugin("mvtools2.dll")
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}
MEnableD3D12(USE_D3D12)

# 1. Base Motion Super Clip (Integer Pixel Precision)
# levels=levels_val: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=1: Whole-pixel estimation for minimal ALU and memory overhead
# hpad=0, vpad=0: No padding overhead to minimize cache pressure
# sharp=0: Fast bilinear interpolation for minimal load
super = src.MSuper(levels=levels_val, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Ultra-Lightweight Coarse Motion Analysis
# 2,040 blocks (32x32 at 1080p, 64x64 at 4K)
# search=2: Hexagonal search pattern (fast and stable)
# searchparam=1: Minimal search radius to limit vector comparisons
# chroma=false: Evaluates luminance only, saving 50% vector computation
# levels=levels_val: Strictly searches base Level 0 without multi-level pyramid overhead
backward_vec = MAnalyse(super, isb=true,  blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, plevel=0, chroma=false, levels=levels_val)
forward_vec  = MAnalyse(super, isb=false, blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, plevel=0, chroma=false, levels=levels_val)

# 3. Direct Block-Based 60 fps Synthesis
# mode=0: Fast block projection (least computationally intensive mode)
# blend=false: Avoids calculating blend transparency masks on fast motion
# thSCD1=400, thSCD2=130: Fast scene-change detection to immediately cut across scene changes
MBlockFps(super, backward_vec, forward_vec, num=target_fps, den=1, mode=0, blend=false, thSCD1=400, thSCD2=130)

# 4. Core Pinning: Strictly 3 Threads with 4 Lookahead Frames
# Utilizes 3 of the 4 Cortex-X1 Prime cores; leaves 1 X1 + all 4 Cortex-A78 cores idle.
# 4 lookahead frames absorb thread scheduling jitter and prevent presentation drops.
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads, 4)

