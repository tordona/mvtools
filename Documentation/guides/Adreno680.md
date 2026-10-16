# Recommended PotPlayer iGPU (Adreno 680) Configuration Guide

> **Hardware Target:** Qualcomm Snapdragon 8cx Gen 2 5G (SC8180XP / Microsoft SQ2)  
> **Integrated GPU:** Qualcomm Adreno 680 (~1.3 TFLOPS FP32)  
> **CPU Topology:** 4x Kryo 495 Gold (Cortex-A76 @ up to 3.15 GHz) + 4x Kryo 495 Silver (Cortex-A55 @ up to 1.8 GHz)  
> **Thermal Profile:** 7W–10W Fanless Design *(e.g., Microsoft Surface Pro X, Lenovo Flex 5G, Samsung Galaxy Book S)*

---

## Overview

On the Qualcomm Snapdragon 8cx Gen 2, the CPU and Adreno 680 iGPU share a unified **7W to 10W fanless thermal envelope** and an 8-channel LPDDR4x-2133 memory bus (~68 GB/s). 

When performing real-time 60fps AviSynth motion interpolation (`mvtools2`), the 4 Kryo 495 Gold (Cortex-A76) performance cores are dedicated to NEON motion vector estimation. If video decoding or display scaling is executed on the CPU, the SoC quickly reaches its thermal ceiling, throttling CPU clocks and causing frame drops.

Offloading both **video decoding** and **display presentation** to the **Adreno 680 iGPU** preserves 100% of the CPU thermal budget for MVTools, ensuring smooth 60fps video playback with zero dropped frames.

---

## Step 1: Hardware Video Decoder Configuration (Adreno 680 VPU)

1. Open **PotPlayer** and press **`F5`** to open **Preferences**.
2. In the left navigation tree, go to:  
   **Filter Control** $\to$ **Video Decoder**.
3. Click the **Built-in Codec/DXVA Settings** button.
4. Configure the following options:
   - Check **Use DXVA / Hardware Acceleration**.
   - **Hardware Acceleration Mode:** Select **`D3D11`** *(Recommended)* or **`DXVA2 (Copy-Back)`**.
   - **DXVA Resolution:** Select **`Always Use`** (or `SD, HD, Full HD, UHD`).
   - Verify hardware acceleration is enabled for all supported codecs:
     - **H.264 / AVC**
     - **HEVC / H.265 (8-bit & 10-bit)**
     - **VP9**
5. Click **Apply**.

> [!IMPORTANT]
> **Why D3D11 / DXVA2 Copy-Back?**  
> AviSynth filters capture video frames directly from PotPlayer via `potplayer_source()`. D3D11 / DXVA2 Copy-Back decodes the compressed video stream inside the Adreno 680 Video Processing Unit (VPU) and transfers uncompressed planar frames into shared memory for MVTools, keeping CPU decoding load at **0%**.

---

## Step 2: Video Renderer Configuration (Adreno 680 Direct3D 11 Pipeline)

1. In **Preferences (`F5`)**, navigate to:  
   **Video**.
2. Set **Video Renderer** to:
   - **`Built-in Direct3D 11 Video Renderer`** *(Recommended)*  
     *(Alternative: `EVR Custom Presenter`)*
3. **Scaling Algorithm:**
   - Under **Resize**, select **`Bicubic`** or **`Bilinear`**.  
   *(Scaling and color presentation shaders are executed directly on the Adreno 680 shader cores without consuming CPU cycles).*
4. Click **Apply**.

---

## Step 3: Colorspace Pass-Through (Zero CPU Overhead)

Converting video frames between YUV and RGB on the CPU wastes memory bandwidth and CPU execution cycles.

1. In **Preferences (`F5`)**, navigate to:  
   **Video** $\to$ **Colorspaces**.
2. Ensure preferred output formats prioritize native planar YUV:
   - **`NV12`**
   - **`YV12`**
3. Ensure **Always use RGB32** is **Unchecked**.

---

## Step 4: AviSynth Processing & Script Activation

1. In **Preferences (`F5`)**, navigate to:  
   **Video** $\to$ **AviSynth**.
2. Check **Enable AviSynth Processing**.
3. **Buffer Management:**
   - **Buffer Ahead:** Set to **`24`** frames.
   - **Buffer Back:** Set to **`12`** to **`15`** frames.
4. Select your preferred Snapdragon 8cx Gen 2 script:
   - **Eco (Battery Saver):** [`Snapdragon-8cxGen2-Eco.avs`](../../AviSynth/Snapdragon-8cxGen2-Eco.avs)
   - **Balanced (Recommended):** [`Snapdragon-8cxGen2-Balanced.avs`](../../AviSynth/Snapdragon-8cxGen2-Balanced.avs)
   - **Max Quality:** [`Snapdragon-8cxGen2-MaxQuality.avs`](../../AviSynth/Snapdragon-8cxGen2-MaxQuality.avs)
5. Click **Apply** $\to$ **OK**.

> [!TIP]
> **The Thread Capping Rule (`Prefetch <= 4`)**  
> The Snapdragon 8cx Gen 2 features 4 out-of-order Kryo 495 Gold cores and 4 in-order Kryo 495 Silver cores. All provided 8cx Gen 2 scripts strictly cap `Prefetch` to **3 or 4 threads** so that MVTools runs exclusively on the Gold performance cores. Never increase `Prefetch` beyond 4, as dispatching work to the slow Silver cores will cause pipeline stalls and video stutter.

---

## Summary Configuration Checklist

| Setting | Location in Preferences (`F5`) | Recommended Value |
| :--- | :--- | :--- |
| **Hardware Video Decoding** | Filter Control $\to$ Video Decoder $\to$ Built-in Settings | `Enabled` |
| **Hardware Decode Mode** | Filter Control $\to$ Video Decoder $\to$ Built-in Settings | `D3D11` or `DXVA2 (Copy-Back)` |
| **Video Renderer** | Video | `Built-in Direct3D 11 Video Renderer` |
| **Output Colorspace** | Video $\to$ Colorspaces | `NV12` / `YV12` *(RGB conversion disabled)* |
| **AviSynth Processing** | Video $\to$ AviSynth | `Enabled` |
| **Buffer Ahead** | Video $\to$ AviSynth | `24` frames |
| **AviSynth Script** | Video $\to$ AviSynth | [`Snapdragon-8cxGen2-Balanced.avs`](../../AviSynth/Snapdragon-8cxGen2-Balanced.avs) |

---

## Verification & OSD Diagnostic

To verify that the Adreno 680 hardware decoder and 60fps interpolation are active during playback:

1. Open and play any 24fps/30fps video in PotPlayer.
2. Press **`Tab`** to toggle the On-Screen Display (OSD).
3. Confirm the following real-time metrics:
   - **Video Codec:** Displays **`D3D11 Native/CopyBack`** or **`DXVA2`** *(not Software / ffmpeg)*.
   - **Video Output:** Shows **`Direct3D 11 Video Renderer`**.
   - **Frame Rate:** Displays **`XX.XX fps -> 60.00 fps`**.
   - **CPU Usage:** Remains low and stable (typically 20%–35% across the Kryo 495 Gold cores).
