# MVTools Benchmark Comparison Matrix - Intel-Processor-N100

**Host Platform:** Intel Processor N100 (4C/4T Gracemont @ 6 W TDP, Intel UHD Graphics 24EU)  
**Platform Identifier:** Intel-Processor-N100  
**PotPlayer Version:** 1.7.23164 (Build: 2026-10-23 02:59:00)  
**Benchmark Suite:** MvToolsBenchmarks-Compare.ps1 (v2.4.1)  
**Generated:** 2026-10-25 12:37:07  
**Reference Target:** tears_of_steel_1080p.mov  

| Tier | Motion Engine | Avg FPS | 1% Low FPS | 0.1% Low FPS | CPU Load (Avg/Peak) | GPU Load (Avg/Peak) | PotPlayer GPU | RAM Working Set | Dropped Frames |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **Eco** | CPU SIMD | **60.00** | **55.61** | 54.47 | 37.3% / 43.9% | 38.3% / 39.6% | 38.3% | 265.9 MB | 0 frames |
| **Balanced** | CPU SIMD | **60.00** | **55.35** | 54.08 | 42.3% / 45.4% | 38.5% / 40.1% | 38.5% | 279.7 MB | 0 frames |
| **MaxQuality** | CPU SIMD | **60.00** | **54.79** | 54.03 | 63.6% / 67.8% | 37.4% / 39.7% | 37.4% | 293.7 MB | 0 frames |

> [!NOTE]
> **Engine Status:** x64 CPU SIMD (mvtools2.dll) is the active production motion estimation engine on x64 platforms.

### Key Architectural Findings & Trade-Offs

1. **Eco Tier (Battery & Thermal Priority):**
   - **Frame Rate & Pacing:** Sustained **60.00 fps** (1% Low: **55.61 fps**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 37.3% (Peak: 43.9%) on x64 CPU SIMD with working set of 265.9 MB.

2. **Balanced Tier (Recommended Daily Driver):**
   - **Frame Rate & Pacing:** Sustained **60.00 fps** (1% Low: **55.35 fps**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 42.3% (Peak: 45.4%) on x64 CPU SIMD with working set of 279.7 MB.

3. **MaxQuality Tier (High-Fidelity Action & Detail):**
   - **Frame Rate & Pacing:** Sustained **60.00 fps** (1% Low: **54.79 fps**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 63.6% (Peak: 67.8%) on x64 CPU SIMD with working set of 293.7 MB.

### Platform Assessment & Profile Recommendation

- **Stability & Real-Time Headroom:** All evaluated tiers sustained real-time 60.00 fps with zero dropped presentation frames on **Intel Processor N100 (4C/4T Gracemont @ 6 W TDP, Intel UHD Graphics 24EU)**. **Eco** minimized CPU compute load (37.3%), while **Eco** delivered the smoothest frame consistency (55.61 fps 1% low).
- **Display Hardware Refresh Rate Impact:** Telemetry indicates this platform's physical panel scans at **59.98 Hz** (Primary Display (59.984 Hz, 14780000/246400)). Across the evaluated duration, presentation synchronized continuously without accumulating frame discards.
