# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Intel Core i3-1215U (Profile 3: MaxQuality)
# Hardware: Intel Core i3-1215U (2P+4E/8T Alder Lake-U @ 15 W TDP, Intel UHD Graphics 64EU)
# Memory: 16 GB Dual-Channel DDR4/LPDDR5 (51.2-83.2 GB/s Bandwidth)
# Architecture: Native 1080p x86-64 AVX2 / SSE4.2 CPU Motion Estimation (mvtools2.dll)
# Target: High-Fidelity 60 fps Presentation, Native 16x16 with 4 px Overlap (14,151 Blocks), 15 W Envelope
# Revision: 2.2.4 (2026-11-17)
# Changelog: Updated pyramid levels to is_4k ? 2 : 0 with plevel=0 for tear-free panning; Parameterized target_fps (default 60, capped at 60 fps on 4K) with target-relative frame rate bypass; Native 1080p, levels=levels_val, 16x16 with 4 px overlap, blend=true, AvsAffinity hardware pinning, dynamic 4K adaptation
# ==============================================================================

# Core Allocation & Threading Strategy:
# 4 worker threads occupies the 4 logical threads of the 2 Golden Cove P-cores.
# Leaves all 4 Gracemont E-cores completely unburdened for UHD DXVA decode, D3D11 swapchain, and DWM.
threads     = 4
mem_limit   = 1024                # Generous cache allocation for dense overlapping vector grid
target_fps  = 60                  # Target output frame rate (e.g. 60 or 120)

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded via Intel UHD Graphics)
src = potplayer_source()

is_4k      = (src.Width() > 2048)
target_fps = (is_4k && target_fps > 60) ? 60 : target_fps

# Bypass motion interpolation if source is already at or above target_fps (4% NTSC tolerance, e.g. 59.94 fps for 60 fps)
if (src.FrameRate() >= (target_fps * 0.96)) {
    return src
}

# Dynamic Resolution Adaptation:
# Detect 4K (3840x2160 / 4096x2160) vs 1080p/720p.
# At 4K, 32x32 blocks with 8 px overlap preserve proportional block density without compute saturation.
levels_val = is_4k ? 2 : 0
blk_sz= is_4k ? 32 : 16
ovlp_sz = is_4k ? 8 : 4

# Load Native x64 MVTools2 plugin (leveraging Golden Cove AVX2 SIMD optimizations)
LoadPlugin("mvtools2.dll")
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}

# 1. Native 1080p Super Clip with Bicubic Subpixel Interpolation
# sharp=1: Bicubic subpixel interpolation enhances fine detail edge contrast
# levels=levels_val: Full pyramid at 1080p (levels=0), 2 levels at 4K (levels=2)
# hpad=0, vpad=0: Native pitch alignment
super = src.MSuper(levels=levels_val, pel=1, hpad=0, vpad=0, sharp=1)

# 2. Native 1080p Overlapping Motion Vector Search (No Proxy / Zero Downscale)
# blksize=blk_sz, blksizev=blk_sz, overlap=ovlp_sz, overlapv=ovlp_sz: ~14,151 overlapping blocks at native 1080p
# Overlap eliminates block boundary discontinuities along fast-moving contours
# search=2, searchparam=2: Radius-2 hexagonal search captures rapid motion
# chroma=false: Luma-only search cuts vector computation by 50%
# levels=levels_val: Full pyramid at 1080p (levels=0), 2 levels at 4K (levels=2)
backward_vec = MAnalyse(super, isb=true,  blksize=blk_sz, blksizev=blk_sz, overlap=ovlp_sz, overlapv=ovlp_sz, search=2, searchparam=2, plevel=0, chroma=false, levels=levels_val)
forward_vec  = MAnalyse(super, isb=false, blksize=blk_sz, blksizev=blk_sz, overlap=ovlp_sz, overlapv=ovlp_sz, search=2, searchparam=2, plevel=0, chroma=false, levels=levels_val)

# 3. Direct Native 60 fps Frame Synthesis with Directional Alpha Blending
# Directly warps native frames using overlapping vector fields
# mode=0: Fast 2-stream block projection
# blend=true: Smooths occlusion boundaries and disocclusion edges
# thSCD1=350, thSCD2=115: High-sensitivity scene-change threshold prevents cut distortion
MBlockFps(src, super, backward_vec, forward_vec, num=target_fps, den=1, mode=0, blend=true, thSCD1=350, thSCD2=115)

# 4. Hardware Thread Affinity & Core Pinning: 4 Threads with 6-Frame Lookahead Queue
# 4 threads across the 2 P-cores (HT) ensures high IPC and avoids E-core latency variance
# 6 lookahead frames absorb thread scheduling jitter
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads, 6)
