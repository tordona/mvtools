# PotPlayer & AviSynth+ 60 fps Configuration Guide: Snapdragon X2 Series (X2 Elite Extreme / X2 Elite / X2 Plus)

> **Hardware Target:** Qualcomm Snapdragon X2 Elite Extreme (`X2E-96-100`, `X2E-94-100`), X2 Elite (`X2E-90-100`, `X2E-88-100`, `X2E-84-100`, `X2E-80-100`, `X2E-78-100`), X2 Plus (`X2P-64-100`, `X2P-42-100`)  
> **Integrated GPU:** Qualcomm Adreno X2-90 / X2-85 / X2-45 (Sliced Architecture @ up to 1.85 GHz)  
> **CPU Topology:** 3rd-Gen Qualcomm Oryon Hybrid Architecture — 6x to 12x Prime Cores (@ up to 4.4 GHz all-core / 5.0 GHz boost) + 4x to 6x Performance Cores (@ 3.4 GHz – 3.6 GHz)  
> **Cache & Memory Subsystem:** 22 MB – 53 MB Total Cache; 128-bit / 192-bit LPDDR5x-9523 (152 GB/s – 228 GB/s Unified Bandwidth)  
> **Thermal Profile:** 15 W – 45 W Configurable Package Envelope

---

## Overview & Thermal Strategy

The **Qualcomm Snapdragon X2** series (fabricated on a 3 nm process node) transitions from the homogeneous core layout of first-generation Snapdragon X processors to a **heterogeneous hybrid 3rd-Gen Oryon architecture** combining high-clock **Prime** cores with power-optimized **Performance** cores:

| SoC Tier & SKU | CPU Core Topology | Prime / Performance Clocks | Total Cache | Integrated GPU | Memory Bus & Bandwidth |
| :--- | :--- | :--- | :---: | :--- | :--- |
| **X2 Elite Extreme**<br>(`X2E-96-100`, `X2E-94-100`) | 18 Cores (12 Prime + 6 Perf) | Up to 4.4 GHz all-core (5.0 GHz boost) / 3.6 GHz | 53 MB | Adreno X2-90 (1.85 GHz) | 192-bit LPDDR5x-9523 (**228 GB/s**) |
| **X2 Elite (18-Core)**<br>(`X2E-90-100`, `X2E-88-100`) | 18 Cores (12 Prime + 6 Perf) | Up to 4.0 GHz all-core (4.7 GHz boost) / 3.4 GHz | 53 MB | Adreno X2-90 / X2-85 (1.70 GHz) | 128-bit LPDDR5x-9523 (**152 GB/s**) |
| **X2 Elite (12-Core)**<br>(`X2E-84-100`, `X2E-80-100`, `X2E-78-100`) | 12 Cores (6 Prime + 6 Perf) | Up to 4.0 GHz all-core (4.7 GHz boost) / 3.4 GHz | 34 MB | Adreno X2-85 (1.35 GHz – 1.70 GHz) | 128-bit LPDDR5x-9523 (**152 GB/s**) |
| **X2 Plus (10-Core / 6-Core)**<br>(`X2P-64-100`, `X2P-42-100`) | 10 Cores (6 Prime + 4 Perf)<br>6 Cores (6 Prime) | Up to 4.0 GHz / 3.4 GHz | 34 MB / 22 MB | Adreno X2-45 (0.91 GHz – 1.70 GHz) | 128-bit LPDDR5x-9523 (**152 GB/s**) |

