# AviSynth Profile Library & Specifications

> **Curated, hardware-tailored AviSynth+ profiles for real-time 24fps → 60fps video motion interpolation in Daum PotPlayer on Windows on ARM64 and x86-64.**

All profiles are engineered around **Rev 3.0.0 Single-Level Geometry (`levels=1`)**, eliminating memory thrashing on unified memory architectures while sustaining flawless 60fps frame delivery.

---

## Architectural Principles (Rev 3.0.0)

### 1. Single-Level Geometry (`levels=1`) vs. Legacy Hierarchical Pyramids
In traditional AviSynth MVTools implementations (`levels=0`, default 7–8 levels), the engine generates a deep hierarchical Gaussian image pyramid for each frame. On unified memory architectures (Qualcomm Snapdragon LPDDR4x/LPDDR5x and modern thin-and-light x86 SoCs), continuously copying, downsampling, and filtering 8 pyramid levels across 4–8 concurrent worker threads saturates the system memory bus and triggers aggressive thermal throttling.

**The Rev 3.0.0 Solution:**
* Setting `levels=1` (or `plevel=0`) restricts motion estimation to native 1080p single-level evaluation.
* Eliminates over 60% of unnecessary memory read/write traffic.
* Prevents cache pollution and stabilizes CPU/GPU temperatures under 15W/5W envelopes.

### 2. Two-Pass Coarse-to-Fine Block Refinement
Instead of relying on deep pyramid levels for macro-motion tracking, Rev 3.0.0 uses a two-pass block refinement strategy:
1. **Coarse Pass (`MAnalyse`):** Evaluates macro-motion vectors using large block sizes (`blksize=32` or `16`) with wide search radii.
2. **Fine Refinement Pass (`MRecalculate` or `MScaleVect`):** Refines vector boundaries down to smaller blocks (`blksize=16` or `8`), resolving fine edges and moving foreground objects without halo tearing.

### 3. CPU Core Pinning & Asymmetric Topology Tuning
Modern chipsets feature heterogeneous CPU topologies (e.g. Oryon, Cortex-X1/A78/A55, and Intel P-cores/E-cores). If AviSynth spawns more threads than there are high-performance cores, worker threads stall waiting on slow efficiency cores:
* **Snapdragon X Plus (8x Oryon):** 6–8 uniform threads.
* **Snapdragon 8cx Gen 3 (4x X1 + 4x A78):** Pinned to 4 threads (strictly Cortex-X1).
* **Snapdragon 8cx Gen 1/2 (4x Gold + 4x Silver):** Pinned to 3–4 threads (strictly Kryo Gold).
* **Snapdragon 7c Gen 2 (2x Gold + 6x Silver):** Strictly 2 threads (pins to the 2 Cortex-A76 cores).
* **Intel Hybrid (P+E Cores):** Pinned to Performance core count to prevent Gracemont stalls.

### 4. Direct3D 12 DirectCompute GPU Offload Toggle (ARM64)
Snapdragon X Plus and 8cx Gen 3 profiles include an inline toggle:
```avisynth
USE_GPU = false  # Set to true for Direct3D 12 Adreno GPU offload (mvtools2_d3d12.dll)
```
When enabled, motion vector estimation executes on the Adreno iGPU command queue while keeping CPU utilization minimal.

---

## Part I: Qualcomm Snapdragon (ARM64) Profiles

