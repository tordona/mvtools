# PotPlayer & AviSynth 60fps Configuration Guide: Snapdragon 8cx Gen 2 / Microsoft SQ2

> **Hardware Target:** Qualcomm Snapdragon 8cx Gen 2 / Microsoft SQ2 (SC8180XP)  
> **Integrated GPU:** Qualcomm Adreno 680 (1.3 TFLOPS FP32)  
> **CPU Topology:** 4x Kryo 495 Gold (Cortex-A76 @ up to 3.00–3.15 GHz) + 4x Kryo 495 Silver (Cortex-A55 @ up to 1.80 GHz)  
> **Memory Subsystem:** 8-Channel LPDDR4x-2133 (68 GB/s Unified Bandwidth)  
> **Thermal Profile:** 7W–10W Fanless Design *(e.g., Microsoft Surface Pro X SQ2, Acer Spin 7, HP Elite Folio)*

---

## Overview & Architecture

The **Qualcomm Snapdragon 8cx Gen 2** (and its Microsoft customized variant, the **Microsoft SQ2**) operates within a **7W to 10W fanless thermal envelope** with an 8-channel LPDDR4x-2133 memory bus (68 GB/s).

When performing real-time 60fps AviSynth motion interpolation (`mvtools2`), the 4 Kryo 495 Gold (Cortex-A76) performance cores are dedicated to NEON motion vector estimation. If video decoding or display scaling is executed on the CPU, the SoC quickly reaches its thermal ceiling, throttling CPU clocks and causing frame drops.

Offloading both **video decoding** and **display presentation** to the **Adreno 680 iGPU** preserves 100% of the CPU thermal budget for MVTools, ensuring smooth 60fps video playback with zero dropped frames.

> [!NOTE]
> **Microsoft SQ2 Compatibility:**  
> The Microsoft SQ2 processor in the Surface Pro X is physically identical silicon to the Snapdragon 8cx Gen 2 (`SC8180XP`). Use these profiles and settings directly for SQ2 devices.

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
5. Under **Load script:**, select your preferred Snapdragon 8cx Gen 2 / Microsoft SQ2 script:
   - **Eco (Battery Saver):** [`Snapdragon-8cxGen2-Eco.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen2-Eco.avs)
   - **Balanced (Recommended):** [`Snapdragon-8cxGen2-Balanced.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen2-Balanced.avs)
   - **Max Quality:** [`Snapdragon-8cxGen2-MaxQuality.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen2-MaxQuality.avs)
6. Click **Apply** → **OK**.

> [!TIP]
> **The Thread Capping Rule (`Prefetch <= 4`)**  
> The Snapdragon 8cx Gen 2 features 4 out-of-order Kryo 495 Gold cores and 4 in-order Kryo 495 Silver cores. All provided 8cx Gen 2 scripts strictly cap `Prefetch` to **3 or 4 threads** so that MVTools runs exclusively on the Gold performance cores. Never increase `Prefetch` beyond 4, as dispatching work to the slow Silver cores will cause pipeline stalls and video stutter.

> [!TIP]
> **Direct3D 12 GPU Offload (`USE_GPU = true` - Experimental Preview)**  
> All 8cx Gen 2 profiles default to pure CPU execution (`USE_GPU = false`), which serves as the production reference and delivers continuous, rock-solid 60fps.  
> Setting `USE_GPU = true` at the top of the scripts engages the **experimental Direct3D 12 preview engine** (`mvtools2_d3d12.dll`) to offload motion search to the Adreno 680 GPU:
> - **Balanced (`USE_GPU = true`):** Sustains 60fps with CPU load dropping to just **12%–18%** and GPU load at **60%–66%** (lows at 35%), keeping temperatures whisper-cool.
> - **MaxQuality (`USE_GPU = true`):** Automatically adapts to 32×32 → 16×16 (`pel=1`) to prevent L1/L2 texture cache thrashing, sustaining continuous 60fps.
>
> *(Note: GPU offload is provided as an experimental preview; rendering fidelity and performance are provided on a best-effort basis).*

---

## Profile Comparison: Snapdragon 8cx Gen 2 / SQ2

| Feature | Eco Profile | Balanced Profile *(Recommended)* | MaxQuality Profile |
| :--- | :--- | :--- | :--- |
| **Motion Search** | Single-pass 32×32 | Dual-pass 32×32 → 16×16 | Dual-pass 16×16 → 8×8 (CPU) / 32×32 → 16×16 (GPU) |
| **Subpixel Precision** | `pel=1` | `pel=1` | `pel=1` |
| **Search Pattern** | Hexagonal (`search=2`) | Hexagonal (`search=2`) | Hexagonal (`search=2`) |
| **Outlier Filter** | Off | Off | `badrange=(-24)` |
| **Frame Synthesis** | Fast Block (`mode=0`) | Pixel Flow (`mode=2`) | Pixel Flow + Occlusion (`mode=2`) |
| **Worker Threads** | `Prefetch(3, 4)` | `Prefetch(4, 4)` | `Prefetch(4, 4)` |
| **Target Power** | 4.5W – 5.5W | 6.5W – 7.5W | 7.5W – 8.8W |

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
| **AviSynth Script** | Video → AviSynth | [`Snapdragon-8cxGen2-Balanced.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen2-Balanced.avs) |

---

## Verification & OSD Diagnostic

To verify that the Adreno 680 hardware decoder and 60fps interpolation are active during playback:

1. Open and play any 24fps/30fps video in PotPlayer.
2. Press **`Tab`** to toggle the On-Screen Display (OSD).
3. Confirm the following real-time metrics:
   - **Video Codec:** Displays **`D3D11 Native/CopyBack`** or **`DXVA2`** *(not Software / ffmpeg)*.
   - **Video Output:** Shows **`Direct3D 11 Video Renderer`**.
   - **Frame Rate:** Displays **`XX.XX fps -> 60.00 fps`**.
   - **CPU Usage:** Remains low and stable (typically 12%–18% with `USE_GPU = true` or 20%–35% with `USE_GPU = false`).