1. **Heterogeneous 3rd-Gen Oryon Topology & Prime-Core Pinning:** Because Snapdragon X2 pairs 4.0 GHz – 5.0 GHz Prime cores with 3.4 GHz – 3.6 GHz Performance cores, unpinned AviSynth+ worker threads can be migrated by the OS scheduler across clock domains during frame evaluation, inducing barrier synchronization jitter. All Snapdragon X2 profiles load `AvsAffinity.dll` (`PinWorkerThreads()`) to confine MVTools2 worker threads strictly to the Oryon Prime core cluster while leaving the Performance cores dedicated to DXVA2/D3D11 hardware video decoding, audio rendering, and DWM swapchain presentation.
2. **Universal 6-Thread Prime Budget:** Every 10-core, 12-core, and 18-core Snapdragon X2 SKU includes **at least 6 Prime cores**. Budgeting `threads = 6` on the **Balanced** and **MaxQuality** CPU tiers maps 1:1 onto the 6-core Prime cluster of 10-core/12-core systems and utilizes half of the 12-core Prime cluster on 18-core systems, guaranteeing zero spillage onto slower secondary cores across the entire product line.
3. **Thermal Budget Preservation via Adreno X2 VPU:** Offloading AV1, 10-bit HEVC, H.264, and VP9 decoding to the dedicated Adreno X2 Video Processing Unit (VPU) via D3D11 Copy-Back keeps CPU decode overhead at 0%, reserving thermal headroom for motion vector search and frame synthesis.
4. **Expanded Unified Memory Bandwidth (152 GB/s – 228 GB/s):** The LPDDR5x-9523 memory subsystem and 22 MB – 53 MB cache hierarchy sustain half-pixel 6-tap Wiener interpolation (`pel=2, sharp=2`) on the native ARM64 NEON path as well as Direct3D 12 compute shader ring buffers without memory bus saturation.
5. **Thermal Profile Scaling:**
   - **Eco (5 W – 8 W):** `threads = USE_D3D12 ? 2 : 4`, `Prefetch(threads, 4)` keeps package power minimal for silent battery playback.
   - **Balanced (12 W – 18 W):** `threads = USE_D3D12 ? 3 : 6`, `Prefetch(threads, 6)` evaluates native 16x16 vectors (`8,160` blocks) entirely within the Prime core cluster.
   - **MaxQuality (20 W – 35 W):** `threads = USE_D3D12 ? 4 : 6`, `Prefetch(threads, 8)` enables coarse-to-fine `MRecalculate` refinement with CPU half-pel Wiener filtering (`pel=2, sharp=2`) or GPU Dynamic Median synthesis (`mode=2`).

---

## Step 1: Hardware Video Decoder Configuration (Adreno X2 VPU)

The Adreno X2 Video Processing Unit (VPU) includes dedicated hardware decode engines for AV1, HEVC, H.264, and VP9.

1. Open **PotPlayer** and press **`F5`** to open **Preferences**.
2. In the left navigation tree, navigate to:  
   **Filter Control** → **Video Decoder**.
3. Click the **Built-in Video Codec/DXVA Settings** button.
4. Configure the following options:
   - Check **Use DXVA** at the top.
   - Under **Hardware acceleration (DXVA) settings**:
     - Set **DXVA2 Copy-Back:** to **`D3D11`** (or **`Auto (Recommended)`**).
     - Set **Resolution limit:** to **`Always use`**.
     - Verify individual codec dropdowns are set to their default built-in decoders:
       - **AV1:** `Built-in FFmpeg Decoder (Recommended)` *(Adreno X2 hardware accelerated)*
       - **H.265/HEVC:** `Built-in FFmpeg Decoder (Recommended)`
       - **H.264/AVC1:** `Built-in FFmpeg Decoder (Recommended)`
       - **VP9:** `Built-in FFmpeg Decoder (Recommended)`
5. Click **Apply**.

> [!IMPORTANT]
> **Why D3D11 / Copy-Back?**  
> AviSynth+ filters receive video input through `potplayer_source()`. D3D11 Copy-Back decodes video inside the Adreno X2 hardware VPU and maps the uncompressed frames into unified LPDDR5x memory, reducing CPU decode overhead down to **0%**.

---

## Step 2: Video Renderer Configuration (Adreno X2 Direct3D 11 Pipeline)

1. In **Preferences (`F5`)**, navigate to the main **Video** page *(do NOT use the sub-page Video → Resize)*.
2. Set **Video Renderer** to:
   - **`Built-in Direct3D 11 Video Renderer`** *(Recommended)*
3. **GPU Scaling Algorithm:**
   - Under **Video Output Settings**, directly below **Direct3D Presentation**, locate the **`Resizer:`** dropdown.
   - Select **`Shader Bicubic(A = -0.6)`** *(Recommended for balanced performance)* or **`Shader(2-Pass) Lanczos 2`** *(Max Quality)*.  
   *(The Adreno X2 shader array executes scaling and presentation shaders with negligible power draw).*
4. Click **Apply**.

---

## Step 3: Colorspace Pass-Through (Zero CPU Copying)

1. In **Preferences (`F5`)**, navigate to:  
   **Video** → **Colorspaces**.
