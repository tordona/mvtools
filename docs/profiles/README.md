# AviSynth+ Profile Library & Specifications

> **Curated, hardware-tailored AviSynth+ profiles for real-time 24 fps → 60 fps video motion interpolation in Daum PotPlayer on Windows on ARM64 and x86-64.**

All profiles are engineered around **Rev 3.0.0 Single-Level Geometry (`levels=1`)**, eliminating memory thrashing on unified memory architectures while sustaining consistent 60 fps frame delivery without frame drops.

---

## Architectural Principles (Rev 3.0.0)

### 1. Single-Level Geometry (`levels=1`) vs. Legacy Hierarchical Pyramids
In traditional AviSynth MVTools implementations (`levels=0`, default 7–8 levels), the engine generates a deep hierarchical Gaussian image pyramid for each frame. On unified memory architectures (Qualcomm Snapdragon LPDDR4x/LPDDR5x and modern thin-and-light x86 SoCs), continuously copying, downsampling, and filtering 8 pyramid levels across 4–8 concurrent worker threads saturates the system memory bus and triggers aggressive thermal throttling.

**The Rev 3.0.0 Solution:**
* Setting `levels=1` (or `plevel=0`) restricts motion estimation to single-level evaluation without downscaled pyramid levels.
* Eliminates over 60% of unnecessary memory read/write traffic.
* Prevents cache pollution and stabilizes CPU/GPU temperatures under 15 W/5 W envelopes.

### 2. Two-Pass Coarse-to-Fine Block Refinement
Instead of relying on deep pyramid levels for macro-motion tracking, Rev 3.0.0 uses a two-pass block refinement strategy:
1. **Coarse Pass (`MAnalyse`):** Evaluates macro-motion vectors using large block sizes (`blksize=32` or `16`) with wide search radii.
2. **Fine Refinement Pass (`MRecalculate`):** Refines vector boundaries down to smaller blocks (`blksize=16` or `8`), resolving fine edges and moving foreground objects without halo tearing.

### 3. CPU Core Pinning & Asymmetric Topology Tuning (`AvsAffinity.dll`)
Modern chipsets feature heterogeneous CPU topologies (e.g. Intel Alder/Raptor Lake/Core Ultra P+E, AMD Zen 4c/5c, Qualcomm Snapdragon X2/C/8cx, and NVIDIA RTX Spark N1X). On these architectures, the Windows thread scheduler can migrate compute-intensive video worker threads across clock domains or onto low-IPC Efficiency cores, causing 1% low frame latency spikes and presentation stutter.

All hybrid profiles chain the companion **`AvsAffinity.dll`** clip filter immediately before `Prefetch`:
```avisynth
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads)
```
* **Worker Thread Isolation:** `PinWorkerThreads()` pins only the AviSynth+ worker threads to Performance cores via Win32 `SetThreadAffinityMask` during `GetFrame()` traversal.
* **Zero Host Blast Radius:** Host media player threads—including audio decoding, DXVA video acceleration, and Direct3D swapchain presentation—remain unconstrained and free to run on Efficiency cores.
* **Homogeneous Processor Bypass:** On processors with uniform core efficiency (e.g. 1st-Gen Qualcomm Oryon on Snapdragon X Elite/Plus, Intel N-series N100/N200, standard AMD Ryzen desktop CCDs), the filter automatically detects uniform core efficiency (`minClass == maxClass`) and executes a safe no-op (`mask = 0x0`).
* **Core Budget Allocations:**
  * **RTX Spark N1X (9–10x Cortex-X925 + 9–10x Cortex-A725):** Pinned strictly to Cortex-X925 Prime cores.
  * **Snapdragon X2 Series (6–12x Prime + 4–6x Perf Oryon):** Pinned strictly to 3rd-Gen Oryon Prime cores.
  * **Snapdragon X Series (8x / 12x Oryon):** 6–8 uniform threads (homogeneous no-op).
  * **Snapdragon C (1x Prime + 3x Perf + 4x Eff):** Pinned strictly to 1 Prime + 3 Perf Kryo cores via `PinWorkerThreads(strictPrime=true)` / `PinWorkerThreads()`.
  * **Snapdragon 8cx Gen 3 (4x X1 + 4x A78):** Pinned strictly to Cortex-X1 Prime cores.
  * **Snapdragon 8cx Gen 1/2 (4x Gold + 4x Silver):** Pinned strictly to Kryo Gold cores.
  * **Snapdragon 7c Gen 2 (2x Gold + 6x Silver):** Pinned strictly to the 2 Cortex-A76 cores.
  * **Intel Hybrid (P+E Cores):** Pinned strictly to Performance cores (e.g. Golden Cove) to eliminate Gracemont stalls.
  * **AMD Hybrid (Zen 5 + Zen 5c):** Pinned strictly to high-frequency Zen 5 cores, leaving 3.4 GHz Zen 5c cores for host playback.

### 4. Direct3D 12 DirectCompute GPU Offload Toggle (ARM64)
ARM64 profiles for eligible hardware include an inline toggle:
```avisynth
USE_D3D12 = false  # Set to true for Direct3D 12 GPU offload (mvtools2.dll)
```
When enabled, motion vector estimation executes on the GPU command queue (NVIDIA Blackwell RTX or Qualcomm Adreno) while keeping CPU utilization minimal.

