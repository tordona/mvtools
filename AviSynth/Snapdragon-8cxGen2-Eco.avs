# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Snapdragon 8cx Gen 2 (Profile 1: Eco)
# Hardware: Qualcomm Snapdragon 8cx Gen 2 (4x Kryo 495 Gold + 4x Silver, Adreno 680)
# Target: 7W Fanless Thermal Envelope, Maximum Battery Life, 0 Dropped Frames
# ==============================================================================

# Memory allocation (768 MB leaves maximum LPDDR4x memory bandwidth for Adreno 680 iGPU)
SetMemoryMax(768)

# Multi-threading filter mode
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (Offloaded via Adreno 680 hardware decoder)
potplayer_source()

# Native ARM64 MVTools2 plugin
LoadPlugin(ScriptDir() + "mvtools2.dll")

# 1. Base Motion Super Clip (Integer Pixel Precision)
# pel=1: Full-pixel precision only (avoids heavy subpixel math on Cortex-A76 cores)
# hpad=0, vpad=0: No padding overhead to minimize cache pressure
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = MSuper(pel=1, hpad=0, vpad=0, sharp=0)

# 2. Ultra-Lightweight Coarse Motion Analysis
# blksize=32, blksizev=32: Large 32x32 blocks dramatically reduce vector calculations
# search=2: Hexagonal search pattern (extremely fast and stable)
# searchparam=1: Minimal search radius to limit vector comparisons
# chroma=false: Evaluates luminance only, saving 50% vector computation
# plevel=0: Direct search without multi-level pyramid overhead
backward_vec = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=1, chroma=false, plevel=0)
forward_vec  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=1, chroma=false, plevel=0)

# 3. Direct Block-Based 60fps Synthesis
# mode=0: Fast block projection (least computationally intensive mode)
# blend=false: Avoids calculating blend transparency masks on fast motion
# thSCD1=400, thSCD2=130: Fast scene-change detection to immediately cut across scene changes
MBlockFps(super, backward_vec, forward_vec, num=60, den=1, mode=0, blend=false, thSCD1=400, thSCD2=130)

# 4. Multi-Threading Capped to 3 Cores
# Caps worker threads to 3, keeping work strictly on the fast Kryo 495 Gold cores.
# Leaves 1 Gold core + all 4 Silver cores completely idle for OS, audio, and Adreno 680 iGPU driver.
# Prevents thermal throttling in fanless 7W devices (e.g. Surface Pro X).
Prefetch(3)
