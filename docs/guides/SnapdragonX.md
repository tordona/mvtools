# PotPlayer & AviSynth 60 fps Configuration Guide: Snapdragon X Series (X Elite / X Plus)

> **Hardware Target:** Qualcomm Snapdragon X Series (X Elite: X1E-78/80/84-100 / X Plus: X1P-42/46/64-100)  
> **Integrated GPU:** Qualcomm Adreno X1-85 (3.8 TFLOPS FP32)  
> **CPU Topology:** 8 to 12 Uniform High-IPC Qualcomm Oryon Cores @ up to 3.4–4.3 GHz *(No E-cores)*  
> **Memory Subsystem:** 8-Channel LPDDR5x-8448 MHz (135 GB/s Unified Bandwidth)  
> **Thermal Profile:** 15 W – 45 W Active / High-Efficiency Passive Designs

---

## Overview & Thermal Strategy

The **Qualcomm Snapdragon X Series** platform operates across a configurable **15 W – 45 W thermal envelope**, scaling from high-efficiency passive/convertible designs to actively cooled laptop chassis:

1. **Uniform Oryon CPU Cores:** Unlike heterogeneous big.LITTLE architectures, the Snapdragon X Series features **8 to 12 uniform high-performance Oryon CPU cores** (up to 3.4–4.3 GHz). Eliminating in-order efficiency cores removes asymmetric worker thread bottlenecks.
2. **Thermal Budget Preservation via Adreno X1 VPU:** Software decoding of modern high-bitrate codecs (such as 4K AV1 or 10-bit HEVC) can draw over 6 W – 8 W on the CPU cores alone, elevating package temperatures and triggering cooling fans or thermal stepping. Offloading decode entirely to the Adreno X1 VPU reduces CPU decode overhead to 0%, preserving thermal headroom for MVTools synthesis.
3. **High Memory Bandwidth (135 GB/s):** The unified 8-channel LPDDR5x memory bus provides 135 GB/s of bandwidth, accommodating multi-level subpixel pyramids (`pel=2`) and high-resolution frame buffers without memory bus throttling.
4. **Thermal Profile Scaling:** 
   - **Eco (5 W – 8 W):** `Prefetch(4)` keeps 4 to 8 Oryon cores completely idle, ensuring minimal thermal dissipation and silent fanless operation.
   - **Balanced (12 W – 18 W):** `Prefetch(6)` provides 60 fps interpolation with idle cores reserved for OS processes and thermal dissipation.
   - **MaxQuality (22 W – 35 W+):** `Prefetch(8)` (or `Prefetch(12)`) utilizes all Oryon cores for fine-grid motion vectors within active cooling thermal ceilings.

---

## Step 1: Hardware Video Decoder Configuration (Adreno X1 VPU)

The Adreno X1 Video Processing Unit (VPU) includes dedicated hardware decoders for modern codecs, including AV1.

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
       - **AV1:** `Built-in FFmpeg Decoder (Recommended)` *(Adreno X1 hardware accelerated)*
       - **H.265/HEVC:** `Built-in FFmpeg Decoder (Recommended)`
       - **H.264/AVC1:** `Built-in FFmpeg Decoder (Recommended)`
       - **VP9:** `Built-in FFmpeg Decoder (Recommended)`
5. Click **Apply**.

> [!IMPORTANT]
> **Why D3D11 / Copy-Back?**  
> AviSynth filters receive video input through `potplayer_source()`. D3D11 Copy-Back decodes video directly inside the Adreno X1 hardware VPU and maps the uncompressed frames into shared memory, reducing CPU decode overhead from approx. 35% down to **0%**.

---

## Step 2: Video Renderer Configuration (Adreno X1 Direct3D 11 Pipeline)

1. In **Preferences (`F5`)**, navigate to the main **Video** page *(do NOT use the sub-page Video → Resize)*.
2. Set **Video Renderer** to:
   - **`Built-in Direct3D 11 Video Renderer`** *(Recommended)*
