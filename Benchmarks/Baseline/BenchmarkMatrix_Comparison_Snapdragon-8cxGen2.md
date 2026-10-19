# MVTools Benchmark Comparison Matrix - Snapdragon-8cxGen2

**Host Platform:** Snapdragon 8cx Gen 2 / SQ2 (Kryo 495, Adreno 680)  
**Platform Identifier:** Snapdragon-8cxGen2  
**PotPlayer Version:** 1.7.23122 (Build: 2026-09-01 19:30:50)  
**Benchmark Suite:** MvToolsBenchmarks-Compare.ps1 (v2.1.0)  
**Generated:** 2026-10-19 10:32:10  
**Reference Target:** 1080p 24fps -> 60fps Interpolation  

| Tier | Motion Engine | Avg FPS | 1% Low FPS | 0.1% Low FPS | CPU Load (Avg/Peak) | GPU Load (Avg/Peak) | PotPlayer GPU | RAM Working Set | Dropped Frames |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **Eco** | CPU NEON | **60.00** | **53.09** | 51.76 | 16.7% / 44.0% | 23.8% / 25.3% | 19.4% | 298.7 MB | 1 frames |
| **Eco** | D3D12 GPU | **60.00** | **53.68** | 52.05 | 10.9% / 18.8% | 65.2% / 73.5% | 62.7% | 314.5 MB | 0 frames |
| **Balanced** | CPU NEON | **60.00** | **53.45** | 51.52 | 13.5% / 15.6% | 23.9% / 25.7% | 19.5% | 317.0 MB | 0 frames |
| **Balanced** | D3D12 GPU | **60.00** | **53.85** | 52.39 | 12.7% / 15.1% | 65.8% / 77.3% | 63.4% | 323.5 MB | 0 frames |
| **MaxQuality** | CPU NEON | **59.99** | **53.74** | 52.51 | 23.6% / 25.7% | 23.9% / 25.7% | 19.5% | 363.6 MB | 1 frames |
| **MaxQuality** | D3D12 GPU | **60.00** | **53.65** | 52.02 | 18.3% / 26.6% | 67.9% / 80.6% | 65.4% | 343.1 MB | 0 frames |

> [!NOTE]
> **Engine Status:** ARM64 CPU NEON (mvtools2.dll) is the recommended production reference. Direct3D 12 GPU offload (mvtools2_d3d12.dll) is provided as an experimental preview; rendering fidelity and real-time performance are provided on a best-effort basis.

### Key Architectural Findings & Trade-Offs

1. **Eco Tier (Battery & Thermal Priority):**
   - **Configuration:** Full native analysis, 32x32 blocks, pel=1 (integer pixel), Fast block projection (mode=0) | Target: 7W Fanless Thermal Envelope, Maximum Battery Life, 0 Dropped Frames
   - **Frame Rate & Pacing:** Average FPS: CPU NEON **60.00 FPS** (1 frames) vs D3D12 GPU **60.00 FPS** (0 frames). 1% Lows: CPU NEON **53.09 FPS** vs D3D12 GPU **53.68 FPS**.
   - **Compute Offload:** D3D12 GPU offload reduced system CPU load by **5.8%** (from 16.7% down to 10.9%), utilizing 62.7% Adreno GPU compute.
   - **Memory Footprint:** PotPlayer working set: 298.7 MB (CPU) vs 314.5 MB (D3D12 GPU).

2. **Balanced Tier (Recommended Daily Driver):**
   - **Configuration:** Full native analysis, Dual-pass 32x32 -> 16x16, pel=1 (integer pixel), Pixel-flow synthesis (mode=2) | Target: Fluid 1080p 60fps, Sharp Edge Tracking, Stable Thermal Ceiling
   - **Frame Rate & Pacing:** Both engines sustained a solid **60.00 FPS** with 0 dropped presentation frames. 1% Lows: CPU NEON **53.45 FPS** vs D3D12 GPU **53.85 FPS**.
   - **Compute Offload:** D3D12 GPU offload reduced system CPU load by **0.8%** (from 13.5% down to 12.7%), utilizing 63.4% Adreno GPU compute.
   - **Memory Footprint:** PotPlayer working set: 317.0 MB (CPU) vs 323.5 MB (D3D12 GPU).

3. **MaxQuality Tier (High-Fidelity Action & Detail):**
   - **Configuration:** Full native analysis, Dual-pass 16x16 -> 8x8 (CPU) / 32x32 -> 16x16 (GPU), pel=2 (CPU half-pixel) / pel=1 (GPU integer), Pixel-flow synthesis (mode=2) | Target: Highest Achievable Quality within 8cx Gen 2 Thermal Ceiling
   - **Frame Rate & Pacing:** Average FPS: CPU NEON **59.99 FPS** (1 frames) vs D3D12 GPU **60.00 FPS** (0 frames). 1% Lows: CPU NEON **53.74 FPS** vs D3D12 GPU **53.65 FPS**.
   - **Compute Offload:** D3D12 GPU offload reduced system CPU load by **5.3%** (from 23.6% down to 18.3%), utilizing 65.4% Adreno GPU compute.
   - **Memory Footprint:** PotPlayer working set: 363.6 MB (CPU) vs 343.1 MB (D3D12 GPU).

### Platform Assessment & Profile Recommendation

- **Stability & Real-Time Headroom:** On **Snapdragon 8cx Gen 2 / SQ2 (Kryo 495, Adreno 680)**, the **Balanced** tier sustained steady 60.00 FPS with zero dropped presentation frames. In contrast, higher-complexity passes in [Eco, MaxQuality] exceeded real-time presentation budgets resulting in frame drops. **Balanced** is therefore the optimal daily recommendation for this SoC.
- **Compute Engine Trade-Off:** ARM64 CPU NEON remains the recommended production baseline for deterministic frame pacing and artifact-free presentation. Direct3D 12 GPU offload transfers motion vector search to the Adreno GPU compute shaders, freeing CPU headroom for background multi-tasking.
