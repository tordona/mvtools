# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 8cx Gen 1 (Profile 3: Max Quality)
# Hardware: Qualcomm Snapdragon 8cx Gen 1 / Microsoft SQ1 (4x Kryo 495 Gold + 4x Silver, Adreno 675)
# Target: Highest Achievable Quality within 8cx Thermal Ceiling
# Revision: 2.4.0 (2026-11-09)
# Changelog: Optimized 4K CPU scaling to invariant 64x64 coarse -> 32x32 fine (8,160 blocks), pel=1/sharp=0 and blend=false on 4K, normalized 4K mem_limit=1280 to eliminate page swapping
# ==============================================================================

# ------------------------------------------------------------------------------
# User Configuration: Toggle Direct3D 12 Compute Offload
# Set to true for Direct3D 12 Adreno GPU offload (via MEnableD3D12 in mvtools2.dll)
# Set to false for original ARM64 CPU NEON baseline (mvtools2.dll)
# ------------------------------------------------------------------------------
USE_D3D12 = false

# PotPlayer video source stream (Offloaded via Adreno 675 hardware decoder)
src = potplayer_source()

# Dynamic Resolution Adaptation:
# Detect 4K (3840x2160 / 4096x2160) vs 1080p/720p.
# At 4K, blocks scale by 2x to maintain the exact 8,160 block count invariant (64x64 coarse -> 32x32 fine)
# and avoid cache/bus thrashing. pel=1 and blend=false on 4K save ALU cycles and eliminate pagefile swapping.
is_4k       = (src.Width() > 2048)
threads     = USE_D3D12 ? 3 : 4     # GPU: 3 threads keeps queue full; CPU: 4 Gold cores
mem_limit   = USE_D3D12 ? 1024 : (is_4k ? 1280 : 1536)

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Dynamic parameter adaptation:
# GPU DirectCompute: pel=1, single-pass dense blocks with search=2 (Diamond search in 2 dispatches prevents 7 W thermal throttling)
# CPU NEON: pel=2 on 1080p, pel=1 on 4K; 16x16 -> 8x8 on 1080p, 64x64 -> 32x32 on 4K
pel_val     = (is_4k || USE_D3D12) ? 1 : 2
sharp_mode  = (is_4k || USE_D3D12) ? 0 : 1
blend_mode  = is_4k ? false : true
blk_dense   = is_4k ? 64 : 16
blk_refine  = is_4k ? 32 : 8
pad_val     = is_4k ? 16 : 8
search_rad  = is_4k ? 1 : 2
search_alg  = 2

# Load Native ARM64 MVTools2 plugin
LoadPlugin("mvtools2.dll")
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}
MEnableD3D12(USE_D3D12)

# 1. Motion Super Clip
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=pel_val: Dynamic based on USE_D3D12 and resolution (pel=1 on 4K and GPU; pel=2 on 1080p CPU)
# pad_val boundary padding stabilizes edge vector calculation
# sharp=sharp_mode: Bicubic filtering when pel=2 on 1080p CPU; unused when pel=1
super = src.MSuper(levels=1, pel=pel_val, hpad=pad_val, vpad=pad_val, sharp=sharp_mode)

# 2. Dense Motion Vector Field Analysis
# GPU: Evaluates in a single pass of dense blocks (16x16 at 1080p, 32x32 at 4K: 8,160 blocks) using Diamond search (~12 points)
# CPU: Radius-1 (4K) or Radius-2 (1080p) coarse pass before micro-block refinement
# levels=1: Strictly searches base Level 0
backward_dense = MAnalyse(super, isb=true,  blksize=blk_dense, blksizev=blk_dense, search=search_alg, searchparam=search_rad, chroma=false, levels=1, badrange=(-24))
forward_dense  = MAnalyse(super, isb=false, blksize=blk_dense, blksizev=blk_dense, search=search_alg, searchparam=search_rad, chroma=false, levels=1, badrange=(-24))

# 3. Motion Vector Refinement (CPU only)
# GPU skips MRecalculate to stay within the 7 W thermal envelope; CPU executes micro-block refinement (8,160 blocks)
backward_vec = USE_D3D12 ? backward_dense : MRecalculate(super, backward_dense, blksize=blk_refine, blksizev=blk_refine, search=2, searchparam=1, chroma=false, divide=0)
forward_vec  = USE_D3D12 ? forward_dense  : MRecalculate(super, forward_dense,  blksize=blk_refine, blksizev=blk_refine, search=2, searchparam=1, chroma=false, divide=0)

# 4. Dynamic Median Pixel-Flow Motion Interpolation
# mode=2: Dynamic Median pixel-flow synthesis
# blend=blend_mode: Scene-change fallback blending (disabled on 4K to conserve ALU bandwidth)
# thSCD1=320, thSCD2=115: Strict scene-change detection to prevent cross-cut morphing
MBlockFps(super, backward_vec, forward_vec, num=60, den=1, mode=2, blend=blend_mode, thSCD1=320, thSCD2=115)

# 5. Core Pinning: 3 threads keeps presentation queue full without mutex starvation
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads)

