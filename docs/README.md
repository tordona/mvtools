# MVTools2 — Windows on ARM64 60 fps Hub

> **Documentation and profile hub for native ARM64 NEON & Direct3D 12 GPU motion interpolation in Daum PotPlayer on Windows on ARM.**

![MVTools2 Banner](images/social-preview-flat.jpg)

---

## Welcome to the Documentation Hub

**MVTools2** is a motion estimation and compensation plugin for AviSynth+ and the AviSynth v2.6 family, providing **real-time 24 fps → 60 fps motion interpolation** in media players like Daum PotPlayer without dropped frames.

This documentation hub covers the key architectural additions developed in this fork:
* **Native Windows on ARM64 Port:** Pure 64-bit ARM assembly (`ARM64 NEON`) with zero x86 emulation overhead.
* **Experimental Direct3D 12 GPU Offload:** DirectCompute shader acceleration (`MEnableD3D12(true)`).
* **24 Tuned Windows on ARM64 Profiles:** Hardware-tailored `.avs` scripts for NVIDIA RTX Spark and Qualcomm Snapdragon platforms with single-level geometry (`levels=1`) preserving memory bus bandwidth.
* **PresentMon Benchmark Test Suite:** Sub-millisecond ETW frame pacing capture with automated swapchain duplication detection.
* **AI Agent Auto-Tuning Guide:** Standardized 1-step prompt and diagnostic decision matrix for autonomous tuning.
* **CPU Core Affinity Isolation:** Companion `AvsAffinity.dll` (`PinWorkerThreads`) filter restricting AviSynth+ worker threads to Performance cores on hybrid architectures.

---

## 📱 Hardware Guides by Windows on ARM64 Platform

Step-by-step PotPlayer hardware decoding (D3D11 Copy-Back), video renderer selection, and profile configuration across Windows on ARM64 platforms:

### NVIDIA RTX Spark (ARM64)

| Platform | Target Hardware / Cores / GPU | Tuned Profiles | Hardware Setup Guide |
| :--- | :--- | :--- | :---: |
| **RTX Spark N1X** | 9–10x Cortex-X925 + 9–10x A725 / Blackwell RTX (6,144 CUDA) | `Eco`, `Balanced`, `MaxQuality` | [View Guide ➔](guides/RTXSparkN1X.md) |

### Qualcomm Snapdragon (ARM64)

| SoC Platform | Target Hardware / Devices | Tuned Profiles | Hardware Setup Guide |
| :--- | :--- | :--- | :---: |
| **Snapdragon X2 Series** | 3rd-Gen Oryon (18C / 12C / 10C / 6C), Adreno X2 | `Eco`, `Balanced`, `MaxQuality` | [View Guide ➔](guides/SnapdragonX2.md) |
| **Snapdragon X Series** | Surface Pro 11, Galaxy Book4 Edge, Dell XPS 13 | `Eco`, `Balanced`, `MaxQuality` | [View Guide ➔](guides/SnapdragonX.md) |
| **Snapdragon 8cx Gen 3 / SQ3** | Lenovo ThinkPad X13s, Surface Pro 9 5G | `Eco`, `Balanced`, `MaxQuality` | [View Guide ➔](guides/Snapdragon8cxGen3.md) |
| **Snapdragon 8cx Gen 2 / SQ2** | Microsoft Surface Pro X SQ2 | `Eco`, `Balanced`, `MaxQuality` | [View Guide ➔](guides/Snapdragon8cxGen2.md) |
| **Snapdragon 8cx Gen 1 / SQ1** | Microsoft Surface Pro X SQ1 | `Eco`, `Balanced`, `MaxQuality` | [View Guide ➔](guides/Snapdragon8cxGen1.md) |
| **Snapdragon 850** | Samsung Galaxy Book2, Lenovo Yoga C630 | `Eco`, `Balanced`, `MaxQuality` | [View Guide ➔](guides/Snapdragon850.md) |
| **Snapdragon 7c Gen 2** | Samsung Galaxy Book Go (Fanless 4 GB) | `Eco`, `Balanced`, `MaxQuality` | [View Guide ➔](guides/Snapdragon7cGen2.md) |

---

## ⚡ Core Sections

* [**Quick Start Setup Guide**](quickstart.md)  
  Get up and running with 60 fps video interpolation in PotPlayer in under 3 minutes.

* [**AviSynth+ Profile Library**](profiles/README.md)  
  Explore all 24 Windows on ARM64 profiles (NVIDIA / Qualcomm) plus x86-64 profiles (AMD / Intel), inspect parameter settings, and copy `.avs` scripts directly.

* [**Benchmark & Telemetry Suite**](benchmarks/README.md)  
  Learn how to run `MvToolsBenchmark-Start.ps1`, measure PresentMon ETW 1% Low frame pacing, detect swapchain frame duplication, and compare baseline results.

* [**Custom Profiles Quickstart**](guides/GenerateCustomProfiles.md)  
  Generate custom 60 fps AviSynth profiles for use in PotPlayer in seconds with an AI assistant (no Git or cloning required).

* [**AI Agent Profile Tuning & Specification Guide**](guides/AIAgentProfileGuide.md)  
  Full architectural specification and closed-loop PresentMon benchmark tuning instructions for AI agents and performance engineers.

---

## 📦 Binaries & Downloads

Download official pre-compiled releases from the [GitHub Releases Page](https://github.com/tordona/mvtools/releases):
* **`mvtools2.dll`** : Native ARM64 NEON SIMD engine for daily viewing and deterministic 60 fps frame delivery.
* **`AvsAffinity.dll`** : Companion filter restricting AviSynth worker threads to Performance cores on hybrid architectures.