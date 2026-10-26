# PotPlayer & AviSynth 60fps Configuration Guide: Snapdragon 8cx Gen 3 / Microsoft SQ3

> **Hardware Target:** Qualcomm Snapdragon 8cx Gen 3 / Microsoft SQ3 (SC8280X)  
> **Integrated GPU:** Qualcomm Adreno 690 (2.2 TFLOPS FP32)  
> **CPU Topology:** 4x Cortex-X1 Prime Cores (@ up to 3.0 GHz) + 4x Cortex-A78 Performance Cores (@ up to 2.4 GHz)  
> **Memory Bus:** 8-channel LPDDR4x-4266 / LPDDR5-6400 (136 GB/s)  
> **Thermal Profile:** 7W–15W *(e.g., Lenovo ThinkPad X13s, Microsoft Surface Pro 9 5G)*

---

## Overview

The Qualcomm Snapdragon 8cx Gen 3 (and Microsoft SQ3) represents a monumental leap over earlier Snapdragon PC chipsets:
1. **Heterogeneous Performance CPU Topology**: Gen 3 completely eliminated in-order Cortex-A55 efficiency cores, pairing 4x Cortex-X1 Prime cores (@ up to 3.0 GHz) with 4x Cortex-A78 Performance cores (@ up to 2.4 GHz). To prevent asymmetric thread latency stalls and guarantee 0 dropped frames, MVTools worker threads are pinned cleanly to the 4x Cortex-X1 Prime cluster (`threads = 4`, with 4 lookahead queue frames), while the 4x Cortex-A78 cores handle Windows background tasks, audio rendering, PotPlayer UI, and DirectShow filters.
2. **Adreno 690 Compute Engine (2.2 TFLOPS)**: Delivers approx. 70% higher compute shader throughput than Gen 2's Adreno 680, easily running dual-pass motion refinement without thermal saturation.
3. **Double Memory Bandwidth (136 GB/s)**: Eliminates texture cache thrashing and memory bus bottlenecks during high-resolution planar uploads.

---

## Profile Architecture & Performance

All Snapdragon 8cx Gen 3 profiles utilize native 1080p motion estimation with `levels=1` single-level base clip processing and `Prefetch(threads, 4)` lookahead buffering:

| Profile | Target & Use Case | Motion Search Grid | Synthesis Mode | Thread Pinning & Queue |
| :--- | :--- | :--- | :--- | :--- |
| **Eco** | Ultra-Low Power, Maximum Battery Longevity | Single-Pass 32×32 Blocks (`searchparam=1`) | `mode=0` Block Projection | `threads=3`, `Prefetch(3, 4)` (leaves 1 X1 + 4 A78 idle) |
| **Balanced** | Fluid 1080p 60fps, Refined Edges *(Recommended)* | Dual-Pass 32×32 → 16×16 (`MRecalculate`) | `mode=0` Block Projection | `threads=4`, `Prefetch(4, 4)` (pinned to 4x Cortex-X1) |
| **MaxQuality** | High-Fidelity Action, Wide Search Radius | Dual-Pass 32×32 (`searchparam=2`) → 16×16 | `mode=0` Block Projection | `threads=4`, `Prefetch(4, 4)` (pinned to 4x Cortex-X1) |

---

## Step 1: Hardware Video Decoder Configuration (Adreno 690 VPU)

1. Open **PotPlayer** and press **`F5`** to open **Preferences**.
2. In the left navigation tree, go to:  
   **Filter Control** → **Video Decoder**.
3. Click the **Built-in Video Codec/DXVA Settings** button.
4. Configure the following options:
   - Check **Use DXVA**.
   - Under **Hardware acceleration (DXVA) settings**:
     - Check **Prioritize D3D11 DXVA** *(Recommended)* or set **DXVA2 Copy-Back:** to **`Auto (Recommended)`** / **`Always Use`**.
     - Set **Resolution limit:** to **`Always Use`**.
     - Verify hardware acceleration is enabled for **H.264/AVC1**, **H.265/HEVC**, and **VP9**.
5. Click **Apply**.

---

## Step 2: Video Renderer Configuration (Direct3D 11 Pipeline)

1. In **Preferences (`F5`)**, navigate to the main **Video** page *(do NOT use the sub-page Video → Resize)*.
2. Set **Video Renderer** to:
   - **`Built-in Direct3D 11 Video Renderer`** *(Recommended)*
3. **GPU Scaling Algorithm:**
   - Under **Video Output Settings**, directly below **Direct3D Presentation**, locate the **`Resizer:`** dropdown.
   - Select **`Shader Bicubic(A = -0.6)`** *(Recommended for crisp 1080p presentation)* or **`Shader Bilinear`** *(lowest GPU power)*.  
   *(GPU shader units execute scaling operations without touching the CPU).*
4. Click **Apply**.

---

## Step 3: Colorspace Pass-Through (Zero CPU Overhead)

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
5. Under **Load script:**, select your preferred Snapdragon 8cx Gen 3 / SQ3 script:
   - **Eco (Battery Saver):** [`Snapdragon-8cxGen3-Eco.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen3-Eco.avs)
   - **Balanced (Recommended):** [`Snapdragon-8cxGen3-Balanced.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen3-Balanced.avs)
   - **Max Quality:** [`Snapdragon-8cxGen3-MaxQuality.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen3-MaxQuality.avs)
6. Click **Apply** → **OK**.

> [!TIP]
> **Adreno 690 Direct3D 12 GPU Offload (`USE_GPU = true` - Experimental Preview)**  
> Set `USE_GPU = true` at the top of any 8cx Gen 3 script to engage the Adreno 690 compute shader (`mvtools2_d3d12.dll`). The 8cx Gen 3's 136 GB/s bus and 2.2 TFLOPS compute engine easily sustain 60fps with subpixel precision at low power.  
> *(Note: Direct3D 12 GPU offload is provided as an experimental preview; rendering fidelity and real-time performance are provided on a best-effort basis, with ARM64 CPU NEON remaining the recommended production default).*

> [!NOTE]
> **Hardware Display Refresh & VSync Timing on Snapdragon 8cx Gen 3**  
> Certain Snapdragon 8cx Gen 3 hardware platforms (such as the ThinkPad X13s or Surface Pro 9 5G) pair the Qualcomm display controller with an oscillator clock operating at approx. 59.8 Hz rather than an integer 60.00 Hz (even over certain external display connections). During strict 60.000 FPS video playback, an excess frame accumulates every 4 to 7 seconds and is discarded by the DXGI swapchain compositor (`DXGI_SWAP_EFFECT_FLIP_DISCARD`) to keep video playback synchronized with audio. These minor discards are confirmed hardware display scanout timing artifacts and do not indicate a CPU/GPU compute bottleneck (frame render latency remains under 0.5 ms).

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
| **AviSynth Script** | Video → AviSynth | [`Snapdragon-8cxGen3-Balanced.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-8cxGen3-Balanced.avs) |
