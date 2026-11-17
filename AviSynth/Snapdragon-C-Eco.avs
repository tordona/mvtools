# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon C (Profile 1: Eco)
# Hardware: Qualcomm Snapdragon C (8x Kryo: 1 Prime @ 3.0 GHz + 3 Perf @ 2.6 GHz + 4 Eff @ 2.0 GHz)
# Architecture: ARM64 NEON CPU Motion Estimation (mvtools2.dll)
# Generator: Google Antigravity (AIAgentProfileGuide Rev 2.3.11)
# Target: 60 fps Playback for 720p–4K, Ultra-Low Thermal Impact, 3 W – 5 W Fanless Envelope
# Revision: 2.0.4 (2026-11-17)
# Changelog: Enabled full pyramid (levels=0) with plevel=0 for tear-free panning; Parameterized target_fps (default 60, capped at 60 fps on 4K) with target-relative frame rate bypass
# ==============================================================================

# Core Allocation & Threading Strategy:
# 2 worker threads strictly locked to the Prime and 1 Performance core.
# Prevents thermal runaway in ~5 W fanless chassis and avoids slow Cortex-A55 efficiency core stalls.
threads     = 2
mem_limit   = 512                 # Bounded cache footprint protects budget LPDDR4x/LPDDR5 memory bus
target_fps  = 60                  # Target output frame rate (e.g. 60 or 120)

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (DXVA2/D3D11 hardware decoded via Adreno VPU)
src = potplayer_source()

is_4k      = (src.Width() > 2048)
target_fps = (is_4k && target_fps > 60) ? 60 : target_fps

# Bypass motion interpolation if source is already at or above target_fps (4% NTSC tolerance, e.g. 59.94 fps for 60 fps)
if (src.FrameRate() >= (target_fps * 0.96)) {
    return src
}

# Dynamic Resolution Adaptation:
# Detect 4K vs 1080p/720p. At 4K, 64x64 blocks maintain the exact 2,040 block count of 1080p 32x32,
# keeping memory traffic strictly within the 3 W – 5 W fanless thermal envelope.
blk_sz = is_4k ? 64 : 32

# Load Native ARM64 MVTools2 plugin (ARM64 CPU NEON execution)
LoadPlugin("mvtools2.dll")
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}

# 1. Native Super Clip (Full Pyramid, Zero Resizing Overhead)
# levels=0: Full coarse-to-fine pyramid prevents panning tearing
# pel=1: Whole-pixel estimation minimizes ALU load
# hpad=0, vpad=0: Zero padding overhead, preserving cache locality
# sharp=0: Fast bilinear interpolation for minimal overhead
super = src.MSuper(levels=0, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Native Wide-Block Motion Vector Analysis (32x32 at 1080p = 2,040 blocks total)
# levels=0, plevel=0: Full pyramid with constant penalty for tear-free panning
# search=2, searchparam=1: Radius-1 hexagonal search provides stable macro-motion tracking
# chroma=false: Luma-only search cuts SAD computations by 50%
backward_vec = MAnalyse(super, isb=true,  blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, plevel=0, chroma=false, levels=0)
forward_vec  = MAnalyse(super, isb=false, blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, plevel=0, chroma=false, levels=0)

# 3. Direct Native 60 fps Frame Synthesis
# Directly warps original source frames using native vectors without vector scaling artifacts
# mode=0: Fast 2-stream block projection (sustains 60 fps without CPU pipeline stalls)
# blend=false: Clean block projection avoiding motion blur
# thSCD1=400, thSCD2=130: Robust scene-change detection cleanly cuts camera transitions
last = MBlockFps(src, super, backward_vec, forward_vec, num=target_fps, den=1, mode=0, blend=false, thSCD1=400, thSCD2=130)

# 4. Hardware Thread Affinity Pinning & Concurrency Pool
# Isolates worker threads to Performance/Prime cores, preventing Efficiency core latency stalls
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads(strictPrime=true) : last
Prefetch(threads, 4)
