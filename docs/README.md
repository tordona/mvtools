# MVTools2 — Windows on ARM64 & Snapdragon 60fps Hub

> **Documentation and profile hub for native ARM64 NEON & Direct3D 12 GPU motion interpolation in Daum PotPlayer on Windows on ARM.**

![MVTools2 Banner](images/social-preview-flat.jpg)

---

## Welcome to the Documentation Hub

**MVTools2** is a motion estimation and compensation plugin for AviSynth+ and the AviSynth v2.6 family, providing **real-time 24fps → 60fps motion interpolation** in media players like Daum PotPlayer without dropped frames.

This documentation hub covers the key architectural additions developed in this fork:
* **Native Windows on ARM64 Port:** Pure 64-bit ARM assembly (`ARM64 NEON`) with zero x86 emulation overhead.
* **Experimental Direct3D 12 GPU Offload:** DirectCompute shader acceleration (`mvtools2_d3d12.dll`).
* **18 Tuned Snapdragon Profiles:** Empirically verified `.avs` scripts with single-level geometry (`levels=1`) preserving memory bus bandwidth.
* **PresentMon Benchmark Test Suite:** Sub-millisecond ETW frame pacing capture with automated swapchain duplication detection.
* **AI Agent Auto-Tuning Guide:** Standardized 1-step prompt and diagnostic decision matrix for autonomous tuning.

---

## 📱 Hardware Guides by Qualcomm Snapdragon SoC

Step-by-step PotPlayer hardware decoding (D3D11 Copy-Back), video renderer selection, and profile configuration for each Qualcomm Snapdragon generation:

| SoC Platform | Target Hardware / Devices | Verified Profiles | Hardware Setup Guide |
| :--- | :--- | :--- | :---: |
| **Snapdragon X Elite / Plus** | Surface Pro 11, Galaxy Book4 Edge, Dell XPS 13 | `Eco`, `Balanced`, `MaxQuality` | [View Guide ➔](guides/SnapdragonXPlus.md) |
| **Snapdragon 8cx Gen 3 / SQ3** | Lenovo ThinkPad X13s, Surface Pro 9 5G | `Eco`, `Balanced`, `MaxQuality` | [View Guide ➔](guides/Snapdragon8cxGen3.md) |
| **Snapdragon 8cx Gen 2 / SQ2** | Microsoft Surface Pro X SQ2 | `Eco`, `Balanced`, `MaxQuality` | [View Guide ➔](guides/Snapdragon8cxGen2.md) |
| **Snapdragon 8cx Gen 1 / SQ1** | Microsoft Surface Pro X SQ1 | `Eco`, `Balanced`, `MaxQuality` | [View Guide ➔](guides/Snapdragon8cxGen1.md) |
| **Snapdragon 850** | Samsung Galaxy Book2, Lenovo Yoga C630 | `Eco`, `Balanced`, `MaxQuality` | [View Guide ➔](guides/Snapdragon850.md) |
| **Snapdragon 7c Gen 2** | Samsung Galaxy Book Go (Fanless 4GB) | `Eco`, `Balanced`, `MaxQuality` | [View Guide ➔](guides/Snapdragon7cGen2.md) |

---

## ⚡ Core Sections

* [**Quick Start Setup Guide**](quickstart.md)  
  Get up and running with 60fps video interpolation in PotPlayer in under 3 minutes.

* [**AviSynth Profile Library**](profiles/README.md)  
  Explore all 18 Snapdragon profiles (`Eco`, `Balanced`, `MaxQuality`), inspect parameter settings, and copy `.avs` scripts directly.

* [**Benchmark & Telemetry Suite**](benchmarks/README.md)  
  Learn how to run `MvToolsBenchmark-Start.ps1`, measure PresentMon ETW 1% Low frame pacing, detect swapchain frame duplication, and compare baseline results.

* [**AI Agent Profiling Guide**](guides/AIAgentProfileGuide.md)  
  Use Google Antigravity, Gemini, Cursor, or Claude to auto-detect hardware and tune custom profiles in an autonomous closed loop.

---

## 📦 Binaries & Downloads

Download official pre-compiled releases from the [GitHub Releases Page](https://github.com/tordona/mvtools/releases):
* **`mvtools2.dll`** *(Production Reference)*: Native ARM64 NEON SIMD engine for daily viewing and deterministic 60fps frame delivery.
* **`mvtools2_d3d12.dll`** *(Experimental Preview)*: Direct3D 12 DirectCompute GPU-accelerated engine.