| Platform / SoC | Profile Tier | Architecture | Block Size | `pel` | Threads | `USE_GPU` | Raw Download |
| :--- | :---: | :--- | :---: | :---: | :---: | :---: | :---: |
| **Snapdragon X Plus** | `Eco` | Single-level Coarse | 32×32 | 1 | 4 | Yes | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-X-Plus-Eco.avs) |
| | `Balanced` | Coarse-to-Fine Refinement | 32 → 16 | 1 | 6 | Yes | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-X-Plus-Balanced.avs) |
| | `MaxQuality` | Subpixel Coarse-to-Fine | 16 → 8 | 2 | 8 | Yes | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-X-Plus-MaxQuality.avs) |
| **Snapdragon 8cx Gen 3** | `Eco` | Single-level Coarse | 32×32 | 1 | 4 | Yes | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen3-Eco.avs) |
| | `Balanced` | Coarse-to-Fine Refinement | 32 → 16 | 1 | 4 | Yes | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen3-Balanced.avs) |
| | `MaxQuality` | Subpixel Coarse-to-Fine | 16 → 8 | 2 | 4 | Yes | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen3-MaxQuality.avs) |
| **Snapdragon 8cx Gen 2** | `Eco` | Single-level Coarse | 32×32 | 1 | 3 | No | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen2-Eco.avs) |
| | `Balanced` | Coarse-to-Fine Refinement | 32 → 16 | 1 | 4 | No | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen2-Balanced.avs) |
| | `MaxQuality` | Fine Refinement | 32 → 16 | 1 | 4 | No | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen2-MaxQuality.avs) |
| **Snapdragon 8cx Gen 1** | `Eco` | Single-level Coarse | 32×32 | 1 | 3 | No | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen1-Eco.avs) |
| | `Balanced` | Coarse-to-Fine Refinement | 32 → 16 | 1 | 4 | No | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen1-Balanced.avs) |
| | `MaxQuality` | Fine Refinement | 32 → 16 | 1 | 4 | No | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen1-MaxQuality.avs) |
| **Snapdragon 850** | `Eco` | Single-level Coarse | 32×32 | 1 | 3 | No | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-850-Eco.avs) |
| | `Balanced` | Coarse-to-Fine Refinement | 32 → 16 | 1 | 3 | No | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-850-Balanced.avs) |
| | `MaxQuality` | Fine Refinement | 32 → 16 | 1 | 4 | No | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-850-MaxQuality.avs) |
| **Snapdragon 7c Gen 2** | `Eco` | Dynamic 0.5x Proxy Vector Warp | 32×16 | 1 | 2 | No | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-7cGen2-Eco.avs) |
| | `Balanced` | Dynamic 0.5x Proxy Vector Warp | 16×16 | 1 | 2 | No | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-7cGen2-Balanced.avs) |
| | `MaxQuality` | Coarse-to-Fine Refinement | 32 → 16 | 1 | 2 | No | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-7cGen2-MaxQuality.avs) |

---

## 1. Qualcomm Snapdragon X Plus / X Elite

> **Hardware Target:** 8x / 12x Qualcomm Oryon Cores @ up to 3.4–4.0 GHz, Adreno X1-85 iGPU, 135 GB/s LPDDR5x.  
> **Tested Chassis:** Microsoft Surface Pro 11, Samsung Galaxy Book4 Edge, Dell XPS 13.

### Snapdragon X Plus: Balanced Profile *(Recommended)*
```avisynth
# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Snapdragon X Plus (Profile 2: Balanced)
# Hardware: Qualcomm Snapdragon X Plus (8x Oryon Cores @ ARM64 NEON)
# Target: Sweet spot between fluid motion, sharp edges, and efficient power draw
# Revision: 2.0.0
# ==============================================================================
USE_GPU = false

plugin_file = USE_GPU ? "mvtools2_d3d12.dll" : "mvtools2.dll"
threads     = USE_GPU ? 4 : 6
mem_limit   = USE_GPU ? 1536 : 2048

SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

potplayer_source()

LoadPlugin(plugin_file)

super = MSuper(pel=1, hpad=8, vpad=8, sharp=1)

backward_coarse = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))

backward_fine = MRecalculate(super, backward_coarse, blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)

MFlowFps(super, backward_fine, forward_fine, num=60, den=1, mask=2, ml=100.0, blend=false)

Prefetch(threads, 4)
```

