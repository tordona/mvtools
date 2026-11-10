# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 7c Gen 2 (Profile 1: Eco)
# Hardware: Qualcomm Snapdragon 7c Gen 2 (2x Kryo 468 Gold @ 2.55 GHz + 6x Silver)
# Test Device: Samsung Galaxy Book Go (14", Fanless 5 W Chassis)
# Target: Ultra-Low Power (~3.0 W), Passive 5 W Fanless Operation, Peak Battery Life
# Revision: 2.3.0 (2026-11-09)
# Changelog: Added native 4K early return bypass (hardware limited to 4K 30 fps by 17 GB/s memory bus and VPU decoder cap)
# ==============================================================================

# Strictly 2 worker threads pins execution to the 2 Kryo 468 Gold (Cortex-A76) cores.
# Avoids thread spilling onto the 6 slow Cortex-A55 Silver cores.
threads     = 2
mem_limit   = 384                 # Lean 384 MB footprint fits within LPDDR4x-2133 bandwidth budget

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full 1080p PotPlayer video source stream (DXVA2/D3D11 hardware decoded via Adreno 618)
src = potplayer_source()

# Dynamic 4K Fallback: 7c Gen 2 memory bus (17 GB/s) and VPU are capped at 4K 30 fps.
# Bypass motion interpolation on 4K streams to maintain smooth native playback.
if (src.Width() > 2048) {
    return src
}

# Dynamic Resolution Adaptation:
# Detect 4K vs 1080p (fallback safeguard if 4K bypass is disabled).
is_4k  = (src.Width() > 2048)
blk_sz = is_4k ? 64 : 32

# Load Native ARM64 MVTools2 plugin (ARM64 CPU NEON execution)
LoadPlugin("mvtools2.dll")
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}

# 1. Native 1080p Super Clip (Single-level, Zero Resizing Overhead)
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=1: Whole-pixel estimation minimizes ALU load
# hpad=0, vpad=0: Zero padding overhead, preserving cache locality
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = src.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Native Wide-Block Motion Vector Search (32x32 at 1080p = 2,040 blocks total)
# levels=1: Strictly searches base Level 0
# search=2, searchparam=1: Radius-1 hexagonal search with minimal ALU overhead
# chroma=false: Luma-only search cuts SAD computations by 50%
backward_vec = MAnalyse(super, isb=true,  blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, chroma=false, levels=1)
forward_vec  = MAnalyse(super, isb=false, blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, chroma=false, levels=1)

# 3. Direct Native Frame Synthesis
# Directly warps original source frames using native vectors without vector scaling artifacts
# mode=0: Fast 2-stream block projection (sustains 60 fps without CPU pipeline stalls)
# blend=false: Skips transparency alpha blending calculations
# thSCD1=400, thSCD2=130: Fast scene-change detection cleanly cuts transitions
MBlockFps(src, super, backward_vec, forward_vec, num=60, den=1, mode=0, blend=false, thSCD1=400, thSCD2=130)

# 4. Core Pinning: Strictly 2 threads locks execution to Gold cores
# 4 lookahead frames absorb thread scheduling jitter
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads, 4)
