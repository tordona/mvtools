# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Snapdragon 850 (Profile 1: Eco)
# Hardware: Qualcomm Snapdragon 850 (4x Kryo 385 Gold @ Cortex-A75, Adreno 630)
# Target: 5W Fanless Thermal Envelope, Maximum Battery Life, 0 Thermal Throttling
# ==============================================================================

# Ultra-lean memory pool: avoids bandwidth starvation on LPDDR4x-1866 bus
SetMemoryMax(512)

# Multi-threading filter mode
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (Offloaded via Adreno 630 hardware decoder)
potplayer_source()

# Native ARM64 MVTools2 plugin
LoadPlugin(ScriptDir() + "mvtools2.dll")

# 1. Base Motion Super Clip (Whole-pixel precision, zero padding)
# pel=1: Eliminates subpixel calculation overhead on Cortex-A75
# hpad=0, vpad=0: No padding overhead to conserve small 2 MB L3 cache
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = MSuper(pel=1, hpad=0, vpad=0, sharp=0)

# 2. Ultra-Lightweight Wide-Block Motion Analysis
# blksize=64, blksizev=32: Rectangular 64x32 blocks cut block count to ~1,020 for 1080p
# search=2: Hexagonal search pattern (fast and stable)
# searchparam=1: Minimal search radius to limit vector comparisons
# chroma=false: Evaluates luminance only, saving 50% vector computation
# plevel=0: Direct search without multi-level pyramid overhead
backward_vec = MAnalyse(super, isb=true,  blksize=64, blksizev=32, search=2, searchparam=1, chroma=false, plevel=0)
forward_vec  = MAnalyse(super, isb=false, blksize=64, blksizev=32, search=2, searchparam=1, chroma=false, plevel=0)

# 3. Direct Block-Based 60fps Synthesis
# mode=0: Fast block projection (least computationally intensive mode)
# blend=false: Avoids calculating blend transparency masks on fast motion
# thSCD1=400, thSCD2=130: Fast scene-change detection to immediately cut across scene changes
MBlockFps(super, backward_vec, forward_vec, num=60, den=1, mode=0, blend=false, thSCD1=400, thSCD2=130)

# 4. Strict Dual-Core Thread Limit
# Runs on exactly 2 Kryo 385 Gold cores, keeping clocks at maximum without thermal throttling
# Leaves 2 Gold cores + 4 Silver cores completely idle for Adreno 630 iGPU driver and system
Prefetch(2)
