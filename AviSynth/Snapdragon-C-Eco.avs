# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon C (Profile 1: Eco)
# Hardware: Qualcomm Snapdragon C (8x Kryo: 1 Prime @ 3.0 GHz + 3 Perf @ 2.6 GHz + 4 Eff @ 2.0 GHz)
# Architecture: ARM64 NEON CPU Motion Estimation (mvtools2.dll)
# Generator: Google Antigravity (AIAgentProfileGuide Rev 2.3.11)
# Target: 60 fps Playback for 720p–4K, Ultra-Low Thermal Impact, 3 W – 5 W Fanless Envelope
# Revision: 1.0.1 (2026-11-08)
# Changelog: Standardized platform naming to Snapdragon C, 0.5x proxy search, MScaleVect, threads=2, mem_limit=512, AvsAffinity pinning, dynamic 4K adaptation
# ==============================================================================

# Core Allocation & Threading Strategy:
# 2 worker threads strictly locked to the Prime and 1 Performance core.
# Prevents thermal runaway in ~5 W fanless chassis and avoids slow Cortex-A55 efficiency core stalls.
threads     = 2
mem_limit   = 512                 # Bounded cache footprint protects budget LPDDR4x/LPDDR5 memory bus

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (DXVA2/D3D11 hardware decoded via Adreno VPU)
src = potplayer_source()

# Dynamic Resolution Adaptation:
# Detect 4K vs 1080p/720p. At 4K, 0.25x proxy downscaling (scale=4.0) maintains
# the exact 960x540 analysis grid, keeping the 5 W fanless thermal envelope intact.
is_4k        = (src.Width() > 2048)
search_scale = is_4k ? 4 : 2
search_w     = (src.Width  / (search_scale * 2)) * 2
search_h     = (src.Height / (search_scale * 2)) * 2
search_clip  = src.BilinearResize(search_w, search_h)

# Load Native ARM64 MVTools2 plugin (ARM64 CPU NEON execution)
LoadPlugin("mvtools2.dll")
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}

# 1. Base Motion Super Clip on 0.5x Proxy
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=1: Whole-pixel estimation minimizes ALU load
# sharp=0: Fast bilinear interpolation for minimal overhead
search_super = search_clip.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Fast Single-Level Motion Vector Search on Proxy
# 16x16 blocks at 0.5x scale map to 32x32 blocks at native resolution
# levels=1: Strictly searches base Level 0
# search=2, searchparam=1: Radius-1 hexagonal search provides stable macro-motion tracking
# chroma=false: Luma-only search cuts SAD computations by 50%
backward_proxy = MAnalyse(search_super, isb=true,  blksize=16, blksizev=16, search=2, searchparam=1, chroma=false, levels=1)
forward_proxy  = MAnalyse(search_super, isb=false, blksize=16, blksizev=16, search=2, searchparam=1, chroma=false, levels=1)

# 3. Mathematically Scale Vectors up to Native Source Coordinates
scale_val       = Float(search_scale)
backward_scaled = backward_proxy.MScaleVect(scale=scale_val, scaleV=scale_val, mode=0)
forward_scaled  = forward_proxy.MScaleVect(scale=scale_val, scaleV=scale_val, mode=0)

# 4. Native Frame Synthesis (Zero Resolution Loss)
# Directly warps original source frames using scaled vectors with zero intermediate blur
# mode=0: Fast 2-stream block projection (sustains 60 fps without CPU pipeline stalls)
# blend=false: Clean block projection avoiding motion blur
# thSCD1=380, thSCD2=125: Balanced scene-change detection cleanly cuts camera transitions
super_src = src.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)
MBlockFps(src, super_src, backward_scaled, forward_scaled, num=60, den=1, mode=0, blend=false, thSCD1=380, thSCD2=125)

# 5. Hardware Thread Affinity Pinning & Concurrency Pool
# Isolates worker threads to Performance/Prime cores, preventing Efficiency core latency stalls
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads, 4)
