# PotPlayer & AviSynth 60 fps Configuration Guide: Snapdragon C

> **Hardware Target:** Qualcomm Snapdragon C  
> **Integrated GPU:** Qualcomm Adreno A643  
> **CPU Topology:** 8-Core Heterogeneous Kryo (1x Prime @ up to 3.0 GHz + 3x Performance @ up to 2.6 GHz + 4x Efficiency @ up to 2.0 GHz)  
> **Memory Subsystem:** LPDDR4x / LPDDR5 Dual-Channel (~25–34 GB/s Unified Bandwidth)  
> **Thermal Profile:** ~5 W – 10 W Fanless Chassis ($300 Budget Class)

---

## Overview & Thermal Strategy

The **Qualcomm Snapdragon C** brings 64-bit Windows on ARM computing to budget-tier laptops operating within a strictly constrained **~5 W – 10 W fanless thermal envelope**:

1. **Heterogeneous Kryo Topology & Thread Pinning:** The processor combines 1 Prime core (up to 3.0 GHz), 3 Performance cores (up to 2.6 GHz), and 4 Efficiency cores (up to 2.0 GHz). Because the Efficiency cores possess low IPC, compute-heavy motion vector threads must be isolated to the Performance/Prime cores via `AvsAffinity.dll` (`PinWorkerThreads`). This keeps the 4 Efficiency cores free for hardware video decoding, audio rendering, and Direct3D 11 swapchain presentation.
2. **Thermal Budget Preservation via Adreno VPU:** Software decoding of modern codecs (such as AV1 or 10-bit HEVC) would saturate the low-power CPU cores and exhaust the 5 W – 10 W thermal budget. Offloading decode entirely to the Adreno VPU via D3D11 Copy-Back reduces host CPU decode load to 0%, preserving thermal headroom for real-time 60 fps interpolation.
3. **Memory Bus Protection (25–34 GB/s):** On budget memory architectures, memory allocations are capped between `512 MB` and `1024 MB` (`levels=1`), preventing cache thrashing and DRAM bus saturation.
4. **Thermal Profile Scaling:**
   - **Eco (3 W – 5 W):** 0.5x proxy search (`threads = 2`) locked to the Prime and 1 Performance core for silent, cool, extended battery playback.
   - **Balanced (6 W – 8 W):** Direct-resolution coarse-to-fine search (`threads = 3`) for smooth 60 fps playback.
   - **MaxQuality (~10 W):** Full saturation of all 4 Performance-tier cores (`threads = 4`) with hexagonal refinement.

---

## Step 1: Hardware Video Decoder Configuration (Adreno VPU)

The integrated Adreno Video Processing Unit (VPU) includes dedicated hardware decoders for modern codecs, including AV1.

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
       - **AV1:** `Built-in FFmpeg Decoder (Recommended)` *(Adreno hardware accelerated)*
       - **H.265/HEVC:** `Built-in FFmpeg Decoder (Recommended)`
       - **H.264/AVC1:** `Built-in FFmpeg Decoder (Recommended)`
       - **VP9:** `Built-in FFmpeg Decoder (Recommended)`
5. Click **Apply**.

> [!IMPORTANT]
> **Why D3D11 / Copy-Back?**  
> AviSynth filters receive video input through `potplayer_source()`. D3D11 Copy-Back decodes video directly inside the Adreno VPU and maps the uncompressed frames into shared memory, reducing CPU decode overhead down to **0%**.

---

## Step 2: Video Renderer Configuration (Direct3D 11 Pipeline)

1. In **Preferences (`F5`)**, navigate to the main **Video** page *(do NOT use the sub-page Video → Resize)*.
2. Set **Video Renderer** to:
   - **`Built-in Direct3D 11 Video Renderer`** *(Recommended)*
