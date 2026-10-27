# PotPlayer & AviSynth 60fps Configuration Guide: Snapdragon 8cx Gen 1 / Microsoft SQ1

> **Hardware Target:** Qualcomm Snapdragon 8cx Gen 1 / Microsoft SQ1 (SC8180X)  
> **Integrated GPU:** Qualcomm Adreno 680 (1.1 TFLOPS FP32)  
> **CPU Topology:** 4x Kryo 495 Gold (Cortex-A76 @ up to 2.84 GHz) + 4x Kryo 495 Silver (Cortex-A55 @ up to 1.80 GHz)  
> **Memory Subsystem:** 8-Channel LPDDR4x-2133 (68 GB/s Unified Bandwidth)  
> **Thermal Profile:** 7W Fanless Design *(e.g., Microsoft Surface Pro X SQ1, Lenovo Flex 5G / Yoga 5G, Samsung Galaxy Book S)*

---

## Overview & Architecture

The **Qualcomm Snapdragon 8cx Gen 1** (and its Microsoft customized variant, the **Microsoft SQ1**) is a 7nm fanless PC platform operating within a strict **7-Watt system envelope**.

When performing real-time 60fps AviSynth motion interpolation (`mvtools2`), the 4 Kryo 495 Gold (Cortex-A76) performance cores handle NEON motion vector estimation. Because Gen 1 has a tighter thermal ceiling than later revisions, running dual-pass recursive refinement or software video decoding causes the package to rapidly heat up, inducing thermal throttling from 2.84 GHz down to 1.6 GHz.

To ensure continuous, deterministic 60fps playback without dropped frames:
1. **Adreno 680 Hardware Decoding:** Offload H.264/HEVC/VP9 decoding entirely to the Adreno 680 Video Processing Unit (VPU) via D3D11 / DXVA2 Copy-Back, keeping CPU decode load at **0%**.
2. **Direct3D 11 Renderer:** Present video using the Direct3D 11 pipeline so scaling and color conversion execute on the GPU shaders.
3. **Optimized Single-Pass Search:** Gen 1 profiles use high-efficiency single-pass block estimation (16×16 or 32×32), eliminating the memory bus thrashing associated with dual-pass recursive refinement.
4. **Strict Core Pinning (`Prefetch <= 4`):** Thread counts are strictly constrained to 3 or 4 to keep all computation exclusively on the high-IPC Gold cores.

---

## Step 1: Hardware Video Decoder Configuration (Adreno 680 VPU)

1. Open **PotPlayer** and press **`F5`** to open **Preferences**.
2. In the left navigation tree, go to:  
   **Filter Control** → **Video Decoder**.
3. Click the **Built-in Video Codec/DXVA Settings** button.
4. Configure the following options:
   - Check **Use DXVA**.
   - Under **Hardware acceleration (DXVA) settings**:
     - Check **Prioritize D3D11 DXVA** *(Recommended)* or set **DXVA2 Copy-Back:** to **`Auto (Recommended)`** / **`Always Use`**.
     - Set **Resolution limit:** to **`Always Use`**.
     - Verify hardware acceleration is enabled for all supported codecs:
       - **H.264/AVC1**
       - **H.265/HEVC**
       - **VP9**
5. Click **Apply**.

> [!IMPORTANT]
> **Why D3D11 / DXVA2 Copy-Back?**  
> AviSynth filters capture video frames directly from PotPlayer via `potplayer_source()`. D3D11 / DXVA2 Copy-Back decodes the compressed video stream inside the Adreno 680 Video Processing Unit (VPU) and transfers uncompressed planar frames into shared memory for MVTools, keeping CPU decoding load at **0%**.

---

## Step 2: Video Renderer Configuration (Adreno 680 Direct3D 11 Pipeline)

1. In **Preferences (`F5`)**, navigate to the main **Video** page *(do NOT use the sub-page Video → Resize)*.
2. Set **Video Renderer** to:
   - **`Built-in Direct3D 11 Video Renderer`** *(Recommended)*  
     *(Alternative: `EVR Custom Presenter`)*
3. **GPU Scaling Algorithm:**
   - Under **Video Output Settings**, directly below **Direct3D Presentation**, locate the **`Resizer:`** dropdown.
   - Select **`Shader Bicubic(A = -0.6)`** *(Recommended for crisp 1080p presentation)* or **`Shader Bilinear`** *(lowest GPU power)*.  
   *(Scaling and color presentation shaders are executed directly on the Adreno 680 shader cores without consuming CPU cycles).*
4. Click **Apply**.

---

## Step 3: Colorspace Pass-Through (Zero CPU Overhead)

Converting video frames between YUV and RGB on the CPU wastes memory bandwidth and CPU execution cycles.

1. In **Preferences (`F5`)**, navigate to:  
   **Video** → **Colorspaces**.
2. Under **Supported Colorspaces / YCbCr <-> RGB conversion**, set **Output color space** to **`Auto (Recommended)`** (or native planar YUV: **`NV12`** / **`YV12`**). Do **NOT** select `RGB 32` or `ARGB 32`.
3. Verify that **High quality YUY2/RGB24/32 conversion** is **Unchecked**.
4. In the format list, ensure preferred output formats prioritize native planar YUV:
   - **`NV12`**
   - **`YV12`**