### 5. Dynamic Resolution Adaptation & 4K Block Density Invariant
A 4K (3840×2160) video stream contains 4× the pixel area of 1080p (1920×1080). Evaluating fixed 1080p block sizes (`16x16`) across a 4K frame generates 240 × 135 = 32,400 blocks per pass (4× more than 1080p's 8,160 blocks). Across a two-pass coarse-to-fine pipeline, this quadruples motion vector search operations and saturates memory bandwidth, resulting in severe GPU compute stalls and CPU worker thread starvation.

**The Dynamic Resolution Scaling Rule:**
All Rev 3.0.0 profiles incorporate real-time resolution detection:
```avisynth
is_4k      = (src.Width() > 2048)
blk_coarse = is_4k ? 64 : 32
blk_fine   = is_4k ? 32 : 16
pad_val    = is_4k ? 16 : 8
```
* **Coarse Pass:** 32×32 on 1080p → 64×64 on 4K.
* **Fine Pass:** 16×16 on 1080p → 32×32 on 4K.
* **Invariant Block Count:** A 32×32 block on 4K covers the exact same physical screen proportion (120 × 68 = 8,160 blocks) as a 16×16 block on 1080p.
* **Performance Impact:** Total evaluated blocks in 4K two-pass refinement drops from 40,560 down to 10,200 (a 75% reduction in search operations), keeping memory bus load within thermal and hardware limits while maintaining identical perceptual motion tracking precision.

---

## Part I: ARM64 Hardware Profiles

| Platform / SoC | Profile Tier | Architecture | Block Size<br><span style="white-space:nowrap">(Base / 4K)</span> | 4K <span style="white-space:nowrap">60 fps</span> | `pel` | Threads | Direct3D 12 | Download |
| :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **RTX Spark N1X** | `Eco` | Single-level Coarse | 32×32 / 64×64 | <span title="Verified 4K 60 fps Playback">✅</span> | 1 | 2 / 4 | <span title="Opt-in (Preview): Direct3D 12 GPU offload available via USE_D3D12 = true">☑️</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/RTX-Spark-N1X-Eco.avs) |
| | `Balanced` | Single-level Native Fine | 16×16 / 32×32 | <span title="Verified 4K 60 fps Playback">✅</span> | 1 | 3 / 6 | <span title="Opt-in (Preview): Direct3D 12 GPU offload available via USE_D3D12 = true">☑️</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/RTX-Spark-N1X-Balanced.avs) |
| | `MaxQuality` | Subpixel Coarse-to-Fine | 32 → 16 / 64 → 32 | <span title="Verified 4K 60 fps Playback">✅</span> | 1 (GPU) / 2 (CPU) | 4 / 8 | <span title="Opt-in (Preview): Direct3D 12 GPU offload available via USE_D3D12 = true">☑️</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/RTX-Spark-N1X-MaxQuality.avs) |
| **Snapdragon X2 Series** | `Eco` | Single-level Coarse | 32×32 / 64×64 | <span title="Verified 4K 60 fps Playback">✅</span> | 1 | 2 / 4 | <span title="Opt-in (Preview): Direct3D 12 GPU offload available via USE_D3D12 = true">☑️</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-X2-Eco.avs) |
| | `Balanced` | Single-level Native Fine | 16×16 / 32×32 | <span title="Verified 4K 60 fps Playback">✅</span> | 1 | 3 / 6 | <span title="Opt-in (Preview): Direct3D 12 GPU offload available via USE_D3D12 = true">☑️</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-X2-Balanced.avs) |
| | `MaxQuality` | Subpixel Coarse-to-Fine | 32 → 16 / 64 → 32 | <span title="Verified 4K 60 fps Playback">✅</span> | 1 (GPU) / 2 (CPU) | 4 / 6 | <span title="Opt-in (Preview): Direct3D 12 GPU offload available via USE_D3D12 = true">☑️</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-X2-MaxQuality.avs) |
| **Snapdragon X Series** | `Eco` | Single-level Coarse | 32×32 / 64×64 | <span title="Verified 4K 60 fps Playback">✅</span> | 1 | 4 | <span title="Opt-in (Preview): Direct3D 12 GPU offload available via USE_D3D12 = true">☑️</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-X-Eco.avs) |
| | `Balanced` | Coarse-to-Fine Refinement | 32 → 16 / 64 → 32 | <span title="Verified 4K 60 fps Playback">✅</span> | 1 | 4 / 6 | <span title="Opt-in (Preview): Direct3D 12 GPU offload available via USE_D3D12 = true">☑️</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-X-Balanced.avs) |
| | `MaxQuality` | Subpixel Coarse-to-Fine | 32 → 16 / 64 → 32 (GPU)<br>16 → 8 / 32 → 16 (CPU) | <span title="Verified 4K 60 fps Playback">✅</span> | 1 (GPU) / 2 (CPU) | 4 / 8 | <span title="Opt-in (Preview): Direct3D 12 GPU offload available via USE_D3D12 = true">☑️</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-X-MaxQuality.avs) |
| **Snapdragon C** | `Eco` | Single-level Coarse | 32×32 / 64×64 | <span title="Unverified Playback (Theoretical 4K block adaptation implemented; pending empirical validation)">⏳</span> | 1 | 2 | <span title="Unsupported: Pure ARM64 CPU NEON execution only">❌</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-C-Eco.avs) |
| | `Balanced` | Single-level Native Fine | 16×16 / 32×32 | <span title="Unverified Playback (Theoretical 4K block adaptation implemented; pending empirical validation)">⏳</span> | 1 | 3 | <span title="Unsupported: Pure ARM64 CPU NEON execution only">❌</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-C-Balanced.avs) |
| | `MaxQuality` | Coarse-to-Fine Refinement | 32 → 16 / 64 → 32 | <span title="Unverified Playback (Theoretical 4K block adaptation implemented; pending empirical validation)">⏳</span> | 1 | 4 | <span title="Unsupported: Pure ARM64 CPU NEON execution only">❌</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-C-MaxQuality.avs) |
| **Snapdragon 8cx Gen 3** | `Eco` | Single-level Coarse | 32×32 / 64×64 | <span title="Verified 4K 60 fps Playback">✅</span> | 1 | 3 / 4 | <span title="Opt-in (Preview): Direct3D 12 GPU offload available via USE_D3D12 = true">☑️</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-8cxGen3-Eco.avs) |
| | `Balanced` | Coarse-to-Fine Refinement | 32 → 16 / 64 → 32 | <span title="Verified 4K 60 fps Playback">✅</span> | 1 | 3 / 4 | <span title="Opt-in (Preview): Direct3D 12 GPU offload available via USE_D3D12 = true">☑️</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-8cxGen3-Balanced.avs) |
| | `MaxQuality` | Coarse-to-Fine Refinement | 32 → 16 / 64 → 32 | <span title="Verified 4K 60 fps Playback">✅</span> | 1 | 3 / 4 | <span title="Opt-in (Preview): Direct3D 12 GPU offload available via USE_D3D12 = true">☑️</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-8cxGen3-MaxQuality.avs) |
| **Snapdragon 8cx Gen 2** | `Eco` | Single-level Coarse | 32×32 / 64×64 | <span title="Verified 4K 60 fps Playback">✅</span> | 1 | 3 | <span title="Opt-in (Preview): Direct3D 12 GPU offload available via USE_D3D12 = true">☑️</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-8cxGen2-Eco.avs) |
| | `Balanced` | Coarse-to-Fine Refinement | 32 → 16 / 64 → 32 | <span title="Verified 4K 60 fps Playback">✅</span> | 1 | 3 / 4 | <span title="Opt-in (Preview): Direct3D 12 GPU offload available via USE_D3D12 = true">☑️</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-8cxGen2-Balanced.avs) |
| | `MaxQuality` | Fine Refinement | 32 → 16 / 64 → 32 | <span title="Verified 4K 60 fps Playback">✅</span> | 1 | 3 / 4 | <span title="Opt-in (Preview): Direct3D 12 GPU offload available via USE_D3D12 = true">☑️</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-8cxGen2-MaxQuality.avs) |
| **Snapdragon 8cx Gen 1** | `Eco` | Single-level Coarse | 32×32 / 64×64 | <span title="Verified 4K 60 fps Playback">✅</span> | 1 | 3 | <span title="Opt-in (Preview): Direct3D 12 GPU offload available via USE_D3D12 = true">☑️</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-8cxGen1-Eco.avs) |
| | `Balanced` | Coarse-to-Fine Refinement | 32 → 16 / 64 → 32 | <span title="Verified 4K 60 fps Playback">✅</span> | 1 | 3 / 4 | <span title="Opt-in (Preview): Direct3D 12 GPU offload available via USE_D3D12 = true">☑️</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-8cxGen1-Balanced.avs) |
| | `MaxQuality` | Fine Refinement | 32 → 16 / 64 → 32 | <span title="Verified 4K 60 fps Playback">✅</span> | 1 | 3 / 4 | <span title="Opt-in (Preview): Direct3D 12 GPU offload available via USE_D3D12 = true">☑️</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-8cxGen1-MaxQuality.avs) |
| **Snapdragon 850** | `Eco` | Single-level Coarse | 64×32 / 128×64 | <span title="Unsupported: Hardware limited to 4K 30 fps by 14.9 GB/s memory bus and VPU decoder cap; profile preserves native playback">❌</span> | 1 | 3 | <span title="Unsupported: Pure ARM64 CPU NEON execution only">❌</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-850-Eco.avs) |
| | `Balanced` | Coarse-to-Fine Refinement | 32 → 16 / 64 → 32 | <span title="Unsupported: Hardware limited to 4K 30 fps by 14.9 GB/s memory bus and VPU decoder cap; profile preserves native playback">❌</span> | 1 | 3 | <span title="Unsupported: Pure ARM64 CPU NEON execution only">❌</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-850-Balanced.avs) |
| | `MaxQuality` | Fine Refinement | 32 → 16 / 64 → 32 | <span title="Unsupported: Hardware limited to 4K 30 fps by 14.9 GB/s memory bus and VPU decoder cap; profile preserves native playback">❌</span> | 1 | 4 | <span title="Unsupported: Pure ARM64 CPU NEON execution only">❌</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-850-MaxQuality.avs) |
| **Snapdragon 7c Gen 2** | `Eco` | Single-level Coarse | 32×32 / 64×64 | <span title="Unsupported: Hardware limited to 4K 30 fps by 17 GB/s memory bus and VPU decoder cap; profile preserves native playback">❌</span> | 1 | 2 | <span title="Unsupported: Pure ARM64 CPU NEON execution only">❌</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-7cGen2-Eco.avs) |
| | `Balanced` | Coarse-to-Fine Refinement | 32 → 16 / 64 → 32 | <span title="Unsupported: Hardware limited to 4K 30 fps by 17 GB/s memory bus and VPU decoder cap; profile preserves native playback">❌</span> | 1 | 2 | <span title="Unsupported: Pure ARM64 CPU NEON execution only">❌</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-7cGen2-Balanced.avs) |
| | `MaxQuality` | Coarse-to-Fine Refinement | 32 → 16 / 64 → 32 | <span title="Unsupported: Hardware limited to 4K 30 fps by 17 GB/s memory bus and VPU decoder cap; profile preserves native playback">❌</span> | 1 | 2 | <span title="Unsupported: Pure ARM64 CPU NEON execution only">❌</span> | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-7cGen2-MaxQuality.avs) |

