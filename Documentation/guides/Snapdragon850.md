# PotPlayer & AviSynth 60fps Configuration Guide: Snapdragon 850

> **Hardware Target:** Qualcomm Snapdragon 850 (SD850 / SDM850)  
> **Integrated GPU:** Qualcomm Adreno 630  
> **CPU Topology:** 4x Kryo 385 Gold (Cortex-A75 @ up to 2.96 GHz) + 4x Kryo 385 Silver (Cortex-A55 @ up to 1.80 GHz)  
> **Memory Subsystem:** 4-Channel LPDDR4x-1866 (~29.8 GB/s Unified Bandwidth)  
> **Thermal Profile:** ~5W Fanless Design *(e.g., Lenovo Yoga C630, Samsung Galaxy Book2)*

---

## Overview & Thermal Strategy

On the Qualcomm Snapdragon 850, software video decoding on the Kryo 385 Gold (Cortex-A75) CPU cores consumes **over 50% of the entire 5W package thermal budget**. When running real-time 60fps AviSynth frame interpolation (`mvtools2`), CPU-based decoding quickly causes thermal saturation, dropping core clocks from 2.96 GHz down to 1.5–1.8 GHz and causing dropped frames and stutter.

To achieve sustained, smooth 60fps playback without thermal throttling:
1. **Adreno 630 Hardware Decoding:** Offload H.264/HEVC/VP9 decode entirely to the Adreno VPU via D3D11 / DXVA2 Copy-Back, reducing CPU decode load to ~0%.
2. **Direct3D 11 Video Renderer:** Display presentation and scaling run directly on Adreno 630 shader units with zero CPU intervention.
3. **Single-Super Native 1080p Analysis:** Eliminates CPU frame downscaling/resizing and redundant pyramid generation (`levels=1`), sharing a single whole-pixel `MSuper` clip across the pipeline.
4. **Coarse-to-Fine Block Refinement:** Employs wide 64×32 blocks for Eco (~1,020 blocks) and dual-pass 32×32 → 16×16 refinement for Balanced/MaxQuality, delivering artifact-free 60fps presentation while bypassing the overhead of 7-pass proxy pipelines.
5. **Strict Core Pinning (`Prefetch(2, 4)` to `Prefetch(4, 4)`):** Limits worker threads so execution stays strictly on the high-IPC Kryo 385 Gold cores, absorbing thread jitter with a 4-frame lookahead queue and avoiding stalls from the in-order Silver cores.

---

## Step 1: Hardware Video Decoder Configuration (Adreno 630 VPU)

1. Open **PotPlayer** and press **`F5`** to open **Preferences**.
2. In the left navigation tree, navigate to:  
   **Filter Control** → **Video Decoder**.
3. Click the **Built-in Video Codec/DXVA Settings** button.
4. Configure the following options:
   - Check **Use DXVA**.
   - Under **Hardware acceleration (DXVA) settings**:
     - Check **Prioritize D3D11 DXVA** *(Recommended)* or set **DXVA2 Copy-Back:** to **`Auto (Recommended)`** / **`Always Use`**.
     - Set **Resolution limit:** to **`Always Use`**.
     - Ensure hardware acceleration is checked for:
       - **H.264/AVC1**
       - **H.265/HEVC**
       - **VP9**
5. Click **Apply**.

> [!IMPORTANT]
> **Why Copy-Back / D3D11?**  
> AviSynth filters receive raw video frames from PotPlayer via `potplayer_source()`. D3D11 / DXVA2 Copy-Back decodes the compressed bitstream inside the Adreno 630 Video Processing Unit (VPU) and transfers the uncompressed planar surface back to system memory with zero CPU decode load.

---

## Step 2: Video Renderer Configuration (Adreno 630 Direct3D Pipeline)

1. In **Preferences (`F5`)**, navigate to the main **Video** page *(do NOT use the sub-page Video → Resize)*.
2. Set **Video Renderer** to:
   - **`Built-in Direct3D 11 Video Renderer`** *(Recommended)*  
     *(Alternative: `EVR Custom Presenter`)*
3. **GPU Scaling Algorithm:**
   - Under **Video Output Settings**, directly below **Direct3D Presentation**, locate the **`Resizer:`** dropdown.
   - Select **`Shader Bilinear`** *(lowest GPU power / battery saver)* or **`Shader Bicubic(A = -0.6)`** *(crisp 1080p presentation)*.  
   *(GPU shader units execute scaling operations without touching the CPU).*