2. Under **Supported Colorspaces / YCbCr <-> RGB conversion**, set **Output color space** to **`Auto (Recommended)`** (or native planar YUV: **`NV12`** / **`YV12`**). Do **NOT** select `RGB 32` or `ARGB 32` *(prevents CPU color space conversion stalls)*.
3. Verify that **High quality YUY2/RGB24/32 conversion** is **Unchecked**.
4. In the format list, verify preferred formats are set to native planar YUV:
   - **`NV12`**
   - **`YV12`**

---

## Step 4: AviSynth+ Processing & Script Profile Selection

1. In **Preferences (`F5`)**, navigate to:  
   **Video** → **AviSynth**.
2. Check **Enable AviSynth processing**.
3. Check **Add "potplayer_source()"**.
4. Check **Buffer (back/ahead)** and configure buffer limits:
   - **Buffer Back** (first box): Set to **`12`** to **`16`** frames.
   - **Buffer Ahead** (second box): Set to **`24`** to **`30`** frames.
5. Under **Load script:**, select your desired Snapdragon X2 script:
   - **Profile 1 (Eco / Battery Saver):** [`Snapdragon-X2-Eco.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-X2-Eco.avs)
   - **Profile 2 (Balanced / Daily Driver):** [`Snapdragon-X2-Balanced.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-X2-Balanced.avs) *(Recommended)*
   - **Profile 3 (Max Quality / Fine Grid):** [`Snapdragon-X2-MaxQuality.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-X2-MaxQuality.avs)
6. Click **Apply** → **OK**.

> [!TIP]
> **Direct3D 12 GPU Offload (`USE_D3D12 = true` — Experimental Preview)**  
> All Snapdragon X2 profiles default to `USE_D3D12 = false` so the 3rd-Gen Oryon Prime cores execute the production ARM64 NEON SIMD path out of the box.  
> Setting `USE_D3D12 = true` at the top of any profile engages the Adreno X2-90 / X2-85 / X2-45 Direct3D 12 compute engine (`MEnableD3D12(USE_D3D12)`) to offload block SAD motion estimation (`motion_search_cs.hlsl`) and frame synthesis (`flow_warp.hlsl`):
> - **MaxQuality (`USE_D3D12 = true`):** Offloads coarse-to-fine diamond motion search (`search=2, searchparam=2`) and unsplit block refinement (`MRecalculate` with `divide=0`) to the Adreno X2 sliced shader architecture, paired with GPU Dynamic Median synthesis (`mode=2, blend=true`) and hardware bilinear texture warping (`pel=1`).
> - **Balanced & Eco (`USE_D3D12 = true`):** Reduces worker thread count to `3` (Balanced) or `2` (Eco) to feed the Direct3D 12 command queue without mutex lock contention, shifting SAD arithmetic off the CPU cores.  
> *(Note: Direct3D 12 GPU offload is provided as an experimental preview; rendering fidelity and real-time performance are provided on a best-effort basis, with native ARM64 CPU NEON remaining the production reference).*

> [!TIP]
> **Heterogeneous Prime + Performance Topology & `AvsAffinity.dll`**  
> Unlike first-generation Snapdragon X Plus and X Elite processors—where all 8 to 12 Oryon cores shared an identical efficiency class and `AvsAffinity.dll` executed a safe no-op—the **Snapdragon X2** series uses a heterogeneous **Prime + Performance** topology (`X2E` 12P+6E or 6P+6E; `X2P-64` 6P+4E).  
> When `last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last` is chained before `Prefetch`, `AvsAffinity.dll` queries Windows `GetLogicalProcessorInformationEx`, identifies the higher `EfficiencyClass` of the Oryon Prime cores, and applies `SetThreadAffinityMask` to lock MVTools2 worker threads strictly onto the Prime cluster. (On the 6-core `X2P-42-100` where all 6 cores share a uniform class, `PinWorkerThreads()` automatically detects `minClass == maxClass` and executes a safe no-op).

---

> [!NOTE]
> **Dynamic 4K Resolution Adaptation:**  
> All profiles automatically adapt across 720p through 4K input resolutions (`is_4k = (src.Width() > 2048)`). For 4K streams (3840×2160), block search dimensions and edge padding automatically scale 2× to maintain the spatial macro-block count invariant (`2,040` coarse / `8,160` fine blocks). This cuts 4K search operations by 75% and prevents GPU execution stalls and memory bus saturation.

## Profile Comparison: Snapdragon X2 Series

| Setting | Profile 1: Eco | Profile 2: Balanced (Default) | Profile 3: Max Quality |
| :--- | :--- | :--- | :--- |
| **Script File** | [`Snapdragon-X2-Eco.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-X2-Eco.avs) | [`Snapdragon-X2-Balanced.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-X2-Balanced.avs) | [`Snapdragon-X2-MaxQuality.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-X2-MaxQuality.avs) |
| **Motion Precision** | `pel=1` (Integer pixel) | `pel=1` (Integer pixel) | `pel=1` (GPU) / `pel=2` (CPU 6-tap Wiener filter) |
| **Block Grid (Base / 4K)** | Single-pass `32x32 / 64x64` (`2,040` blocks) | Single-pass `16x16 / 32x32` (`8,160` blocks) | Dual-pass `32x32 → 16x16 / 64x64 → 32x32` (`MRecalculate`, `divide=0`) |
| **Search Pattern** | Hexagonal (`search=2, searchparam=1`) | Hexagonal (`search=2, searchparam=2`) | Diamond / Hexagonal (`search=2, searchparam=2`) |
| **Chroma Tracking** | Luma only (`chroma=false`) | Luma only (`chroma=false`) | Luma only (`chroma=false`) |
| **Interpolation Mode** | Fast Block Projection (`mode=0`, `blend=false`) | Fast Block Projection (`mode=0`, `blend=false`) | Dynamic Median (`mode=2` GPU) / Projection (`mode=0` CPU), `blend=true` |
| **Threading & Lookahead** | `threads = USE_D3D12 ? 2 : 4`, `Prefetch(threads, 4)` | `threads = USE_D3D12 ? 3 : 6`, `Prefetch(threads, 6)` | `threads = USE_D3D12 ? 4 : 6` *(or `8` on 18C)*, `Prefetch(threads, 8)` |
| **Core Affinity (`AvsAffinity`)** | Pinned to Oryon Prime cluster | Pinned to Oryon Prime cluster | Pinned to Oryon Prime cluster |
| **Memory Allocation** | `SetMemoryMax(512)` | `SetMemoryMax(1024)` | `SetMemoryMax(1536)` (GPU) / `2048` (CPU) |
| **Estimated SoC Power** | 5 W – 8 W | 12 W – 18 W | 20 W – 35 W |