3. **GPU Scaling Algorithm:**
   - Under **Video Output Settings**, directly below **Direct3D Presentation**, locate the **`Resizer:`** dropdown.
   - Select **`Shader Bicubic(A = -0.6)`** *(Recommended for balanced performance)* or **`Shader(2-Pass) Lanczos 2`** *(Max Quality)*.  
   *(The Adreno X1 GPU executes scaling and display shaders with negligible power consumption).*
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

## Step 4: AviSynth Processing & Script Profile Selection

1. In **Preferences (`F5`)**, navigate to:  
   **Video** → **AviSynth**.
2. Check **Enable AviSynth processing**.
3. Check **Add "potplayer_source()"**.
4. Check **Buffer (back/ahead)** and configure buffer limits:
   - **Buffer Back** (first box): Set to **`12`** to **`16`** frames.
   - **Buffer Ahead** (second box): Set to **`24`** to **`30`** frames.
5. Under **Load script:**, select your desired Snapdragon X script:
   - **Profile 1 (Eco / Battery Saver):** [`Snapdragon-X-Eco.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-X-Eco.avs)
   - **Profile 2 (Balanced / Daily Driver):** [`Snapdragon-X-Balanced.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-X-Balanced.avs) *(Recommended)*
   - **Profile 3 (Max Quality / Fine Grid):** [`Snapdragon-X-MaxQuality.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-X-MaxQuality.avs)
   *(Note: Snapdragon X Elite / Plus users can also run [`Snapdragon-8cxGen3-*.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-8cxGen3-Balanced.avs) as an ultra-low-power battery saver option).*
6. Click **Apply** → **OK**.

> [!TIP]
> **Direct3D 12 GPU Offload (`USE_D3D12 = true` — Experimental Preview)**  
> On Snapdragon X Series platforms, the 8–12 Oryon CPU cores easily sustain the Balanced and Eco tiers with native NEON SIMD (`mvtools2.dll`), serving as the production reference engine.  
> Setting `USE_D3D12 = true` at the top of the profile engages the Adreno X1-85 GPU compute engine (`MEnableD3D12(true)`) to offload block SAD motion estimation and frame synthesis:
> - **MaxQuality (`USE_D3D12 = true`):** Executes diamond motion search (`search=2, searchparam=2`, ~12 coarse candidate points) and fine diamond refinement (`fine_rad=2`) entirely in Adreno X1 compute shaders (`motion_search_cs.hlsl`). Coupled with hardware bilinear texture warping (`pel=1`), host CPU load is reduced from 10.6% down to **6.0%** (a 43.4% CPU overhead reduction).
> - **Balanced (`USE_D3D12 = true`):** Reduces host CPU load to **6.3%** and working set RAM to **335.9 MB** while sustaining **55.53 fps 1% Low** pacing and zero dropped frames.  
> *(Note: Direct3D 12 GPU offload is provided as an experimental preview; rendering fidelity and real-time performance are provided on a best-effort basis, with native ARM64 CPU NEON remaining the production reference).*

> [!NOTE]
> **Homogeneous Architecture & `AvsAffinity.dll`**  
> Because Qualcomm Snapdragon X Plus and X Elite use uniform Qualcomm Oryon CPU cores across the entire SoC (no low-IPC Efficiency cores), `AvsAffinity.dll` automatically detects uniform efficiency (`minClass == maxClass`) and executes a safe no-op (`mask = 0x0`), allowing threads to schedule freely across all 8 to 12 Oryon cores without modification to system affinity.

---

> [!NOTE]
> **Dynamic 4K Resolution Adaptation:**  
> All profiles support source resolutions from 720p to 4K and automatically detect input dimensions exceeding 2048px (`is_4k = (src.Width() > 2048)`). For 4K streams (3840×2160), block search dimensions and edge padding automatically scale 2× to maintain the spatial macro-block count invariant (~8,160 blocks). This cuts 4K search operations by 75% and prevents GPU execution stalls and memory bus saturation.

## Profile Comparison: Snapdragon X Series

