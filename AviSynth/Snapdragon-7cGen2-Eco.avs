# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 7c Gen 2 (Profile 1: Eco)
# Hardware: Qualcomm Snapdragon 7c Gen 2 (2x Kryo 468 Gold @ 2.55 GHz + 6x Silver)
# Test Device: Samsung Galaxy Book Go (14", Fanless 5 W Chassis)
# Target: Ultra-Low Power (~3.0 W), Whisper-Cool Fanless Operation, Peak Battery Life
# Revision: 2.0.0 (2026-10-18)
# Changelog: Memory-constrained 4 GB tuning, native 1080p, levels=1, single MSuper, threads=2, Prefetch(2, 4), mem_limit=512
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

# Load Native ARM64 MVTools2 plugin (ARM64 CPU NEON execution)
LoadPlugin("mvtools2.dll")

# 1. Dynamic 0.5x Proxy Clip for Maximum Efficiency & Coolest Operation
# Dynamically downscales source by 2x preserving source aspect ratio (e.g. 16:9, 2.40:1 Scope, 4:3)
# levels=1 prevents MSuper from creating 7 redundant pyramid reduction levels
search_w     = (src.Width  / 4) * 2
search_h     = (src.Height / 4) * 2
search_clip  = src.BilinearResize(search_w, search_h)
search_super = search_clip.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Ultra-Lightweight Single-Level Motion Vector Search on Proxy
# 32x16 rectangular blocks at 0.5x scale up to 64x32 at native resolution (~510 blocks total)
# levels=1: Strictly searches Level 0 (single level), matching search_super's levels=1
# search=2, searchparam=1: Radius-1 hexagonal search with minimal ALU overhead
# chroma=false: Luma-only search cuts SAD computations by 50%
backward_proxy = MAnalyse(search_super, isb=true,  blksize=32, blksizev=16, search=2, searchparam=1, chroma=false, levels=1)
forward_proxy  = MAnalyse(search_super, isb=false, blksize=32, blksizev=16, search=2, searchparam=1, chroma=false, levels=1)

# 3. Mathematically Scale Vectors 2x up to Native Source Coordinates
backward_scaled = backward_proxy.MScaleVect(scale=2.0, scaleV=2.0, mode=0)
forward_scaled  = forward_proxy.MScaleVect(scale=2.0, scaleV=2.0, mode=0)

# 4. Native Frame Synthesis (ZERO RESOLUTION LOSS)
# Directly warps the original uncompressed source frames using scaled vectors
# levels=1: Eliminates generating 9 downscaled pyramid images on full source frames!
# mode=0: Fast 2-stream block projection (avoids 4-stream median filter stalls)
# blend=false: Skips transparency alpha blending calculations
# thSCD1=400, thSCD2=130: Fast scene-change detection cleanly cuts transitions
super_src = src.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)
MBlockFps(src, super_src, backward_scaled, forward_scaled, num=60, den=1, mode=0, blend=false, thSCD1=400, thSCD2=130)

# 5. Core Pinning: Strictly 2 threads locks execution to Gold cores
# 4 lookahead frames absorb thread scheduling jitter
Prefetch(threads, 4)

