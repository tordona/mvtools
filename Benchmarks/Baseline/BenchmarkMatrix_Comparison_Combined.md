# MVTools Multi-Platform Benchmark Summary

**Generated:** 2026-10-25 13:11:30  
**Benchmark Suite:** MvToolsBenchmarks-Compare.ps1 (v2.4.1)  
**Reference Target:** 1080p 24fps -> 60fps Interpolation  
**Platforms Evaluated:** AMD-Ryzen-AI-5-340, Intel-Processor-N100, Intel-Core-i5-1135G7, Intel-Core-i3-1215U, Generic-x86-64-Core-i5-7Y54-CPU---1-20GHz--Intel-HD-Graphics-615, Generic-x86-64-Pentium-Silver-N5030-CPU---1-10GHz--Intel-UHD-Graphics-605, Snapdragon-X-Plus, Snapdragon-8cxGen2, Snapdragon-8cxGen3, Snapdragon-850, Snapdragon-7cGen2, Snapdragon-8cxGen1  

## Cross-Platform Recommended Daily Driver Matrix (Balanced Tier)

| Platform | Engine | Avg FPS | 1% Low FPS | CPU Load (Avg/Peak) | GPU Load (Avg/Peak) | Dropped Frames | Dedicated Matrix |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **AMD Ryzen AI 5 340 (3x Zen 5 + 3x Zen 5c Cores, Radeon 840M RDNA 3.5 @ 2.9 GHz)** | CPU SIMD | **59.90** | **52.23** | 10.7% / 13.2% | 40.8% / 41.3% | 0 frames | [AMD-Ryzen-AI-5-340 Matrix](BenchmarkMatrix_Comparison_AMD-Ryzen-AI-5-340.md) |
| **Intel Processor N100 (4C/4T Gracemont @ 6W TDP, Intel UHD Graphics 24EU)** | CPU SIMD | **60.00** | **55.35** | 42.3% / 45.4% | 38.5% / 40.1% | 0 frames | [Intel-Processor-N100 Matrix](BenchmarkMatrix_Comparison_Intel-Processor-N100.md) |
| **Intel Core i5-1135G7 (4C/8T Tiger Lake-U @ 12W TDP, Intel Iris Xe Graphics 80EU)** | CPU SIMD | **60.00** | **54.22** | 6.2% / 6.4% | 22.9% / 23.7% | 0 frames | [Intel-Core-i5-1135G7 Matrix](BenchmarkMatrix_Comparison_Intel-Core-i5-1135G7.md) |
| **Intel Core i3-1215U (2P+4E/8T Alder Lake-U @ 15W TDP, Intel UHD Graphics 64EU)** | CPU SIMD | **60.00** | **55.13** | 20.8% / 22.4% | 55.1% / 56.1% | 0 frames | [Intel-Core-i3-1215U Matrix](BenchmarkMatrix_Comparison_Intel-Core-i3-1215U.md) |
| **Generic x86-64 (Intel(R) Core(TM) i5-7Y54 CPU @ 1.20GHz, Intel(R) HD Graphics 615)** | CPU SIMD | **60.00** | **55.09** | 24.4% / 26.5% | 46.2% / 47.1% | 0 frames | [Generic-x86-64-Core-i5-7Y54-CPU---1-20GHz--Intel-HD-Graphics-615 Matrix](BenchmarkMatrix_Comparison_Generic-x86-64-Core-i5-7Y54-CPU---1-20GHz--Intel-HD-Graphics-615.md) |
| **Generic x86-64 (Intel(R) Pentium(R) Silver N5030 CPU @ 1.10GHz, Intel(R) UHD Graphics 605)** | CPU SIMD | **59.97** | **54.50** | 59.2% / 65.2% | 100.5% / 113.3% | 31 frames | [Generic-x86-64-Pentium-Silver-N5030-CPU---1-10GHz--Intel-UHD-Graphics-605 Matrix](BenchmarkMatrix_Comparison_Generic-x86-64-Pentium-Silver-N5030-CPU---1-10GHz--Intel-UHD-Graphics-605.md) |
| **Snapdragon X Plus (Qualcomm Oryon CPU, Adreno X1 GPU)** | CPU NEON | **60.00** | **53.02** | 7.3% / 10.7% | 29.3% / 32.4% | 0 (DWM Composed: Flip presentation) | [Snapdragon-X-Plus Matrix](BenchmarkMatrix_Comparison_Snapdragon-X-Plus.md) |
| **Snapdragon X Plus (Qualcomm Oryon CPU, Adreno X1 GPU)** | D3D12 GPU | **60.00** | **54.11** | 21.5% / 23.0% | 76.6% / 79.2% | 47 frames | [Snapdragon-X-Plus Matrix](BenchmarkMatrix_Comparison_Snapdragon-X-Plus.md) |
| **Snapdragon 8cx Gen 2 / SQ2 (Kryo 495, Adreno 680)** | CPU NEON | **60.00** | **53.45** | 13.5% / 15.6% | 23.9% / 25.7% | 0 frames | [Snapdragon-8cxGen2 Matrix](BenchmarkMatrix_Comparison_Snapdragon-8cxGen2.md) |
| **Snapdragon 8cx Gen 2 / SQ2 (Kryo 495, Adreno 680)** | D3D12 GPU | **60.00** | **53.85** | 12.7% / 15.1% | 65.8% / 77.3% | 0 frames | [Snapdragon-8cxGen2 Matrix](BenchmarkMatrix_Comparison_Snapdragon-8cxGen2.md) |
| **Snapdragon 8cx Gen 3 (Kryo Cortex-X1/A78, Adreno 690)** | CPU NEON | **60.00** | **54.57** | 7.0% / 8.2% | 12.6% / 13.9% | 2 frames | [Snapdragon-8cxGen3 Matrix](BenchmarkMatrix_Comparison_Snapdragon-8cxGen3.md) |
| **Snapdragon 8cx Gen 3 (Kryo Cortex-X1/A78, Adreno 690)** | D3D12 GPU | **60.00** | **54.47** | 6.4% / 14.2% | 41.9% / 43.6% | 5 frames | [Snapdragon-8cxGen3 Matrix](BenchmarkMatrix_Comparison_Snapdragon-8cxGen3.md) |
| **Snapdragon 850 (Kryo 385, Adreno 630)** | CPU NEON | **60.00** | **54.09** | 14.9% / 16.2% | 53.3% / 54.6% | 0 frames | [Snapdragon-850 Matrix](BenchmarkMatrix_Comparison_Snapdragon-850.md) |
| **Snapdragon 7c Gen 2 (Kryo 468, Adreno 618) *(Memory-Constrained)*** | CPU NEON | **60.00** | **53.56** | 12.0% / 13.4% | 51.3% / 52.1% | 1 frames | [Snapdragon-7cGen2 Matrix](BenchmarkMatrix_Comparison_Snapdragon-7cGen2.md) |
| **Snapdragon 8cx Gen 1 / SQ1 (Kryo 495, Adreno 675)** | CPU NEON | **60.00** | **54.88** | 15.6% / 20.9% | 23.9% / 25.4% | 0 frames | [Snapdragon-8cxGen1 Matrix](BenchmarkMatrix_Comparison_Snapdragon-8cxGen1.md) |
| **Snapdragon 8cx Gen 1 / SQ1 (Kryo 495, Adreno 675)** | D3D12 GPU | **60.00** | **53.47** | 14.9% / 15.5% | 60.8% / 75.2% | 0 frames | [Snapdragon-8cxGen1 Matrix](BenchmarkMatrix_Comparison_Snapdragon-8cxGen1.md) |

