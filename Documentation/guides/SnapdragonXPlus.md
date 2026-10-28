# PotPlayer & AviSynth 60 fps Configuration Guide: Snapdragon X Plus

> **Hardware Target:** Qualcomm Snapdragon X Plus (X1P-42-100 / X1P-46-100 / X1P-64-100)  
> **Integrated GPU:** Qualcomm Adreno X1-85 (3.8 TFLOPS FP32)  
> **CPU Topology:** 8x Uniform High-IPC Qualcomm Oryon Cores @ up to 3.4 GHz *(No E-cores)*  
> **Memory Subsystem:** 8-Channel LPDDR5x-8448 MHz (135 GB/s Unified Bandwidth)  
> **Thermal Profile:** 15 W – 30 W Active / High-Efficiency Passive Designs

---

## Overview & Thermal Strategy

The **Qualcomm Snapdragon X Plus** platform operates across a configurable **15 W – 30 W thermal envelope**, scaling from high-efficiency passive/convertible designs to actively cooled laptop chassis:

1. **Uniform Oryon CPU Cores:** Unlike heterogeneous big.LITTLE architectures, the Snapdragon X Plus features **8 uniform high-performance Oryon CPU cores** (up to 3.4 GHz). Eliminating in-order efficiency cores removes asymmetric worker thread bottlenecks.
2. **Thermal Budget Preservation via Adreno X1 VPU:** Software decoding of modern high-bitrate codecs (such as 4K AV1 or 10-bit HEVC) can draw over 6 W – 8 W on the CPU cores alone, elevating package temperatures and triggering cooling fans or thermal stepping. Offloading decode entirely to the Adreno X1 VPU reduces CPU decode overhead to 0%, preserving thermal headroom for MVTools synthesis.
3. **High Memory Bandwidth (135 GB/s):** The unified 8-channel LPDDR5x memory bus provides 135 GB/s of bandwidth, accommodating multi-level subpixel pyramids (`pel=2`) and high-resolution frame buffers without memory bus throttling.
4. **Thermal Profile Scaling:** 
   - **Eco (5 W – 8 W):** `Prefetch(4)` keeps 4 Oryon cores completely idle, ensuring minimal thermal dissipation and silent fanless operation.
   - **Balanced (12 W – 16 W):** `Prefetch(6)` provides 60 fps interpolation with 2 idle cores reserved for OS processes and thermal dissipation.
   - **MaxQuality (22 W – 28 W):** `Prefetch(8)` utilizes all 8 cores for fine-grid motion vectors within active cooling thermal ceilings.

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
5. Under **Load script:**, select your desired Snapdragon X Plus script:
   - **Profile 1 (Eco / Battery Saver):** [`Snapdragon-X-Plus-Eco.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-X-Plus-Eco.avs)
   - **Profile 2 (Balanced / Daily Driver):** [`Snapdragon-X-Plus-Balanced.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-X-Plus-Balanced.avs) *(Recommended)*
   - **Profile 3 (Max Quality / Fine Grid):** [`Snapdragon-X-Plus-MaxQuality.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-X-Plus-MaxQuality.avs)
   *(Note: Snapdragon X Elite / Plus users can also run [`Snapdragon-8cxGen3-*.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen3-Balanced.avs) as an ultra-low-power battery saver option).*
6. Click **Apply** → **OK**.

> [!TIP]
> **Direct3D 12 GPU Acceleration (`mvtools2_d3d12.dll` - Experimental Preview)**  
> On Snapdragon X Plus / Elite platforms, the 8–12 Oryon CPU cores easily sustain the Balanced and Eco tiers with native NEON SIMD (`mvtools2.dll`), serving as the production reference engine.  
> Direct3D 12 GPU offload via `mvtools2_d3d12.dll` is provided as an **experimental preview** for offloading motion estimation into the Adreno X1-85 GPU compute queue. Rendering quality, motion vector precision, and real-time performance are provided on a best-effort basis.

---

## Profile Comparison: Snapdragon X Plus

| Setting | Profile 1: Eco | Profile 2: Balanced (Default) | Profile 3: Max Quality |
| :--- | :--- | :--- | :--- |
| **Script File** | [`Snapdragon-X-Plus-Eco.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-X-Plus-Eco.avs) | [`Snapdragon-X-Plus-Balanced.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-X-Plus-Balanced.avs) | [`Snapdragon-X-Plus-MaxQuality.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-X-Plus-MaxQuality.avs) |
| **Motion Precision** | `pel=1` (Integer pixel) | `pel=1` + Dual-pass Refinement | `pel=2` (Half-pixel Wiener filter) |
| **Block Grid** | Single-pass `32x32` | Dual-pass `32x32` → `16x16` | Dual-pass `16x16` → `8x8` micro-blocks |
| **Search Pattern** | Hexagonal (`search=2`) | Hexagonal (`search=2`) | UMH / Exhaustive (`search=3`) |
| **Chroma Tracking** | Luma only (`chroma=false`) | Luma only (`chroma=false`) | Full Y+U+V (`chroma=true`) |
| **Interpolation Mode** | Fast Block (`mode=0`) | Pixel Flow (`mode=2`) | Pixel Flow + Occlusion (`mode=2`) |
| **Threading (`Prefetch`)** | `Prefetch(4)` *(4 cores idle)* | `Prefetch(6)` *(Leaves 2 cores for OS)* | `Prefetch(8)` *(Full 8-core saturation)* |
| **Memory Allocation** | `SetMemoryMax(1024)` | `SetMemoryMax(2048)` | `SetMemoryMax(4096)` |
| **Estimated SoC Power** | 5 W – 8 W | 12 W – 16 W | 22 W – 28 W |

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
| **AviSynth Script** | Video → AviSynth | [`Snapdragon-X-Plus-Balanced.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-X-Plus-Balanced.avs) |

---

## Verification & OSD Diagnostic

To confirm that the Adreno X1 hardware decoder and 60 fps AviSynth interpolation pipeline are functioning properly:

1. Open and play any 24 fps/30 fps video in PotPlayer.
2. Press **`Tab`** to toggle the On-Screen Display (OSD).
3. Confirm the following real-time metrics:
   - **Video Codec:** Displays **`D3D11 Native/CopyBack`** or **`DXVA2`** *(confirming GPU decode)*.
   - **Video Output:** Shows **`Direct3D 11 Video Renderer`**.
   - **Frame Rate:** Displays **`XX.XX fps -> 60.00 fps`**.
   - **CPU Usage:** Typically stays between 15%–25% on the Balanced profile across the Oryon cores.
