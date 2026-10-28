# MVTools Benchmark Comparison Matrix - Intel-Core-i5-8259U

**Host Platform:** Intel Core i5-8259U (4C/8T Coffee Lake-U @ 28 W TDP, Intel Iris Plus Graphics 655)  
**Platform Identifier:** Intel-Core-i5-8259U  
**PotPlayer Version:** 1.7.23164 (Build: 2026-10-23 02:59:00)  
**Benchmark Suite:** MvToolsBenchmarks-Compare.ps1 (v2.4.1)  
**Generated:** 2026-10-25 14:06:27  
**Reference Target:** tears_of_steel_1080p.mov  

| Tier | Motion Engine | Avg FPS | 1% Low FPS | 0.1% Low FPS | CPU Load (Avg/Peak) | GPU Load (Avg/Peak) | PotPlayer GPU | RAM Working Set | Dropped Frames |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **Eco** | CPU SIMD | **60.00** | **55.38** | 54.77 | 12.9% / 24.9% | 23.8% / 25.0% | 23.7% | 272.6 MB | 0 frames |
| **Balanced** | CPU SIMD | **60.00** | **54.72** | 53.02 | 15.1% / 25.7% | 23.6% / 24.7% | 23.5% | 285.7 MB | 0 frames |
| **MaxQuality** | CPU SIMD | **60.00** | **55.09** | 52.70 | 28.1% / 30.2% | 20.0% / 20.3% | 19.9% | 305.2 MB | 0 frames |

> [!NOTE]
> **Engine Status:** x64 CPU SIMD (mvtools2.dll) is the active production motion estimation engine on x64 platforms.

### Key Architectural Findings & Trade-Offs

1. **Eco Tier (Battery & Thermal Priority):**
   - **Frame Rate & Pacing:** Sustained **60.00 fps** (1% Low: **55.38 fps**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 12.9% (Peak: 24.9%) on x64 CPU SIMD with working set of 272.6 MB.

2. **Balanced Tier (Recommended Daily Driver):**
   - **Frame Rate & Pacing:** Sustained **60.00 fps** (1% Low: **54.72 fps**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 15.1% (Peak: 25.7%) on x64 CPU SIMD with working set of 285.7 MB.

3. **MaxQuality Tier (High-Fidelity Action & Detail):**
   - **Frame Rate & Pacing:** Sustained **60.00 fps** (1% Low: **55.09 fps**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 28.1% (Peak: 30.2%) on x64 CPU SIMD with working set of 305.2 MB.

### Platform Assessment & Profile Recommendation

- **Stability & Real-Time Headroom:** All evaluated tiers sustained real-time 60.00 fps with zero dropped presentation frames on **Intel Core i5-8259U (4C/8T Coffee Lake-U @ 28 W TDP, Intel Iris Plus Graphics 655)**. **Eco** minimized CPU compute load (12.9%), while **Eco** delivered the smoothest frame consistency (55.38 fps 1% low).
- **Display Hardware Refresh Rate Impact:** Telemetry indicates this platform's physical panel scans at **60.00 Hz** (Primary Display (59.999 Hz, 218540000/3642400)). Across the evaluated duration, presentation synchronized continuously without accumulating frame discards.