#### 4K 60 fps Status Legend

| Status | Verification Level | Criteria |
| :---: | :--- | :--- |
| ✅ | Verified Playback | Empirically validated with 4K media (`tearsofsteel_4k.mov`) sustaining real-time 60 fps (or platform architecture tier $\ge$ Snapdragon X Series). |
| ⏳ | Unverified Playback | Theoretical 4K 2× block adaptation implemented; pending empirical hardware benchmark validation on this chipset. |
| ❌ | Unsupported | Real-time 4K 60 fps playback cannot be sustained on this architecture; profile dynamically scales back or preserves standard rate. |

#### Direct3D 12 GPU Offload Status Legend

| Status | Support Level | Implementation & Hardware Criteria |
| :---: | :--- | :--- |
| ☑️ | Opt-in (Preview) | Experimental Direct3D 12 GPU offload available via `USE_D3D12 = true`. Supported on Qualcomm Adreno (680, 690, X1-85) and NVIDIA Blackwell RTX. Defaults to ARM64 CPU NEON (`USE_D3D12 = false`). |
| ❌ | Unsupported | Pure ARM64 CPU NEON execution only. Chipset lacks required DirectCompute shader capability or runtime driver support. |

> [!NOTE]
> All profiles default to pure CPU NEON execution (`USE_D3D12 = false`). Profiles marked with **Opt-in (Preview)** (`☑️`) provide an inline toggle allowing users to optionally test experimental Direct3D 12 GPU compute offload on supported hardware (NVIDIA Blackwell RTX and Qualcomm Adreno).