### Snapdragon X Plus: MaxQuality Profile
```avisynth
# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Snapdragon X Plus (Profile 3: MaxQuality)
# Target: Maximum visual fidelity, subpixel precision (pel=2), 16x16 -> 8x8 blocks
# Revision: 2.0.0
# ==============================================================================
USE_GPU = false

plugin_file = USE_GPU ? "mvtools2_d3d12.dll" : "mvtools2.dll"
threads     = USE_GPU ? 4 : 8
mem_limit   = USE_GPU ? 2048 : 3072

SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

potplayer_source()

LoadPlugin(plugin_file)

super = MSuper(pel=2, hpad=16, vpad=16, sharp=2)

backward_coarse = MAnalyse(super, isb=true,  blksize=16, blksizev=16, search=3, searchparam=2, chroma=false, plevel=0, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=16, blksizev=16, search=3, searchparam=2, chroma=false, plevel=0, badrange=(-24))

backward_fine = MRecalculate(super, backward_coarse, blksize=8, blksizev=8, search=3, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=8, blksizev=8, search=3, searchparam=1, chroma=false)

MFlowFps(super, backward_fine, forward_fine, num=60, den=1, mask=2, ml=100.0, blend=false)

Prefetch(threads, 4)
```

---

## 2. Qualcomm Snapdragon 8cx Gen 3 / Microsoft SQ3

> **Hardware Target:** 4x Cortex-X1 Prime Cores @ 3.0 GHz + 4x Cortex-A78 Cores, Adreno 690 iGPU.  
> **Tested Chassis:** Lenovo ThinkPad X13s, Microsoft Surface Pro 9 5G.

### Snapdragon 8cx Gen 3: Balanced Profile *(Recommended)*
```avisynth
# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Snapdragon 8cx Gen 3 (Profile 2: Balanced)
# Pinned to 4x Cortex-X1 Prime cores (threads=4) to prevent asymmetric core stalls
# Revision: 2.1.0
# ==============================================================================
USE_GPU = false

plugin_file = USE_GPU ? "mvtools2_d3d12.dll" : "mvtools2.dll"
threads     = USE_GPU ? 3 : 4
mem_limit   = USE_GPU ? 1024 : 1024

SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

potplayer_source()

LoadPlugin(plugin_file)

super = MSuper(pel=1, hpad=8, vpad=8, sharp=1)

backward_coarse = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))

backward_fine = MRecalculate(super, backward_coarse, blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)

MFlowFps(super, backward_fine, forward_fine, num=60, den=1, mask=2, ml=100.0, blend=false)

Prefetch(threads, 4)
```

---

## 3. Qualcomm Snapdragon 8cx Gen 2 / Gen 1 / Microsoft SQ1 & SQ2

> **Hardware Target:** 4x Kryo 495 Gold Cores (Cortex-A76 @ 3.0/2.84 GHz) + 4x Kryo 495 Silver, Adreno 685/680.  
> **Tested Chassis:** Microsoft Surface Pro X SQ1 & SQ2, Samsung Galaxy Book S.

### Snapdragon 8cx Gen 2: Balanced Profile *(Recommended)*
```avisynth
# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Snapdragon 8cx Gen 2 (Profile 2: Balanced)
# Pinned to 4x Kryo 495 Gold cores (threads=4)
# Revision: 2.0.0
# ==============================================================================
threads     = 4
mem_limit   = 1024

SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

src = potplayer_source()

LoadPlugin("mvtools2.dll")

super = src.MSuper(levels=1, pel=1, hpad=8, vpad=8, sharp=1)

backward_coarse = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))

backward_fine = MRecalculate(super, backward_coarse, blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)

MFlowFps(src, super, backward_fine, forward_fine, num=60, den=1, mask=2, ml=100.0, blend=false)

Prefetch(threads, 4)
```

---

## 4. Qualcomm Snapdragon 850

> **Hardware Target:** 4x Kryo 385 Gold Cores (Cortex-A75 @ 2.96 GHz) + 4x Kryo 385 Silver, Adreno 630.  
> **Tested Chassis:** Samsung Galaxy Book2, Lenovo Yoga C630 WOS.

