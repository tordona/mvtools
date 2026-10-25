# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Generic x86-64 (Profile 1: Eco)
# Hardware: Generic 64-bit x86 (Intel Pentium/Celeron N-Series / Atom / Core / AMD)
# Target: Low-Power Fanless Budget Envelopes (~6W TDP e.g. N5000 / N4100 / N100)
# Architecture: Dynamic 0.5x Proxy Motion Estimation -> Native 1080p Synthesis
# Revision: 2.1.0 (2026-10-24)
# ==============================================================================

threads     = 3                   # 3 worker threads on quad-core CPUs leaves 1 core for OS/player
mem_limit   = 384                 # Lean memory footprint for low-power budget platforms

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded)
src = potplayer_source()

# Load MVTools2 plugin
LoadPlugin("mvtools2.dll")

# 1. Dynamic 0.5x Proxy Clip for High-Efficiency Search
# Downscales source by 2x preserving source aspect ratio (e.g. 16:9, 2.40:1 Scope, 4:3)
# levels=1 prevents MSuper from generating redundant pyramid reduction levels
search_w     = (src.Width  / 4) * 2
search_h     = (src.Height / 4) * 2
search_clip  = src.BilinearResize(search_w, search_h)
search_super = search_clip.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Ultra-Lightweight Single-Level Motion Vector Search on Proxy
# 32x16 rectangular blocks at 0.5x scale up to 64x32 at native resolution (~510 blocks total)
# levels=1: Strictly searches Level 0 (single level)
# search=2, searchparam=1: Radius-1 hexagonal search with minimal ALU overhead
# chroma=false: Luma-only search cuts vector computation by 50%
backward_proxy = MAnalyse(search_super, isb=true,  blksize=32, blksizev=16, search=2, searchparam=1, chroma=false, levels=1)
forward_proxy  = MAnalyse(search_super, isb=false, blksize=32, blksizev=16, search=2, searchparam=1, chroma=false, levels=1)

# 3. Mathematically Scale Vectors 2x up to Native Source Coordinates
backward_scaled = backward_proxy.MScaleVect(scale=2.0, scaleV=2.0, mode=0)
forward_scaled  = forward_proxy.MScaleVect(scale=2.0, scaleV=2.0, mode=0)

# 4. Native Frame Synthesis (ZERO RESOLUTION LOSS)
# Directly warps the original uncompressed source frames using scaled vectors
super_src = src.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)
MBlockFps(src, super_src, backward_scaled, forward_scaled, num=60, den=1, mode=0, blend=false, thSCD1=400, thSCD2=130)

# 5. Lookahead Queue
# 6 lookahead frames absorb thread scheduling jitter and smooth presentation
Prefetch(threads, 6)