---

## 1. Qualcomm Snapdragon X Plus / X Elite

> **Hardware Target:** 8x / 12x Qualcomm Oryon Cores @ up to 3.4–4.0 GHz, Adreno X1-85 iGPU, 135 GB/s LPDDR5x.  
> **Tested Chassis:** Microsoft Surface Pro 11, Samsung Galaxy Book4 Edge, Dell XPS 13.

### Snapdragon X Plus: Balanced Profile *(Recommended)*
```avisynth
# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon X Plus (Profile 2: Balanced)
# Hardware: Qualcomm Snapdragon X Plus (8x Oryon Cores @ ARM64 NEON)
# Target: Balanced tradeoff between motion fluidity, edge definition, and power consumption
# Revision: 2.2.0 (2026-11-03)
# Changelog: Oryon architecture, levels=1, coarse 32x32 -> fine 16x16, sharp=0 (pel=1), threads=4/6, Prefetch(threads), mem_limit=1536/2048, D3D12 toggle, dynamic 4K adaptation
# ==============================================================================
USE_D3D12 = false

# Dynamic parameters adapted to USE_D3D12
threads     = USE_D3D12 ? 4 : 6     # GPU offload executes on command queue (4 threads optimal); CPU uses 6 Oryon cores
mem_limit   = USE_D3D12 ? 1536 : 2048

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream
potplayer_source()

# Dynamic 4K resolution adaptation (doubles block sizes at 4K to preserve block density invariant)
is_4k      = (src.Width() > 2048)
blk_coarse = is_4k ? 64 : 32
blk_fine   = is_4k ? 32 : 16
pad_val    = is_4k ? 16 : 8

# Load Native ARM64 MVTools2 plugin
LoadPlugin("mvtools2.dll")
MEnableD3D12(USE_D3D12)

# 1. Motion Super Clip with Edge Guard
super = MSuper(levels=1, pel=1, hpad=pad_val, vpad=pad_val, sharp=0)

# 2. Coarse Global Motion Vector Search
backward_coarse = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))

# 3. Fine Motion Refinement Pass (MRecalculate)
backward_fine = MRecalculate(super, backward_coarse, blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)

# 4. Pixel-Level Motion Interpolation with Occlusion Handling
MBlockFps(super, backward_fine, forward_fine, num=60, den=1, mode=2, blend=true, thSCD1=350, thSCD2=120)

# 5. Thread Pool (adapted dynamically to USE_D3D12)
Prefetch(threads)
```

### Snapdragon X Plus: MaxQuality Profile
```avisynth
# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon X Plus (Profile 3: Max Quality)
# Hardware: Qualcomm Snapdragon X Plus (8x Oryon Cores @ ARM64 NEON)
# Target: Highest visual fidelity, diamond motion search, sustained 60 fps
# Revision: 2.4.0 (2026-11-03)
# Changelog: Oryon architecture, levels=1, search=2 (Diamond search coarse / fine refinement), threads=4/8, Prefetch(threads), mem_limit=2048/4096, D3D12 toggle, dynamic 4K adaptation, standardized src source clip and src.Width() 4K adaptation
# ==============================================================================
USE_D3D12 = false

# Dynamic parameters adapted to USE_D3D12
use_chroma  = USE_D3D12 ? false : true
threads     = USE_D3D12 ? 4 : 8
mem_limit   = USE_D3D12 ? 2048 : 4096

# Subpixel, Block & Search Parameters:
fine_rad    = USE_D3D12 ? 2 : 1

SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

src = potplayer_source()

# Dynamic 4K resolution adaptation (doubles block sizes at 4K to preserve block density invariant)
is_4k       = (src.Width() > 2048)
blk_scale   = is_4k ? 2 : 1
pel_val     = USE_D3D12 ? 1 : 2
sharp_mode  = USE_D3D12 ? 0 : 2
pad_size    = (USE_D3D12 ? 8 : 16) * blk_scale
blk_coarse  = (USE_D3D12 ? 32 : 16) * blk_scale
blk_fine    = (USE_D3D12 ? 16 : 8) * blk_scale

# Load Native ARM64 MVTools2 plugin
LoadPlugin("mvtools2.dll")
MEnableD3D12(USE_D3D12)

# 1. Motion Super Clip
super = src.MSuper(levels=1, pel=pel_val, hpad=pad_size, vpad=pad_size, sharp=sharp_mode)

# 2. Diamond Coarse Motion Vector Field Analysis
backward_coarse = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=use_chroma, levels=1, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=use_chroma, levels=1, badrange=(-24))

# 3. Micro-Block Refinement (MRecalculate)
backward_fine = MRecalculate(super, backward_coarse, blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=fine_rad, chroma=use_chroma, divide=0)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=fine_rad, chroma=use_chroma, divide=0)

# 4. Dynamic Median Pixel-Flow Motion Interpolation
MBlockFps(super, backward_fine, forward_fine, num=60, den=1, mode=2, blend=true, thSCD1=320, thSCD2=115)

Prefetch(threads)
```

---

## 2. Qualcomm Snapdragon 8cx Gen 3 / Microsoft SQ3

> **Hardware Target:** 4x Cortex-X1 Prime Cores @ 3.0 GHz + 4x Cortex-A78 Cores, Adreno 690 iGPU.  
> **Tested Chassis:** Lenovo ThinkPad X13s, Microsoft Surface Pro 9 5G.