---

## Dedicated Platform Comparison Matrices

- **[AMD Ryzen AI 5 340 (3x Zen 5 + 3x Zen 5c Cores, Radeon 840M RDNA 3.5 @ 2.9 GHz)](BenchmarkMatrix_Comparison_AMD-Ryzen-AI-5-340.md)** (Identifier: `AMD-Ryzen-AI-5-340`): Eco, Balanced, MaxQuality tiers tested
- **[Intel Processor N100 (4C/4T Gracemont @ 6W TDP, Intel UHD Graphics 24EU)](BenchmarkMatrix_Comparison_Intel-Processor-N100.md)** (Identifier: `Intel-Processor-N100`): Eco, Balanced, MaxQuality tiers tested
- **[Intel Core i5-1135G7 (4C/8T Tiger Lake-U @ 12W TDP, Intel Iris Xe Graphics 80EU)](BenchmarkMatrix_Comparison_Intel-Core-i5-1135G7.md)** (Identifier: `Intel-Core-i5-1135G7`): Eco, Balanced, MaxQuality tiers tested
- **[Intel Core i3-1215U (2P+4E/8T Alder Lake-U @ 15W TDP, Intel UHD Graphics 64EU)](BenchmarkMatrix_Comparison_Intel-Core-i3-1215U.md)** (Identifier: `Intel-Core-i3-1215U`): Eco, Balanced, MaxQuality tiers tested
- **[Generic x86-64 (Intel(R) Core(TM) i5-7Y54 CPU @ 1.20GHz, Intel(R) HD Graphics 615)](BenchmarkMatrix_Comparison_Generic-x86-64-Core-i5-7Y54-CPU---1-20GHz--Intel-HD-Graphics-615.md)** (Identifier: `Generic-x86-64-Core-i5-7Y54-CPU---1-20GHz--Intel-HD-Graphics-615`): Eco, Balanced, MaxQuality tiers tested
- **[Generic x86-64 (Intel(R) Pentium(R) Silver N5030 CPU @ 1.10GHz, Intel(R) UHD Graphics 605)](BenchmarkMatrix_Comparison_Generic-x86-64-Pentium-Silver-N5030-CPU---1-10GHz--Intel-UHD-Graphics-605.md)** (Identifier: `Generic-x86-64-Pentium-Silver-N5030-CPU---1-10GHz--Intel-UHD-Graphics-605`): Eco, Balanced, MaxQuality tiers tested
- **[Snapdragon X Plus (Qualcomm Oryon CPU, Adreno X1 GPU)](BenchmarkMatrix_Comparison_Snapdragon-X-Plus.md)** (Identifier: `Snapdragon-X-Plus`): Eco, Balanced, MaxQuality tiers tested
- **[Snapdragon 8cx Gen 2 / SQ2 (Kryo 495, Adreno 680)](BenchmarkMatrix_Comparison_Snapdragon-8cxGen2.md)** (Identifier: `Snapdragon-8cxGen2`): Eco, Balanced, MaxQuality tiers tested
- **[Snapdragon 8cx Gen 3 (Kryo Cortex-X1/A78, Adreno 690)](BenchmarkMatrix_Comparison_Snapdragon-8cxGen3.md)** (Identifier: `Snapdragon-8cxGen3`): Eco, Balanced, MaxQuality tiers tested
- **[Snapdragon 850 (Kryo 385, Adreno 630)](BenchmarkMatrix_Comparison_Snapdragon-850.md)** (Identifier: `Snapdragon-850`): Eco, Balanced, MaxQuality tiers tested
- **[Snapdragon 7c Gen 2 (Kryo 468, Adreno 618)](BenchmarkMatrix_Comparison_Snapdragon-7cGen2.md)** (Identifier: `Snapdragon-7cGen2`): Eco, Balanced, MaxQuality tiers tested
- **[Snapdragon 8cx Gen 1 / SQ1 (Kryo 495, Adreno 675)](BenchmarkMatrix_Comparison_Snapdragon-8cxGen1.md)** (Identifier: `Snapdragon-8cxGen1`): Eco, Balanced, MaxQuality tiers tested