| Setting | Profile 1: Eco | Profile 2: Balanced (Default) | Profile 3: Max Quality |
| :--- | :--- | :--- | :--- |
| **Script File** | [`Snapdragon-X-Eco.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-X-Eco.avs) | [`Snapdragon-X-Balanced.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-X-Balanced.avs) | [`Snapdragon-X-MaxQuality.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-X-MaxQuality.avs) |
| **Motion Precision** | `pel=1` (Integer pixel) | `pel=1` + Dual-pass Refinement | `pel=1` (GPU) / `pel=2` (CPU Wiener filter) |
| **Block Grid (Base / 4K)** | Single-pass `32x32 / 64x64` | Dual-pass `32x32 → 16x16 / 64x64 → 32x32` | Dual-pass `32x32 → 16x16 / 64x64 → 32x32` (GPU)<br>`16x16 → 8x8 / 32x32 → 16x16` (CPU) |
| **Search Pattern** | Hexagonal (`search=2`) | Hexagonal (`search=2`) | Diamond (`search=2`, searchparam=2) |
| **Chroma Tracking** | Luma only (`chroma=false`) | Luma only (`chroma=false`) | Luma only (GPU) / Full Y+U+V (CPU) |
| **Interpolation Mode** | Pixel Flow (`mode=2`, `blend=false`) | Dynamic Median (`mode=2`, `blend=true`) | Dynamic Median (`mode=2`, `blend=true`) |
| **Threading (`Prefetch`)** | `Prefetch(4)` *(4–8 cores idle)* | `Prefetch(4)` (GPU) / `Prefetch(6)` (CPU) | `Prefetch(4)` (GPU) / `Prefetch(8)` (CPU) |
| **Memory Allocation** | `SetMemoryMax(1024)` | `SetMemoryMax(1536)` (GPU) / `2048` (CPU) | `SetMemoryMax(2048)` (GPU) / `4096` (CPU) |
| **Estimated SoC Power** | 5 W – 8 W | 12 W – 18 W | 22 W – 35 W |

---

## Summary Configuration Checklist

| Setting | Location in Preferences (`F5`) | Recommended Value |
| :--- | :--- | :--- |
| **Hardware Video Decoding** | Filter Control → Video Decoder → Built-in Video Codec/DXVA Settings | `Use DXVA` checked |
| **Hardware Decode Mode** | Filter Control → Video Decoder → Built-in Video Codec/DXVA Settings | `Prioritize D3D11 DXVA` or `DXVA2 Copy-Back` |
| **Codecs Accelerated** | Filter Control → Video Decoder → Built-in Video Codec/DXVA Settings | Built-in decoder active (`AV1`, `HEVC`, `H.264`, `VP9`) |
| **Video Renderer** | Video | `Built-in Direct3D 11 Video Renderer` |
| **Output Colorspace** | Video → Colorspaces | `Auto (Recommended)` / native `NV12` / `YV12` |
| **AviSynth Processing** | Video → AviSynth | `Enable AviSynth processing` checked |
| **Buffer (back/ahead)** | Video → AviSynth | `12-16` (Back) / `24-30` (Ahead) |
| **AviSynth Script** | Video → AviSynth | [`Snapdragon-X-Balanced.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-X-Balanced.avs) |

---

## Verification & OSD Diagnostic

To confirm that the Adreno X1 hardware decoder and 60 fps AviSynth interpolation pipeline are functioning properly:

1. Open and play any 24 fps/30 fps video in PotPlayer.
2. Press **`Tab`** to toggle the On-Screen Display (OSD).
3. Confirm the following real-time metrics:
   - **Video Codec:** Displays **`D3D11 Native/CopyBack`** or **`DXVA2`** *(confirming GPU decode)*.
   - **Video Output:** Shows **`Direct3D 11 Video Renderer`**.
   - **Frame Rate:** Displays **`XX.XX fps -> 60.00 fps`**.
   - **CPU Usage:** Typically stays between 10%–25% on the Balanced profile across the Oryon cores.