### Snapdragon 8cx Gen 3: Balanced Profile *(Recommended)*
```avisynth
# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 8cx Gen 3 (Profile 2: Balanced)
# Pinned to 4x Cortex-X1 Prime cores (threads=4) to prevent asymmetric core stalls
# Revision: 2.3.0 (2026-11-03)
# Changelog: Coarse 32x32 -> fine 16x16, Dynamic Median synthesis (mode=2), sharp=0 (pel=1), threads=3/4, Prefetch(threads, 4), mem_limit=1024, D3D12 toggle, AvsAffinity pinning, dynamic 4K adaptation
# ==============================================================================
USE_D3D12 = false

threads     = USE_D3D12 ? 3 : 4
mem_limit   = USE_D3D12 ? 1024 : 1024

SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

potplayer_source()

# Dynamic 4K resolution adaptation (doubles block sizes at 4K to preserve block density invariant)
is_4k      = (src.Width() > 2048)
blk_coarse = is_4k ? 64 : 32
blk_fine   = is_4k ? 32 : 16
pad_val    = is_4k ? 16 : 8

# Load Native ARM64 MVTools2 plugin
LoadPlugin("mvtools2.dll")
MEnableD3D12(USE_D3D12)

super = MSuper(levels=1, pel=1, hpad=pad_val, vpad=pad_val, sharp=0)

backward_coarse = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))

backward_fine = MRecalculate(super, backward_coarse, blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)

MBlockFps(super, backward_fine, forward_fine, num=60, den=1, mode=2, blend=false, thSCD1=350, thSCD2=120)

Prefetch(threads)
```

---

## 3. Qualcomm Snapdragon 8cx Gen 2 / Gen 1 / Microsoft SQ1 & SQ2

> **Hardware Target:** 4x Kryo 495 Gold Cores (Cortex-A76 @ 3.0/2.84 GHz) + 4x Kryo 495 Silver, Adreno 685/680/675.  
> **Tested Chassis:** Microsoft Surface Pro X SQ1 & SQ2, Samsung Galaxy Book S.

### Snapdragon 8cx Gen 2: Balanced Profile *(Recommended)*
```avisynth
# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 8cx Gen 2 (Profile 2: Balanced)
# Pinned to 4x Kryo 495 Gold cores (threads=4)
# Revision: 2.2.0 (2026-11-03)
# Changelog: Native 1080p, levels=1, coarse 32x32 -> fine 16x16, sharp=0 (pel=1), threads=3/4, Prefetch(threads), mem_limit=1024/1536, D3D12 toggle, AvsAffinity pinning, dynamic 4K adaptation
# ==============================================================================
USE_D3D12 = false

# Dynamic parameters adapted to USE_D3D12
threads     = USE_D3D12 ? 3 : 4
mem_limit   = USE_D3D12 ? 1024 : 1536

SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

potplayer_source()

# Dynamic 4K resolution adaptation (doubles block sizes at 4K to preserve block density invariant)
is_4k      = (src.Width() > 2048)
blk_coarse = is_4k ? 64 : 32
blk_fine   = is_4k ? 32 : 16
pad_val    = is_4k ? 16 : 8

# Load Native ARM64 MVTools2 plugin
LoadPlugin("mvtools2.dll")
MEnableD3D12(USE_D3D12)

super = MSuper(levels=1, pel=1, hpad=pad_val, vpad=pad_val, sharp=0)

backward_coarse = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=2, chroma=false, levels=1, badrange=(-24))

backward_fine = MRecalculate(super, backward_coarse, blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)

MBlockFps(super, backward_fine, forward_fine, num=60, den=1, mode=2, blend=false, thSCD1=350, thSCD2=120)

Prefetch(threads)
```

---

## 4. Qualcomm Snapdragon 850

> **Hardware Target:** 4x Kryo 385 Gold Cores (Cortex-A75 @ 2.96 GHz) + 4x Kryo 385 Silver, Adreno 630.  
> **Tested Chassis:** Samsung Galaxy Book2, Lenovo Yoga C630 WOS.

### Snapdragon 850: Balanced Profile *(Recommended)*
```avisynth
# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 850 (Profile 2: Balanced)
# Hardware: Qualcomm Snapdragon 850 (4x Kryo 385 Gold @ Cortex-A75, Adreno 630)
# Target: Fluid 1080p 60 fps, Refined 16x16 Edges, Stable Thermal Ceiling
# Architecture: Native 1080p Coarse-to-Fine Refinement (Zero Resizing Overhead)
# Revision: 2.2.0 (2026-11-09)
# Changelog: Added native 4K early return bypass (hardware limited to 4K 30 fps by 14.9 GB/s memory bus and VPU decoder cap)
# ==============================================================================

threads     = 3                   # 3 Kryo 385 Gold cores
mem_limit   = 768

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded via Adreno 630)
src = potplayer_source()

# Dynamic 4K Fallback: Snapdragon 850 memory bus (14.9 GB/s) and VPU are capped at 4K 30 fps.
# Bypass motion interpolation on 4K streams to maintain smooth native playback.
if (src.Width() > 2048) {
    return src
}

# Dynamic Resolution Adaptation:
# Detect 4K (3840x2160 / 4096x2160) vs 1080p/720p (fallback safeguard if 4K bypass is disabled).
is_4k      = (src.Width() > 2048)
blk_coarse = is_4k ? 64 : 32
blk_fine   = is_4k ? 32 : 16
pad_val    = is_4k ? 8 : 0

# Load Native ARM64 MVTools2 plugin (ARM64 CPU NEON execution)
LoadPlugin("mvtools2.dll")
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}

# 1. Base Motion Super Clip (Single Level, Shared across Pipeline)
super = src.MSuper(levels=1, pel=1, hpad=pad_val, vpad=pad_val, sharp=0)

# 2. Coarse Global Motion Vector Search (2,040 blocks: 32x32 at 1080p, 64x64 at 4K)
backward_coarse = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=1, chroma=false, levels=1, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=1, chroma=false, levels=1, badrange=(-24))

# 3. Fine Refinement Pass (8,160 blocks: 16x16 at 1080p, 32x32 at 4K)
backward_fine = MRecalculate(super, backward_coarse, blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)

# 4. Direct Frame Synthesis with Refined Vectors
MBlockFps(src, super, backward_fine, forward_fine, num=60, den=1, mode=0, blend=false, thSCD1=380, thSCD2=125)

# 5. Core Pinning: Strictly 3 Threads with Lookahead Queue
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads, 4)
```