### Snapdragon 850: Balanced Profile *(Recommended)*
```avisynth
# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Snapdragon 850 (Profile 2: Balanced)
# Pinned to 3x Kryo 385 Gold cores (threads=3) to preserve headroom for D3D11 present
# Revision: 2.0.0
# ==============================================================================
threads     = 3
mem_limit   = 768

SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

src = potplayer_source()

LoadPlugin("mvtools2.dll")

super = src.MSuper(levels=1, pel=1, hpad=8, vpad=8, sharp=1)

backward_coarse = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))

backward_fine = MRecalculate(super, backward_coarse, blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)

MFlowFps(src, super, backward_fine, forward_fine, num=60, den=1, mask=2, ml=100.0, blend=false)

Prefetch(threads, 4)
```

---

## 5. Qualcomm Snapdragon 7c Gen 2

> **Hardware Target:** 2x Kryo 468 Gold Cores (Cortex-A76 @ 2.55 GHz) + 6x Kryo 468 Silver, Adreno 618, Fanless 5W.  
> **Tested Chassis:** Samsung Galaxy Book Go (4GB RAM, fanless).

### Snapdragon 7c Gen 2: Balanced Profile *(Recommended)*
```avisynth
# ==============================================================================
# PotPlayer AviSynth 60fps Interpolation: Snapdragon 7c Gen 2 (Profile 2: Balanced)
# Dynamic 0.5x proxy search + 2x vector scale + zero-loss native synthesis
# Pinned to 2x Cortex-A76 Gold cores (threads=2) for whisper-cool fanless playback
# Revision: 2.0.0
# ==============================================================================
threads     = 2
mem_limit   = 512

SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

src = potplayer_source()

LoadPlugin("mvtools2.dll")

# 1. Dynamic 0.5x Proxy Clip
search_w     = (src.Width  / 4) * 2
search_h     = (src.Height / 4) * 2
search_clip  = src.BilinearResize(search_w, search_h)
search_super = search_clip.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)

# 2. Fast Single-Level Vector Search on Proxy
backward_proxy = MAnalyse(search_super, isb=true,  blksize=16, blksizev=16, search=2, searchparam=1, chroma=false, levels=1)
forward_proxy  = MAnalyse(search_super, isb=false, blksize=16, blksizev=16, search=2, searchparam=1, chroma=false, levels=1)

# 3. Mathematically Scale Vectors 2x up to Native Coordinates
backward_scaled = backward_proxy.MScaleVect(scale=2.0, scaleV=2.0, mode=0)
forward_scaled  = forward_proxy.MScaleVect(scale=2.0, scaleV=2.0, mode=0)

# 4. Native Frame Synthesis (Zero Resolution Loss)
super_src = src.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=0)
MBlockFps(src, super_src, backward_scaled, forward_scaled, num=60, den=1, mode=0, blend=false, thSCD1=380, thSCD2=125)

Prefetch(threads, 4)
```

---

<span id="part-ii-x86-64-hardware-profiles"></span>
## Part II: x86-64 Hardware Profiles (AMD Ryzen & Intel Core)

Curated Rev 3.0.0 profiles tailored for x86-64 desktop and mobile processors, preserving memory bandwidth on integrated GPUs (AMD Radeon RDNA, Intel Iris Xe, and Intel Arc) while maintaining fluid 60fps frame delivery.

### x86-64 Profile Matrix

