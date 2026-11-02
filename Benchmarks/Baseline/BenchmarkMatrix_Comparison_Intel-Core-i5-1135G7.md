# MVTools Benchmark Comparison Matrix - Intel-Core-i5-1135G7

**Host Platform:** Intel Core i5-1135G7 (4C/8T Tiger Lake-U @ 12 W TDP, Intel Iris Xe Graphics 80EU)  
**Platform Identifier:** Intel-Core-i5-1135G7  
**PotPlayer Version:** 1.7.23164 (Build: 2026-10-23 02:59:00)  
**Benchmark Suite:** MvToolsBenchmarks-Compare.ps1 (v2.4.1)  
**Generated:** 2026-10-25 12:37:07  
**Reference Target:** tears_of_steel_1080p.mov  

| Tier | Motion Engine | Avg FPS | 1% Low FPS | 0.1% Low FPS | CPU Load (Avg/Peak) | GPU Load (Avg/Peak) | PotPlayer GPU | RAM Working Set | Dropped Frames |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **Eco** | CPU SIMD | **60.00** | **55.32** | 53.40 | 4.9% / 5.3% | 22.9% / 23.9% | 22.9% | 282.0 MB | 0 frames |
| **Balanced** | CPU SIMD | **60.00** | **54.22** | 53.75 | 6.2% / 6.4% | 22.9% / 23.7% | 22.9% | 291.3 MB | 0 frames |
| **MaxQuality** | CPU SIMD | **60.00** | **54.79** | 53.68 | 10.5% / 11.0% | 23.1% / 24.1% | 23.1% | 310.9 MB | 0 frames |

> [!NOTE]
> **Engine Status:** x64 CPU SIMD (mvtools2.dll) is the active production motion estimation engine on x64 platforms.

### Key Architectural Findings & Trade-Offs

1. **Eco Tier (Battery & Thermal Priority):**
   - **Frame Rate & Pacing:** Sustained **60.00 fps** (1% Low: **55.32 fps**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 4.9% (Peak: 5.3%) on x64 CPU SIMD with working set of 282.0 MB.

2. **Balanced Tier (Recommended Daily Driver):**
   - **Frame Rate & Pacing:** Sustained **60.00 fps** (1% Low: **54.22 fps**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 6.2% (Peak: 6.4%) on x64 CPU SIMD with working set of 291.3 MB.

3. **MaxQuality Tier (High-Fidelity Action & Detail):**
   - **Frame Rate & Pacing:** Sustained **60.00 fps** (1% Low: **54.79 fps**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 10.5% (Peak: 11.0%) on x64 CPU SIMD with working set of 310.9 MB.

### Platform Assessment & Profile Recommendation

- **Stability & Real-Time Headroom:** All evaluated tiers sustained real-time 60.00 fps with zero dropped presentation frames on **Intel Core i5-1135G7 (4C/8T Tiger Lake-U @ 12 W TDP, Intel Iris Xe Graphics 80EU)**. **Eco** minimized CPU compute load (4.9%), while **Eco** delivered the smoothest frame consistency (55.32 fps 1% low).
- **Display Hardware Refresh Rate Impact:** Telemetry indicates this platform's physical panel scans at **59.96 Hz** (Primary Display (59.959 Hz, 32575000/543289)). Across the evaluated duration, presentation synchronized continuously without accumulating frame discards.