3. **GPU Scaling Algorithm:**
   - Under **Video Output Settings**, directly below **Direct3D Presentation**, locate the **`Resizer:`** dropdown.
   - Select **`Shader Bicubic(A = -0.6)`** *(Recommended for balanced performance)*.
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
5. Under **Load script:**, select your desired Snapdragon C script:
   - **Profile 1 (Eco / Battery Saver):** [`Snapdragon-C-Eco.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-C-Eco.avs)
   - **Profile 2 (Balanced / Daily Driver):** [`Snapdragon-C-Balanced.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-C-Balanced.avs) *(Recommended)*
   - **Profile 3 (Max Quality / Fine Grid):** [`Snapdragon-C-MaxQuality.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-C-MaxQuality.avs)
6. Click **Apply** → **OK**.

> [!NOTE]
> **Asymmetric Core Pinning & `AvsAffinity.dll`**  
> On Snapdragon C devices, `AvsAffinity.dll` detects the heterogeneous efficiency spread between the Prime/Performance cores and the 4 Efficiency cores, pinning video motion worker threads strictly to the Performance cluster. This prevents microstutter caused by thread migration to the low-frequency Efficiency cores.

---

> [!NOTE]
> **Dynamic 4K Resolution Adaptation:**  
> All profiles support source resolutions from 720p to 4K and automatically detect input dimensions exceeding 2048px (`is_4k = (src.Width() > 2048)`). For 4K streams (3840×2160), block search dimensions and edge padding automatically scale to maintain the spatial macro-block count invariant, preserving the 5 W – 10 W fanless thermal envelope.

## Profile Comparison: Snapdragon C

| Setting | Profile 1: Eco | Profile 2: Balanced (Default) | Profile 3: Max Quality |
| :--- | :--- | :--- | :--- |
| **Script File** | [`Snapdragon-C-Eco.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-C-Eco.avs) | [`Snapdragon-C-Balanced.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-C-Balanced.avs) | [`Snapdragon-C-MaxQuality.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-C-MaxQuality.avs) |
| **Motion Precision** | `pel=1` (Integer pixel) | `pel=1` + Dual-pass Refinement | `pel=1` + Dual-pass Refinement |
| **Block Grid (Base / 4K)** | 0.5x Proxy `16x16 → 32x32` | Dual-pass `32x32 → 16x16 / 64x64 → 32x32` | Dual-pass `32x32 → 16x16 / 64x64 → 32x32` |
| **Search Pattern** | Hexagonal (`search=2, searchparam=1`) | Hexagonal (`search=2, searchparam=1`) | Hexagonal (`search=2, searchparam=2`) |
| **Chroma Tracking** | Luma only (`chroma=false`) | Luma only (`chroma=false`) | Luma only (`chroma=false`) |
| **Interpolation Mode** | Block Projection (`mode=0`, `blend=false`) | Dynamic Median (`mode=2`, `blend=true`) | Dynamic Median (`mode=2`, `blend=true`) |
| **Threading (`Prefetch`)** | `Prefetch(2, 4)` | `Prefetch(3, 4)` | `Prefetch(4, 4)` |
| **Memory Allocation** | `SetMemoryMax(512)` | `SetMemoryMax(768)` | `SetMemoryMax(1024)` |
| **Hardware Core Pinning** | `PinWorkerThreads(strictPrime=true)` | `PinWorkerThreads()` | `PinWorkerThreads()` |
| **Estimated SoC Power** | 3 W – 5 W | 6 W – 8 W | ~10 W |

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
| **AviSynth Script** | Video → AviSynth | [`Snapdragon-C-Balanced.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/AviSynth/Snapdragon-C-Balanced.avs) |

---

## Verification & OSD Diagnostic

To confirm that the Adreno hardware decoder and 60 fps AviSynth interpolation pipeline are functioning properly:

1. Open and play any 24 fps/30 fps video in PotPlayer.
2. Press **`Tab`** to toggle the On-Screen Display (OSD).
3. Confirm the following real-time metrics:
   - **Video Codec:** Displays **`D3D11 Native/CopyBack`** or **`DXVA2`** *(confirming GPU decode)*.
   - **Video Output:** Shows **`Direct3D 11 Video Renderer`**.
   - **Frame Rate:** Displays **`XX.XX fps -> 60.00 fps`**.
   - **CPU Usage:** Typically stays between 35%–55% on the Balanced profile across the Performance cores, with Efficiency cores remaining quiescent.