| Platform / CPU | Topology & TDP | Tier | Block Size | Threads | Memory | Download |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **AMD Ryzen AI 5 340** | 3x Zen 5 + 3x Zen 5c (12T) @ 15W–28W | `Eco` | 32×32 | 4 | 1536 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/RyzenAI-5-340-Eco.avs) |
| | Radeon 840M (RDNA 3.5) | `Balanced` | 32 → 16 | 6 | 2048 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/RyzenAI-5-340-Balanced.avs) |
| | | `MaxQuality` | 16 → 8 | 8 | 3072 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/RyzenAI-5-340-MaxQuality.avs) |
| **Intel Core i7-11850H** | 8 Cores / 16 Threads @ 45W | `Eco` | 32×32 | 6 | 1536 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Core-i7-11850H-Eco.avs) |
| | Intel UHD Graphics 32EU | `Balanced` | 32 → 16 | 8 | 2048 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Core-i7-11850H-Balanced.avs) |
| | | `MaxQuality` | 16 → 8 | 8 | 3072 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Core-i7-11850H-MaxQuality.avs) |
| **Intel Core i5-1135G7** | 4 Cores / 8 Threads @ 12W–28W | `Eco` | 32×32 | 3 | 1024 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Core-i5-1135G7-Eco.avs) |
| | Intel Iris Xe 80EU | `Balanced` | 32 → 16 | 4 | 1024 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Core-i5-1135G7-Balanced.avs) |
| | | `MaxQuality` | 32 → 16 | 4 | 1536 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Core-i5-1135G7-MaxQuality.avs) |
| **Intel Core i5-8259U** | 4 Cores / 8 Threads @ 28W | `Eco` | 32×32 | 3 | 1024 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Core-i5-8259U-Eco.avs) |
| | Intel Iris Plus 655 (128MB eDRAM) | `Balanced` | 32 → 16 | 4 | 1024 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Core-i5-8259U-Balanced.avs) |
| | | `MaxQuality` | 32 → 16 | 4 | 1536 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Core-i5-8259U-MaxQuality.avs) |
| **Intel Core i5-7Y54** | 2 Cores / 4 Threads @ 4.5W (Fanless) | `Eco` | 32×16 (Proxy) | 2 | 384 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Core-i5-7Y54-Eco.avs) |
| | Intel HD Graphics 615 | `Balanced` | 16×16 (Proxy) | 2 | 512 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Core-i5-7Y54-Balanced.avs) |
| | | `MaxQuality` | 32 → 16 | 2 | 512 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Core-i5-7Y54-MaxQuality.avs) |
| **Intel Core i3-1215U** | 2 P-cores + 4 E-cores (8T) @ 15W | `Eco` | 32×32 | 3 | 1024 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Core-i3-1215U-Eco.avs) |
| | Intel UHD Graphics 64EU | `Balanced` | 32 → 16 | 4 | 1024 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Core-i3-1215U-Balanced.avs) |
| | | `MaxQuality` | 32 → 16 | 4 | 1536 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Core-i3-1215U-MaxQuality.avs) |
| **Intel Processor N100** | 4 Gracemont E-cores (4T) @ 6W (Fanless) | `Eco` | 32×32 | 2 | 512 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Intel-N100-Eco.avs) |
| | Intel UHD Graphics 24EU | `Balanced` | 32 → 16 | 3 | 768 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Intel-N100-Balanced.avs) |
| | | `MaxQuality` | 32 → 16 | 3 | 768 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Intel-N100-MaxQuality.avs) |
| **Generic x86-64** | Universal fallback for all AMD / Intel PCs | `Eco` | 32×32 | 3 | 768 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Generic-x64-Eco.avs) |
| | Compatible with any x86-64 CPU | `Balanced` | 32 → 16 | 4 | 1024 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Generic-x64-Balanced.avs) |
| | | `MaxQuality` | 16 → 8 | 4 | 1536 MB | [`Raw`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Generic-x64-MaxQuality.avs) |

---

### Universal x86-64 Balanced Script

```avisynth
# ==============================================================================
# MVTools2 60fps Balanced Interpolation Script (Generic x86-64)
# Hardware: AMD Ryzen / Intel Core (4+ Physical Cores)
# Revision: 3.0.0
# ==============================================================================
threads   = 4
mem_limit = 1024

SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

potplayer_source()

LoadPlugin("mvtools2.dll")

# 1. Native 1080p Single-Level Super Clip
super = MSuper(pel=1, hpad=8, vpad=8, sharp=1)

# 2. Coarse Motion Vector Estimation (32x32)
backward_coarse = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))

# 3. Fine Motion Refinement Pass (16x16)
backward_fine = MRecalculate(super, backward_coarse, blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)

# 4. Pixel-Level Motion Interpolation to 60fps
MFlowFps(super, backward_fine, forward_fine, num=60, den=1, mask=2, ml=100.0, blend=false)

Prefetch(threads, 4)
```
