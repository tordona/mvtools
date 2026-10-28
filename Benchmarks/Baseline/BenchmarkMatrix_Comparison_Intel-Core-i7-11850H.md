# MVTools Benchmark Comparison Matrix - Intel-Core-i7-11850H

**Host Platform:** Intel Core i7-11850H (8C/16T Tiger Lake-H @ 45 W TDP, Intel UHD Graphics 32EU)  
**Platform Identifier:** Intel-Core-i7-11850H  
**PotPlayer Version:** 1.7.23164 (Build: 2026-10-23 02:59:00)  
**Benchmark Suite:** MvToolsBenchmarks-Compare.ps1 (v2.4.1)  
**Generated:** 2026-10-25 14:06:27  
**Reference Target:** tears_of_steel_1080p.mov  

| Tier | Motion Engine | Avg FPS | 1% Low FPS | 0.1% Low FPS | CPU Load (Avg/Peak) | GPU Load (Avg/Peak) | PotPlayer GPU | RAM Working Set | Dropped Frames |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **Eco** | CPU SIMD | **60.00** | **54.58** | 53.77 | 3.8% / 4.1% | 22.1% / 22.4% | 22.0% | 303.8 MB | 0 frames |
| **Balanced** | CPU SIMD | **60.00** | **54.68** | 53.96 | 4.5% / 4.8% | 22.7% / 23.1% | 22.6% | 321.3 MB | 0 frames |
| **MaxQuality** | CPU SIMD | **60.00** | **54.84** | 54.40 | 6.5% / 6.9% | 23.7% / 24.0% | 23.6% | 376.7 MB | 0 frames |

> [!NOTE]
> **Engine Status:** x64 CPU SIMD (mvtools2.dll) is the active production motion estimation engine on x64 platforms.

### Key Architectural Findings & Trade-Offs

1. **Eco Tier (Battery & Thermal Priority):**
   - **Frame Rate & Pacing:** Sustained **60.00 fps** (1% Low: **54.58 fps**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 3.8% (Peak: 4.1%) on x64 CPU SIMD with working set of 303.8 MB.

2. **Balanced Tier (Recommended Daily Driver):**
   - **Frame Rate & Pacing:** Sustained **60.00 fps** (1% Low: **54.68 fps**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 4.5% (Peak: 4.8%) on x64 CPU SIMD with working set of 321.3 MB.

3. **MaxQuality Tier (High-Fidelity Action & Detail):**
   - **Frame Rate & Pacing:** Sustained **60.00 fps** (1% Low: **54.84 fps**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 6.5% (Peak: 6.9%) on x64 CPU SIMD with working set of 376.7 MB.

### Platform Assessment & Profile Recommendation

- **Stability & Real-Time Headroom:** All evaluated tiers sustained real-time 60.00 fps with zero dropped presentation frames on **Intel Core i7-11850H (8C/16T Tiger Lake-H @ 45 W TDP, Intel UHD Graphics 32EU)**. **Eco** minimized CPU compute load (3.8%), while **MaxQuality** delivered the smoothest frame consistency (54.84 fps 1% low).
- **Display Hardware Refresh Rate Impact:** Telemetry indicates this platform's physical panel scans at **60.00 Hz** (Primary Display (60.003 Hz, 13866000/231088)). Across the evaluated duration, presentation synchronized continuously without accumulating frame discards.