---

## Summary Configuration Checklist

| Setting | Location in Preferences (`F5`) | Recommended Value |
| :--- | :--- | :--- |
| **Hardware Video Decoding** | Filter Control → Video Decoder → Built-in Video Codec/DXVA Settings | `Use DXVA` checked |
| **Hardware Decode Mode** | Filter Control → Video Decoder → Built-in Video Codec/DXVA Settings | `Prioritize D3D11 DXVA` or `DXVA2 Copy-Back` |
| **Codecs Accelerated** | Filter Control → Video Decoder → Built-in Video Codec/DXVA Settings | Built-in decoder active (`AV1`, `HEVC`, `H.264`, `VP9`) |
| **Video Renderer** | Video | `Built-in Direct3D 11 Video Renderer` |
| **Output Colorspace** | Video → Colorspaces | `Auto (Recommended)` / native `NV12` / `YV12` |
| **AviSynth+ Processing** | Video → AviSynth | `Enable AviSynth processing` checked |
| **Buffer (back/ahead)** | Video → AviSynth | `12-16` (Back) / `24-30` (Ahead) |
| **AviSynth+ Script** | Video → AviSynth | [`Snapdragon-X2-Balanced.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-X2-Balanced.avs) |

---

## Verification & OSD Diagnostic

To confirm that the Adreno X2 hardware decoder and 60 fps AviSynth+ interpolation pipeline are functioning properly:

1. Open and play any 24 fps / 30 fps video in PotPlayer.
2. Press **`Tab`** to toggle the On-Screen Display (OSD).
3. Confirm the following real-time metrics:
   - **Video Codec:** Displays **`D3D11 Native/CopyBack`** or **`DXVA2`** *(confirming GPU decode)*.
   - **Video Output:** Shows **`Direct3D 11 Video Renderer`**.
   - **Frame Rate:** Displays **`XX.XX fps -> 60.00 fps`**.
   - **CPU Usage:** Typically remains between 8%–18% on the Balanced profile across the Oryon Prime cores (or under 5% when `USE_D3D12 = true` is enabled).