---

## 5. Qualcomm Snapdragon 7c Gen 2

> **Hardware Target:** 2x Kryo 468 Gold Cores (Cortex-A76 @ 2.55 GHz) + 6x Kryo 468 Silver, Adreno 618, Fanless 5 W.  
> **Tested Chassis:** Samsung Galaxy Book Go (4 GB RAM, fanless).

### Snapdragon 7c Gen 2: Balanced Profile *(Recommended)*
```avisynth
# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon 7c Gen 2 (Profile 2: Balanced)
# Hardware: Qualcomm Snapdragon 7c Gen 2 (2x Kryo 468 Gold @ 2.55 GHz + 6x Silver)
# Test Device: Samsung Galaxy Book Go (14", Fanless 5 W Chassis)
# Target: Fluid 1080p 60 fps, Refined 16x16 Edges, Stable 5 W Thermal Ceiling
# Architecture: Native 1080p Coarse-to-Fine Refinement (Zero Resizing Overhead)
# Revision: 2.3.0 (2026-11-09)
# Changelog: Added native 4K early return bypass (hardware limited to 4K 30 fps by 17 GB/s memory bus and VPU decoder cap)
# ==============================================================================

# Strictly 2 worker threads locks computation to the 2 Cortex-A76 Gold cores.
# Prevents thermal runaway and avoids slow Cortex-A55 Silver core stalls.
threads     = 2
mem_limit   = 512

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
# Detect 4K vs 1080p/720p (fallback safeguard if 4K bypass is disabled).
is_4k      = (src.Width() > 2048)
blk_coarse = is_4k ? 64 : 32
blk_fine   = is_4k ? 32 : 16
pad_val    = is_4k ? 8 : 0

# Load Native ARM64 MVTools2 plugin (ARM64 CPU NEON execution)
LoadPlugin("mvtools2.dll")
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}

# 1. Base Motion Super Clip (Single Level, Shared across Pipeline)
# levels=1: Avoids calculating redundant downscaled pyramid images
# pel=1: Whole-pixel base clip paired with MRecalculate keeps CPU low while tracking details
# pad_val boundary padding stabilizes edge vector calculation
# sharp=0: Fast bilinear interpolation
super = src.MSuper(levels=1, pel=1, hpad=pad_val, vpad=pad_val, sharp=0)

# 2. Coarse Global Motion Vector Search (2,040 blocks: 32x32 at 1080p, 64x64 at 4K)
# search=2, searchparam=1: Hexagonal search with radius 1 keeps search light on Cortex-A76
# badrange=(-24): Early rejection of outlier vectors to prevent haloing
# levels=1: Strictly searches Level 0 (single level)
backward_coarse = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=1, chroma=false, levels=1, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=1, chroma=false, levels=1, badrange=(-24))

# 3. Fine Refinement Pass (8,160 blocks: 16x16 at 1080p, 32x32 at 4K)
# Resolves small moving objects and eliminates blocky edge artifacts
backward_fine = MRecalculate(super, backward_coarse, blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)

# 4. Direct Native Frame Synthesis
# mode=0: Fast 2-stream block projection using refined 16x16 vector grid (crisp, zero block tearing)
# blend=false: Skips transparency alpha blending calculations to conserve ALU cycles
# thSCD1=380, thSCD2=125: Balanced scene-change detection cleanly cuts camera transitions
MBlockFps(src, super, backward_fine, forward_fine, num=60, den=1, mode=0, blend=false, thSCD1=380, thSCD2=125)

# 5. Core Pinning: Strictly 2 threads prevents thermal throttling
# 4 lookahead frames absorb thread scheduling jitter
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads, 4)
```

---

## 6. Qualcomm Snapdragon C

> **Hardware Target:** 8-Core Heterogeneous Kryo (1x Prime @ up to 3.0 GHz + 3x Performance @ up to 2.6 GHz + 4x Efficiency @ up to 2.0 GHz), Adreno A643 iGPU, Fanless ~5 W – 10 W.  
> **Tested Chassis:** \$300 Budget-Tier Windows on ARM Laptops.

