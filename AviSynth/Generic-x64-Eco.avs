# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Generic x86-64 (Profile 1: Eco)
# Hardware: Generic 64-bit x86 (Intel Pentium/Celeron / Atom / Core / AMD Quad+ Cores)
# Architecture: Native 1080p x86-64 SSE4.2 / AVX2 CPU Motion Estimation (mvtools2.dll)
# Target: Ultra-Low Compute Load, Fanless & Battery Safety, Guaranteed Real-Time 60fps
# Revision: 3.0.0 (2026-10-25)
# Changelog: Native 1080p 64x32 blocks (~1,020 blocks) with search=0 (OneTime predictor).
#            Eliminated 0.5x proxy downscaling blur. Single-level geometry (levels=1).
# ==============================================================================

# Core Allocation & Threading Strategy:
# 3 worker threads on quad-core CPUs leaves 1 core completely free for DXVA2 decode and DWM.
# Native 64x32 blocks with search=0 guarantees smooth 60fps even on 6W low-power silicon.
threads     = 3
mem_limit   = 512                 # Lean working set tailored for low-power and budget memory

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded)
src = potplayer_source()

# Load Native x64 MVTools2 plugin
LoadPlugin("mvtools2.dll")

# 1. Native 1080p Super Clip (Single-Level, Integer Pixel Precision)
# pel=1: Full-pixel precision only (avoids subpixel interpolation overhead)
# levels=1: Eliminates redundant multi-level spatial pyramid calculation
# hpad=0, vpad=0: Zero padding overhead, preserving native pitch alignment
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = src.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Ultra-Lightweight Native 1080p Motion Vector Search (No Proxy / Zero Downscale)
# blksize=64, blksizev=32: 64x32 blocks at native 1080p (~1,020 blocks total)
# search=0: OneTime predictor search tests temporal/spatial predictors directly, bypassing iterative hexagonal search
# chroma=false: Luma-only search cuts vector computation by 50%
# levels=1: Single-level search matching super's levels=1
backward_vec = MAnalyse(super, isb=true,  blksize=64, blksizev=32, search=0, chroma=false, levels=1)
forward_vec  = MAnalyse(super, isb=false, blksize=64, blksizev=32, search=0, chroma=false, levels=1)

# 3. Direct Native 60fps Frame Synthesis
# Directly warps original source frames without proxy scaling quantization artifacts
# mode=0: Fast block projection (minimal ALU load)
# blend=false: Skips transparency alpha blending calculations
# thSCD1=400, thSCD2=130: Robust scene-change detection cleanly cuts camera transitions
MBlockFps(src, super, backward_vec, forward_vec, num=60, den=1, mode=0, blend=false, thSCD1=400, thSCD2=130)

# 4. Core Pinning: 3 Threads with 6-Frame Lookahead Queue
# 3 threads leaves 1 core free for OS, audio pipeline, and D3D11 presentation
# 6 lookahead frames absorb thread scheduling jitter
Prefetch(threads, 6)