4. Click **Apply**.

---

## Step 3: Colorspace Pass-Through (Zero CPU Conversion)

Converting pixel formats (such as YV12/NV12 to RGB32) on the CPU adds massive memory copying and conversion overhead.

1. In **Preferences (`F5`)**, navigate to:  
   **Video** → **Colorspaces**.
2. Under **Supported Colorspaces / YCbCr <-> RGB conversion**, set **Output color space** to **`Auto (Recommended)`** (or native planar YUV: **`NV12`** / **`YV12`**). Do **NOT** select `RGB 32` or `ARGB 32`.
3. Verify that **High quality YUY2/RGB24/32 conversion** is **Unchecked**.
4. In the format list, ensure the output format priority is set to planar YUV:
   - **`NV12`**
   - **`YV12`**

---

## Step 4: AviSynth Processing & Script Activation

1. In **Preferences (`F5`)**, navigate to:  
   **Video** → **AviSynth**.
2. Check **Enable AviSynth processing**.
3. Check **Add "potplayer_source()"**.
4. Check **Buffer (back/ahead)** and configure buffer limits:
   - **Buffer Back** (first box): Set to **`10`** to **`15`** frames.
   - **Buffer Ahead** (second box): Set to **`20`** to **`24`** frames.
5. Under **Load script:**, choose your preferred Snapdragon 850 profile:
   - **Eco (Battery Saver):** [`Snapdragon-850-Eco.avs`](../../AviSynth/Snapdragon-850-Eco.avs)
   - **Balanced (Recommended):** [`Snapdragon-850-Balanced.avs`](../../AviSynth/Snapdragon-850-Balanced.avs)
   - **Max Quality:** [`Snapdragon-850-MaxQuality.avs`](../../AviSynth/Snapdragon-850-MaxQuality.avs)
6. Click **Apply** → **OK**.

---

## Profile Comparison: Snapdragon 850

| Feature | Eco Profile | Balanced Profile *(Recommended)* | MaxQuality Profile |
| :--- | :--- | :--- | :--- |
| **Analysis Resolution** | Native 1080p (Single Super Clip, `levels=1`) | Native 1080p (Single Super Clip, `levels=1`) | Native 1080p (Single Super Clip, `levels=1`) |
| **Search Block Size** | $64 \times 32$ wide blocks (~1,020 blocks) | Dual-pass 32×32 → 16×16 | Dual-pass 32×32 → 16×16 (`searchparam=2`) |
| **Subpixel Precision** | `pel=1` | `pel=1` | `pel=1` |
| **Search Algorithm** | Hexagonal (`search=2`) | Hexagonal (`search=2`) | Hexagonal (`search=2`) |
| **Outlier Filter** | Off | `badrange=(-24)` | `badrange=(-24)` |
| **Frame Synthesis** | Native 1080p `mode=0` | Native 1080p `mode=0` | Native 1080p `mode=0` |
| **Worker Threads** | `Prefetch(2, 4)` | `Prefetch(3, 4)` | `Prefetch(4, 4)` |
| **Target Power** | ~3.0W – 3.5W | ~3.8W – 4.2W | ~4.5W – 5.0W |

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
| **Buffer (back/ahead)** | Video → AviSynth | `10-15` (Back) / `20-24` (Ahead) |
| **AviSynth Script** | Video → AviSynth | [`Snapdragon-850-Balanced.avs`](../../AviSynth/Snapdragon-850-Balanced.avs) |

---

## Verification & OSD Diagnostic

To confirm that the Adreno 630 hardware decoder and 60fps AviSynth processing are active during playback:

1. Play a video in PotPlayer.
2. Press **`Tab`** to toggle the On-Screen Display (OSD).
3. Verify the following fields:
   - **Video Codec:** Indicates **`D3D11 Native/CopyBack`** or **`DXVA2`** *(not Software / ffmpeg)*.
   - **Output:** **`Direct3D 11 Video Renderer`** (or `EVR`).
   - **Frame Rate:** Displays **`XX fps -> 60.00 fps`**.
   - **CPU Usage:** Stays well below 30–40% on the Kryo 385 Gold cores.