---

## Step 4: AviSynth Processing & Script Activation

1. In **Preferences (`F5`)**, navigate to:  
   **Video** → **AviSynth**.
2. Check **Enable AviSynth processing**.
3. Check **Add "potplayer_source()"**.
4. Check **Buffer (back/ahead)** and configure buffer limits:
   - **Buffer Back** (first box): Set to **`12`** to **`15`** frames.
   - **Buffer Ahead** (second box): Set to **`24`** frames.
5. Under **Load script:**, select your preferred Snapdragon 8cx Gen 1 / Microsoft SQ1 script:
   - **Eco (Battery Saver):** [`Snapdragon-8cxGen1-Eco.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen1-Eco.avs)
   - **Balanced (Recommended):** [`Snapdragon-8cxGen1-Balanced.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen1-Balanced.avs)
   - **Max Quality:** [`Snapdragon-8cxGen1-MaxQuality.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen1-MaxQuality.avs)
6. Click **Apply** → **OK**.

> [!TIP]
> **The Thread Capping Rule (`Prefetch <= 4`)**  
> The Snapdragon 8cx Gen 1 / SQ1 features 4 out-of-order Kryo 495 Gold cores and 4 in-order Kryo 495 Silver cores. All provided scripts strictly cap `Prefetch` to **3 or 4 threads** so that MVTools runs exclusively on the Gold performance cores. Never increase `Prefetch` beyond 4, as dispatching work to the slow Silver cores will cause pipeline stalls and video stutter.

> [!TIP]
> **Direct3D 12 GPU Offload (`USE_GPU = true` - Experimental Preview)**  
> All 8cx Gen 1 profiles default to pure CPU NEON execution (`USE_GPU = false`), which serves as the production reference. Setting `USE_GPU = true` engages the **experimental Direct3D 12 preview engine** (`mvtools2_d3d12.dll`) to offload motion search to the Adreno 680 GPU.  
> *(Note: GPU offload is provided as an experimental preview; rendering fidelity and performance are provided on a best-effort basis).*

---

## Profile Comparison: Snapdragon 8cx Gen 1 / SQ1

| Feature | Eco Profile | Balanced Profile *(Recommended)* | MaxQuality Profile |
| :--- | :--- | :--- | :--- |
| **Block Size** | 32×32 | 16×16 | 16×16 |
| **Subpixel Precision** | `pel=1` | `pel=1` | `pel=1` |
| **Search Pattern** | Hexagonal (`search=2`) | Hexagonal (`search=2`) | Hexagonal (`search=2`) |
| **Outlier Filter** | Off | Off | `badrange=(-24)` |
| **Frame Synthesis** | Fast Block (`mode=0`) | Pixel Flow (`mode=2`) | Pixel Flow + Occlusion (`mode=2`) |
| **Worker Threads** | `Prefetch(3, 4)` | `Prefetch(3, 4)` | `Prefetch(4, 4)` |
| **Memory Limit** | 512 MB | 768 MB | 1024 MB |
| **Target Power** | 4.0W – 4.5W | 5.2W – 5.8W | 6.2W – 6.8W |

---

## Summary Configuration Checklist

| Setting | Location in Preferences (`F5`) | Recommended Value |
| :--- | :--- | :--- |
| **Hardware Video Decoding** | Filter Control → Video Decoder → Built-in Video Codec/DXVA Settings | `Use DXVA` checked |
| **Hardware Decode Mode** | Filter Control → Video Decoder → Built-in Video Codec/DXVA Settings | `Prioritize D3D11 DXVA` or `DXVA2 Copy-Back` |
| **Codecs Accelerated** | Filter Control → Video Decoder → Built-in Video Codec/DXVA Settings | `H.264/AVC1`, `H.265/HEVC`, `VP9` |
| **Video Renderer** | Video | `Built-in Direct3D 11 Video Renderer` |
| **Output Colorspace** | Video → Colorspaces | `Auto (Recommended)` / native `NV12` / `YV12` |
| **AviSynth Processing** | Video → AviSynth | `Enable AviSynth processing` checked |
| **Buffer (back/ahead)** | Video → AviSynth | `12-15` (Back) / `24` (Ahead) |
| **AviSynth Script** | Video → AviSynth | [`Snapdragon-8cxGen1-Balanced.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen1-Balanced.avs) |

---

## Verification & OSD Diagnostic

To verify that the Adreno 680 hardware decoder and 60fps interpolation are active during playback:

1. Open and play any 24fps/30fps video in PotPlayer.
2. Press **`Tab`** to toggle the On-Screen Display (OSD).
3. Confirm the following real-time metrics:
   - **Video Codec:** Displays **`D3D11 Native/CopyBack`** or **`DXVA2`** *(not Software / ffmpeg)*.
   - **Video Output:** Shows **`Direct3D 11 Video Renderer`**.
   - **Frame Rate:** Displays **`XX.XX fps -> 60.00 fps`**.
   - **CPU Usage:** Remains stable around 20%–35% across the Kryo 495 Gold cores.