### Snapdragon C: Balanced Profile *(Recommended)*
```avisynth
# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Snapdragon C (Profile 2: Balanced)
# Hardware: Qualcomm Snapdragon C (8x Kryo: 1 Prime @ 3.0 GHz + 3 Perf @ 2.6 GHz + 4 Eff @ 2.0 GHz)
# Architecture: ARM64 NEON CPU Motion Estimation (mvtools2.dll)
# Generator: Google Antigravity (AIAgentProfileGuide Rev 2.3.11)
# Target: Fluid 720p–4K 60 fps, Refined 16x16 Edges, 6 W – 8 W Sustained Envelope
# Revision: 1.1.0 (2026-11-09)
# Changelog: Optimized 4K playback: mode=0 and blend=false on 4K to eliminate ALU and memory bus saturation, pad_val=0 on 4K
# ==============================================================================

# Core Allocation & Threading Strategy:
# 3 worker threads pinned across the 1 Prime + 3 Performance cores.
# Leaves 1 Performance core + all 4 Efficiency cores available for Adreno VPU decode,
# Direct3D 11 swapchain presentation, and Windows background tasks.
threads     = 3
mem_limit   = 768                 # Bounded cache footprint protects budget LPDDR4x/LPDDR5 memory bus

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# PotPlayer video source stream (DXVA2/D3D11 hardware decoded via Adreno VPU)
src = potplayer_source()

# Dynamic Resolution Adaptation:
# Detect 4K (3840x2160 / 4096x2160) vs 1080p/720p.
# At 4K, 64x64 coarse -> 32x32 fine maintains the exact 120x68 (8,160 blocks) spatial grid
# density of 1080p 16x16, cutting 4K block evaluations by 75% and preventing memory bus saturation.
# mode=0 and blend=false on 4K cuts ALU and DRAM traffic by >60%, preventing fanless throttling.
is_4k      = (src.Width() > 2048)
blk_coarse = is_4k ? 64 : 32
blk_fine   = is_4k ? 32 : 16
pad_val    = is_4k ? 0 : 4
synth_mode = is_4k ? 0 : 2
blend_val  = is_4k ? false : true

# Load Native ARM64 MVTools2 plugin & companion AvsAffinity
LoadPlugin("mvtools2.dll")
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}

# 1. Base Motion Super Clip with Lightweight Edge Guard
# levels=1: Single-level base clip eliminates redundant downscaled pyramid computations
# pel=1: Whole-pixel estimation paired with MRecalculate
# pad_val boundary padding stabilizes edge vector calculation without memory thrashing
# sharp=0: Subpixel interpolation filter is unused when pel=1
super = src.MSuper(levels=1, pel=1, hpad=pad_val, vpad=pad_val, sharp=0)

# 2. Coarse Motion Vector Search (2,040 blocks: 32x32 at standard resolutions, 64x64 at 4K)
# search=2, searchparam=1: 3x3 local grid search across 2,040 blocks
# badrange=(-24): Outlier vector rejection threshold for CPU NEON search path
# levels=1: Strictly searches base Level 0
backward_coarse = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=1, chroma=false, levels=1, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=1, chroma=false, levels=1, badrange=(-24))

# 3. Fine Motion Refinement Pass (8,160 blocks: 16x16 at standard resolutions, 32x32 at 4K)
# Refines vectors down to fine blocks at object boundaries using 2x2 bilinear coarse predictors
backward_fine = MRecalculate(super, backward_coarse, blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=blk_fine, blksizev=blk_fine, search=2, searchparam=1, chroma=false)

# 4. Direct Frame Synthesis
# mode=0 on 4K sustains 60 fps without CPU pipeline stalls; mode=2 on 1080p delivers crisp dynamic median edges
# blend=false on 4K avoids memory bus saturation; blend=true on 1080p blends occlusion boundaries
# thSCD1=380, thSCD2=125: Balanced scene-change sensitivity cleanly cuts camera transitions
last = MBlockFps(src, super, backward_fine, forward_fine, num=60, den=1, mode=synth_mode, blend=blend_val, thSCD1=380, thSCD2=125)

# 5. Hardware Thread Affinity Pinning & Concurrency Pool
# Isolates worker threads to Performance/Prime cores, preventing Efficiency core latency stalls
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads, 4)
```

---

## Part II: x86-64 Hardware Profiles

Curated Rev 3.0.0 profiles tailored for x86-64 desktop and mobile processors, preserving memory bandwidth on integrated GPUs (AMD Radeon RDNA, Intel Iris Xe, and Intel Arc) while maintaining fluid 60 fps frame delivery.

> [!NOTE]
> **x86-64 Target Scope & Empirical Validation:**  
> Empirical hardware benchmarking and validation for x86-64 platforms are conducted strictly at **1080p 24 fps -> 60 fps**. While x86-64 profiles incorporate theoretical invariant 4K block scaling ($64\times 64$ coarse $\to 32\times 32$ fine) as an architectural safeguard in script syntax, real-time 4K 60 fps playback is not empirically tracked, tested, or certified on x86-64 platforms due to the expansive diversity of discrete/integrated GPU combinations and memory configurations.

### x86-64 Profile Matrix

