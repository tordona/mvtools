# Essential PotPlayer iGPU (Adreno 630) Configuration Guide

> **Hardware Target:** Qualcomm Snapdragon 850 (SD850 / SDM850)  
> **Integrated GPU:** Qualcomm Adreno 630  
> **Thermal Profile:** ~5W Fanless Design *(e.g., Lenovo Yoga C630, Samsung Galaxy Book2)*

---

## Overview

On the Qualcomm Snapdragon 850, software video decoding on the Kryo 385 Gold (Cortex-A75) CPU cores consumes **over 50% of the entire 5W package thermal budget**. When running real-time 60fps AviSynth frame interpolation (`mvtools2`), CPU-based decoding quickly causes thermal saturation, dropping core clocks from 2.96 GHz down to 1.5–1.8 GHz and causing dropped frames and stutter.

Offloading both **video decoding** and **display rendering/presentation** to the **Adreno 630 iGPU** eliminates CPU decode overhead (reducing it to ~0%), preserving the CPU cores and LPDDR4x-1866 bus exclusively for MVTools NEON vector estimation.

---

## Step 1: Hardware Video Decoder Configuration (Adreno 630 VPU)

1. Open **PotPlayer** and press **`F5`** to open **Preferences**.
2. In the left navigation tree, navigate to:  
   **Filter Control** $\to$ **Video Decoder**.
3. Click the **Built-in Codec/DXVA Settings** button.
4. Configure the following options:
   - Check **Use DXVA / Hardware Acceleration**.
   - **Hardware Acceleration Mode:** Select **`D3D11`** *(recommended)* or **`DXVA2 (Copy-Back)`**.
   - **DXVA Resolution:** Set to **`Always Use`** (or `SD, HD, Full HD, UHD`).
   - Ensure hardware acceleration is checked for:
     - **H.264 / AVC**
     - **HEVC / H.265 (8-bit & 10-bit)**
     - **VP9**
5. Click **Apply**.

> [!IMPORTANT]
> **Why Copy-Back / D3D11?**  
> AviSynth filters receive raw video frames from PotPlayer via `potplayer_source()`. D3D11 / DXVA2 Copy-Back decodes the compressed bitstream inside the Adreno 630 Video Processing Unit (VPU) and transfers the uncompressed planar surface back to system memory with zero CPU decode load.

---

## Step 2: Video Renderer Configuration (Adreno 630 Direct3D Pipeline)

1. In **Preferences (`F5`)**, navigate to:  
   **Video**.
2. Set **Video Renderer** to:
   - **`Built-in Direct3D 11 Video Renderer`** *(Recommended)*  
     *(Alternative: `EVR Custom Presenter`)*
3. **Scaling Algorithm:**
   - Under **Resize**, select **`Bilinear`** or **`Bicubic (Fast)`**.  
   *(GPU shader units execute scaling operations without touching the CPU).*
4. Click **Apply**.

---

## Step 3: Colorspace Pass-Through (Zero CPU Conversion)

Converting pixel formats (such as YV12/NV12 to RGB32) on the CPU adds massive memory copying and conversion overhead.

1. In **Preferences (`F5`)**, navigate to:  
   **Video** $\to$ **Colorspaces**.
2. Ensure the output format priority is set to planar YUV:
   - **`NV12`**
   - **`YV12`**
3. Verify that **Always use RGB32** is **Unchecked**.

---

## Step 4: AviSynth Processing & Script Activation

1. In **Preferences (`F5`)**, navigate to:  
   **Video** $\to$ **AviSynth**.
2. Check **Enable AviSynth Processing**.
3. **Buffer Management:**
   - **Buffer Ahead:** Set to **`20`** to **`24`** frames.
   - **Buffer Back:** Set to **`10`** to **`15`** frames.
4. Under the script selection, choose your preferred Snapdragon 850 profile:
   - **Eco (Battery Saver):** [`Snapdragon-850-Eco.avs`](../../AviSynth/Snapdragon-850-Eco.avs)
   - **Balanced (Recommended):** [`Snapdragon-850-Balanced.avs`](../../AviSynth/Snapdragon-850-Balanced.avs)
   - **Max Quality:** [`Snapdragon-850-MaxQuality.avs`](../../AviSynth/Snapdragon-850-MaxQuality.avs)
5. Click **Apply** $\to$ **OK**.

---

## Summary Configuration Checklist

| Setting | Location in Preferences (`F5`) | Recommended Value |
| :--- | :--- | :--- |
| **DXVA Hardware Decoding** | Filter Control $\to$ Video Decoder $\to$ Built-in Settings | `Enabled` |
| **DXVA Mode** | Filter Control $\to$ Video Decoder $\to$ Built-in Settings | `D3D11` or `DXVA2 (Copy-Back)` |
| **Video Renderer** | Video | `Built-in Direct3D 11 Video Renderer` |
| **Colorspace** | Video $\to$ Colorspaces | `NV12` / `YV12` *(RGB conversion disabled)* |
| **AviSynth Processing** | Video $\to$ AviSynth | `Enabled` |
| **Buffer Ahead** | Video $\to$ AviSynth | `20` – `24` |
| **AviSynth Script** | Video $\to$ AviSynth | [`Snapdragon-850-Balanced.avs`](../../AviSynth/Snapdragon-850-Balanced.avs) |

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
