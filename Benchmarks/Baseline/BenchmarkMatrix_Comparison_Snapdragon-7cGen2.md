# MVTools Benchmark Comparison Matrix - Snapdragon-7cGen2

**Host Platform:** Snapdragon 7c Gen 2 (Kryo 468, Adreno 618)  
**Platform Identifier:** Snapdragon-7cGen2  
**Memory Environment:** Memory-Constrained Hardware (<= 4 GB RAM or low physical memory headroom)  
**PotPlayer Version:** 1.7.23122 (Build: 2026-09-01 19:30:50)  
**Benchmark Suite:** MvToolsBenchmarks-Compare.ps1 (v2.5.0)  
**Generated:** 2026-10-28 17:07:09  
**Reference Target:** tears_of_steel_1080p.mov  

| Tier | Motion Engine | Avg FPS | 1% Low FPS | 0.1% Low FPS | CPU Load (Avg/Peak) | GPU Load (Avg/Peak) | PotPlayer GPU | RAM Working Set | Dropped Frames |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **Eco** | CPU NEON | **60.00** | **53.02** | 51.95 | 11.2% / 12.6% | 53.2% / 54.0% | 45.3% | 229.4 MB | 0 frames |
| **Balanced** | CPU NEON | **59.99** | **54.58** | 52.46 | 11.0% / 12.7% | 51.0% / 52.2% | 42.6% | 227.9 MB | 0 frames |
| **MaxQuality** | CPU NEON | **60.01** | **54.65** | 52.12 | 10.8% / 12.7% | 51.3% / 52.3% | 42.5% | 228.0 MB | 1 frames |

> [!NOTE]
> **Engine Status:** ARM64 CPU NEON (mvtools2.dll) is the recommended production reference. Direct3D 12 GPU offload (mvtools2_d3d12.dll) is provided as an experimental preview; rendering fidelity and real-time performance are provided on a best-effort basis.

> [!NOTE]
> **Memory-Constrained Hardware Notice:** Benchmark telemetry for this platform was captured on a memory-constrained device (Yes (Total RAM: 3767 MB, Available: 1571 MB)). Microstutter metrics (1% and 0.1% Low FPS) and memory working sets should be interpreted with memory pressure in mind.

### Key Architectural Findings & Trade-Offs

1. **Eco Tier (Battery & Thermal Priority):**
   - **Frame Rate & Pacing:** Sustained **60.00 FPS** (1% Low: **53.02 FPS**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 11.2% (Peak: 12.6%) on native ARM64 NEON with working set of 229.4 MB.

2. **Balanced Tier (Recommended Daily Driver):**
   - **Frame Rate & Pacing:** Sustained **59.99 FPS** (1% Low: **54.58 FPS**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 11.0% (Peak: 12.7%) on native ARM64 NEON with working set of 227.9 MB.

3. **MaxQuality Tier (High-Fidelity Action & Detail):**
   - **Frame Rate & Pacing:** Sustained **60.01 FPS** (1% Low: **54.65 FPS**, Dropped: 1 frames).
   - **Compute Load:** System CPU averaged 10.8% (Peak: 12.7%) on native ARM64 NEON with working set of 228.0 MB.

### Platform Assessment & Profile Recommendation

- **Stability & Real-Time Headroom:** On **Snapdragon 7c Gen 2 (Kryo 468, Adreno 618)**, the **Balanced** tier sustained steady 60.00 fps with zero dropped presentation frames. In contrast, higher-complexity passes in [MaxQuality] exceeded real-time presentation budgets resulting in frame drops. **Balanced** is therefore the optimal daily recommendation for this SoC.
- **Memory-Constrained Hardware Headroom:** Benchmarks on this platform were executed on a memory-constrained device. To prevent Windows working-set compression and secondary SSD pagefile swapping during high-motion scenes, utilizing the **Eco** profile or conservative SetMemoryMax configurations is strongly recommended.