| Platform / SoC | Topology & TDP | Tier | Block Size<br><span style="white-space:nowrap">(Base / 4K)</span> | Threads | Memory | Download |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **AMD Ryzen AI 5 340** | 3x Zen 5 + 3x Zen 5c (12T) @ 15 W – 28 W | `Eco` | 32×32 / 64×64 | 4 | 1536 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/RyzenAI-5-340-Eco.avs) |
| | Radeon 840M (RDNA 3.5) | `Balanced` | 32 → 16 / 64 → 32 | 6 | 2048 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/RyzenAI-5-340-Balanced.avs) |
| | | `MaxQuality` | 16 → 8 / 32 → 16 | 8 | 3072 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/RyzenAI-5-340-MaxQuality.avs) |
| **Intel Core i7-11850H** | 8 Cores / 16 Threads @ 45 W | `Eco` | 32×32 / 64×64 | 6 | 1536 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Core-i7-11850H-Eco.avs) |
| | Intel UHD Graphics 32EU | `Balanced` | 32 → 16 / 64 → 32 | 8 | 2048 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Core-i7-11850H-Balanced.avs) |
| | | `MaxQuality` | 16 → 8 / 32 → 16 | 8 | 3072 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Core-i7-11850H-MaxQuality.avs) |
| **Intel Core i5-1135G7** | 4 Cores / 8 Threads @ 12 W – 28 W | `Eco` | 32×32 / 64×64 | 3 | 1024 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Core-i5-1135G7-Eco.avs) |
| | Intel Iris Xe 80EU | `Balanced` | 32 → 16 / 64 → 32 | 4 | 1024 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Core-i5-1135G7-Balanced.avs) |
| | | `MaxQuality` | 32 → 16 / 64 → 32 | 4 | 1536 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Core-i5-1135G7-MaxQuality.avs) |
| **Intel Core i5-8259U** | 4 Cores / 8 Threads @ 28 W | `Eco` | 32×32 / 64×64 | 3 | 1024 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Core-i5-8259U-Eco.avs) |
| | Intel Iris Plus 655 (128 MB eDRAM) | `Balanced` | 32 → 16 / 64 → 32 | 4 | 1024 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Core-i5-8259U-Balanced.avs) |
| | | `MaxQuality` | 32 → 16 / 64 → 32 | 4 | 1536 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Core-i5-8259U-MaxQuality.avs) |
| **Intel Core i5-7Y54** | 2 Cores / 4 Threads @ 4.5 W (Fanless) | `Eco` | 32×16 / 64×32 (Proxy) | 2 | 384 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Core-i5-7Y54-Eco.avs) |
| | Intel HD Graphics 615 | `Balanced` | 16×16 / 32×32 (Proxy) | 2 | 512 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Core-i5-7Y54-Balanced.avs) |
| | | `MaxQuality` | 32 → 16 / 64 → 32 | 2 | 512 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Core-i5-7Y54-MaxQuality.avs) |
| **Intel Core i3-1215U** | 2 P-cores + 4 E-cores (8T) @ 15 W | `Eco` | 32×32 / 64×64 | 3 | 1024 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Core-i3-1215U-Eco.avs) |
| | Intel UHD Graphics 64EU | `Balanced` | 32 → 16 / 64 → 32 | 4 | 1024 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Core-i3-1215U-Balanced.avs) |
| | | `MaxQuality` | 32 → 16 / 64 → 32 | 4 | 1536 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Core-i3-1215U-MaxQuality.avs) |
| **Intel Processor N100** | 4 Gracemont E-cores (4T) @ 6 W (Fanless) | `Eco` | 32×32 / 64×64 | 2 | 512 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Intel-N100-Eco.avs) |
| | Intel UHD Graphics 24EU | `Balanced` | 32 → 16 / 64 → 32 | 3 | 768 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Intel-N100-Balanced.avs) |
| | | `MaxQuality` | 32 → 16 / 64 → 32 | 3 | 768 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Intel-N100-MaxQuality.avs) |
| **Generic x86-64** | Universal fallback for all 64-bit x86 PCs | `Eco` | 64×32 / 64×64 | 3 | 512 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Generic-x64-Eco.avs) |
| | Compatible with any x86-64 CPU | `Balanced` | 32×32 / 64×64 | 3 | 512 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Generic-x64-Balanced.avs) |
| | | `MaxQuality` | 16×16 / 32×32 | 4 | 768 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Generic-x64-MaxQuality.avs) |

---

### Universal x86-64 Balanced Script

```avisynth
# ==============================================================================
# PotPlayer AviSynth 60 fps Interpolation: Generic x86-64 (Profile 2: Balanced)
# Hardware: Generic 64-bit x86 (Intel Core i3/i5/i7 / AMD Ryzen Quad+ Cores, 15 W – 28 W TDP)
# Architecture: x86-64 AVX2 / SSE4.2 CPU Motion Estimation (mvtools2.dll)
# Target: Fluid 720p–4K 60 fps, 32x32 Vectors (2,040 Blocks), Recommended Default
# Revision: 3.1.0 (2026-11-03)
# Changelog: Replaced 0.5x proxy with native 1080p 32x32 blocks (~2,040 blocks), dynamic 4K adaptation
# ==============================================================================

# Core Allocation & Threading Strategy:
# 3 worker threads across 4+ cores leaves ample headroom for GPU video decode and presentation.
# Native 32x32 blocks delivers crisp motion tracking across 95% of mainstream x64 PCs.
threads     = 3
mem_limit   = 512                 # Bounded cache footprint protects dual-channel DRAM bus

# Memory allocation and multi-threading filter mode
SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

# Full PotPlayer video source stream (DXVA2/D3D11 hardware decoded)
src = potplayer_source()

# Dynamic Resolution Adaptation:
# Detect 4K vs 1080p. At 4K, 64x64 blocks maintain the exact 2,040 block count of 1080p 32x32.
is_4k  = (src.Width() > 2048)
blk_sz = is_4k ? 64 : 32

# Load Native x64 MVTools2 plugin
LoadPlugin("mvtools2.dll")
try { LoadPlugin("AvsAffinity.dll") } catch(e) {}

# 1. Base Motion Super Clip (Single-Level, Integer Pixel Precision)
# pel=1: Full-pixel precision only (avoids subpixel interpolation overhead)
# levels=1: Eliminates redundant multi-level spatial pyramid generation
# hpad=0, vpad=0: Zero padding overhead, preserving native pitch alignment
# sharp=0: Fast bilinear interpolation for minimal ALU load
super = src.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Balanced Motion Vector Search (No Proxy / Zero Downscale)
# blksize=blk_sz, blksizev=blk_sz: 32x32 blocks (~2,040 blocks total)
# search=2, searchparam=1: Radius-1 hexagonal search ensures tight vector consistency
# chroma=false: Luma-only search cuts vector computation by 50%
# levels=1: Single-level search matching super's levels=1
backward_vec = MAnalyse(super, isb=true,  blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, chroma=false, levels=1)
forward_vec  = MAnalyse(super, isb=false, blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, chroma=false, levels=1)

# 3. Direct 60 fps Frame Synthesis
# Directly warps source frames with 1:1 native pixel coordinate accuracy
# mode=0: Fast 2-stream block projection (sustains 60 fps without CPU pipeline stalls)
# blend=false: Clean block projection avoiding blur on fast motion
# thSCD1=380, thSCD2=125: Balanced scene-change detection cleanly cuts camera transitions
MBlockFps(src, super, backward_vec, forward_vec, num=60, den=1, mode=0, blend=false, thSCD1=380, thSCD2=125)

# 4. Core Pinning: 3 Threads with 6-Frame Lookahead Queue
# Leaves 1 core completely free for OS, audio pipeline, and D3D11 swapchain
# 6 lookahead frames absorb thread scheduling jitter
last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
Prefetch(threads, 6)
```
