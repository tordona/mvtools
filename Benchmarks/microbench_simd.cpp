#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <vector>
#include <algorithm>
#define NOMINMAX
#include <windows.h>
#include <emmintrin.h>
#include <immintrin.h>

#define MV_FORCEINLINE __forceinline
typedef int sad_t;

static LARGE_INTEGER g_freq;

static inline double GetElapsedMs(const LARGE_INTEGER &t0, const LARGE_INTEGER &t1)
{
    return (double)(t1.QuadPart - t0.QuadPart) * 1000.0 / (double)g_freq.QuadPart;
}

// ============================================================================
// 1. SAD Predictor Batching Implementations
// ============================================================================

// Baseline sequential SSE2 SAD
template<int nBlkWidth, int nBlkHeight>
static MV_FORCEINLINE unsigned int Sad_sse2_impl(const uint8_t* pSrc, int nSrcPitch, const uint8_t* pRef, int nRefPitch)
{
    __m128i acc = _mm_setzero_si128();
    for (int y = 0; y < nBlkHeight; ++y)
    {
        for (int x = 0; x < nBlkWidth / 16 * 16; x += 16)
        {
            __m128i s = _mm_loadu_si128(reinterpret_cast<const __m128i*>(pSrc + x));
            __m128i r = _mm_loadu_si128(reinterpret_cast<const __m128i*>(pRef + x));
            acc = _mm_add_epi32(acc, _mm_sad_epu8(s, r));
        }
        if constexpr (nBlkWidth % 16 != 0 && nBlkWidth % 8 == 0)
        {
            for (int x = nBlkWidth / 16 * 16; x < nBlkWidth / 8 * 8; x += 8)
            {
                __m128i s = _mm_loadl_epi64(reinterpret_cast<const __m128i*>(pSrc + x));
                __m128i r = _mm_loadl_epi64(reinterpret_cast<const __m128i*>(pRef + x));
                acc = _mm_add_epi32(acc, _mm_sad_epu8(s, r));
            }
        }
        pSrc += nSrcPitch;
        pRef += nRefPitch;
    }
    __m128i upper = _mm_castps_si128(_mm_movehl_ps(_mm_setzero_ps(), _mm_castsi128_ps(acc)));
    acc = _mm_add_epi32(acc, upper);
    return _mm_cvtsi128_si32(acc);
}

// 4-Wide Batched SSE2 SAD
template<int nBlkWidth, int nBlkHeight>
static MV_FORCEINLINE void Sad_x4_sse2_impl(
    const uint8_t *pSrc, int nSrcPitch,
    const uint8_t *pRef0, const uint8_t *pRef1,
    const uint8_t *pRef2, const uint8_t *pRef3,
    int nRefPitch, sad_t *out_sads)
{
    __m128i acc0 = _mm_setzero_si128();
    __m128i acc1 = _mm_setzero_si128();
    __m128i acc2 = _mm_setzero_si128();
    __m128i acc3 = _mm_setzero_si128();

    for (int y = 0; y < nBlkHeight; ++y)
    {
        for (int x = 0; x < nBlkWidth / 16 * 16; x += 16)
        {
            __m128i s = _mm_loadu_si128(reinterpret_cast<const __m128i*>(pSrc + x));
            acc0 = _mm_add_epi32(acc0, _mm_sad_epu8(s, _mm_loadu_si128(reinterpret_cast<const __m128i*>(pRef0 + x))));
            acc1 = _mm_add_epi32(acc1, _mm_sad_epu8(s, _mm_loadu_si128(reinterpret_cast<const __m128i*>(pRef1 + x))));
            acc2 = _mm_add_epi32(acc2, _mm_sad_epu8(s, _mm_loadu_si128(reinterpret_cast<const __m128i*>(pRef2 + x))));
            acc3 = _mm_add_epi32(acc3, _mm_sad_epu8(s, _mm_loadu_si128(reinterpret_cast<const __m128i*>(pRef3 + x))));
        }
        if constexpr (nBlkWidth % 16 != 0 && nBlkWidth % 8 == 0)
        {
            for (int x = nBlkWidth / 16 * 16; x < nBlkWidth / 8 * 8; x += 8)
            {
                __m128i s = _mm_loadl_epi64(reinterpret_cast<const __m128i*>(pSrc + x));
                acc0 = _mm_add_epi32(acc0, _mm_sad_epu8(s, _mm_loadl_epi64(reinterpret_cast<const __m128i*>(pRef0 + x))));
                acc1 = _mm_add_epi32(acc1, _mm_sad_epu8(s, _mm_loadl_epi64(reinterpret_cast<const __m128i*>(pRef1 + x))));
                acc2 = _mm_add_epi32(acc2, _mm_sad_epu8(s, _mm_loadl_epi64(reinterpret_cast<const __m128i*>(pRef2 + x))));
                acc3 = _mm_add_epi32(acc3, _mm_sad_epu8(s, _mm_loadl_epi64(reinterpret_cast<const __m128i*>(pRef3 + x))));
            }
        }
        pSrc += nSrcPitch;
        pRef0 += nRefPitch; pRef1 += nRefPitch; pRef2 += nRefPitch; pRef3 += nRefPitch;
    }
    auto reduce = [](__m128i acc) {
        __m128i upper = _mm_castps_si128(_mm_movehl_ps(_mm_setzero_ps(), _mm_castsi128_ps(acc)));
        return (sad_t)_mm_cvtsi128_si32(_mm_add_epi32(acc, upper));
    };
    out_sads[0] = reduce(acc0);
    out_sads[1] = reduce(acc1);
    out_sads[2] = reduce(acc2);
    out_sads[3] = reduce(acc3);
}

// 4-Wide Batched AVX2 SAD
template<int nBlkWidth, int nBlkHeight>
static MV_FORCEINLINE void Sad_x4_avx2_impl(
    const uint8_t *pSrc, int nSrcPitch,
    const uint8_t *pRef0, const uint8_t *pRef1,
    const uint8_t *pRef2, const uint8_t *pRef3,
    int nRefPitch, sad_t *out_sads)
{
    if constexpr (nBlkWidth >= 32)
    {
        __m256i acc0 = _mm256_setzero_si256();
        __m256i acc1 = _mm256_setzero_si256();
        __m256i acc2 = _mm256_setzero_si256();
        __m256i acc3 = _mm256_setzero_si256();

        for (int y = 0; y < nBlkHeight; ++y)
        {
            for (int x = 0; x < nBlkWidth / 32 * 32; x += 32)
            {
                __m256i s = _mm256_loadu_si256(reinterpret_cast<const __m256i*>(pSrc + x));
                acc0 = _mm256_add_epi64(acc0, _mm256_sad_epu8(s, _mm256_loadu_si256(reinterpret_cast<const __m256i*>(pRef0 + x))));
                acc1 = _mm256_add_epi64(acc1, _mm256_sad_epu8(s, _mm256_loadu_si256(reinterpret_cast<const __m256i*>(pRef1 + x))));
                acc2 = _mm256_add_epi64(acc2, _mm256_sad_epu8(s, _mm256_loadu_si256(reinterpret_cast<const __m256i*>(pRef2 + x))));
                acc3 = _mm256_add_epi64(acc3, _mm256_sad_epu8(s, _mm256_loadu_si256(reinterpret_cast<const __m256i*>(pRef3 + x))));
            }
            pSrc += nSrcPitch;
            pRef0 += nRefPitch; pRef1 += nRefPitch; pRef2 += nRefPitch; pRef3 += nRefPitch;
        }
        auto reduce256 = [](__m256i a) {
            __m128i lo = _mm256_castsi256_si128(a);
            __m128i hi = _mm256_extracti128_si256(a, 1);
            __m128i sum = _mm_add_epi64(lo, hi);
            return (sad_t)(_mm_cvtsi128_si32(sum) + _mm_cvtsi128_si32(_mm_srli_si128(sum, 8)));
        };
        out_sads[0] = reduce256(acc0);
        out_sads[1] = reduce256(acc1);
        out_sads[2] = reduce256(acc2);
        out_sads[3] = reduce256(acc3);
    }
    else
    {
        Sad_x4_sse2_impl<nBlkWidth, nBlkHeight>(pSrc, nSrcPitch, pRef0, pRef1, pRef2, pRef3, nRefPitch, out_sads);
    }
}

// ============================================================================
// 2. Overlap Blending Implementations
// ============================================================================

template<int nBlkWidth, int nBlkHeight>
static MV_FORCEINLINE void Overlaps_scalar_impl(uint16_t *pDst, int nDstPitch, const uint8_t *pSrc, int nSrcPitch, short *pWin, int nWinPitch)
{
    for (int j = 0; j < nBlkHeight; ++j)
    {
        for (int i = 0; i < nBlkWidth; ++i)
            pDst[i] += (uint16_t)(((int)pSrc[i] * pWin[i]) >> 8);
        pDst += nDstPitch;
        pSrc += nSrcPitch;
        pWin += nWinPitch;
    }
}

template<int nBlkWidth, int nBlkHeight>
static MV_FORCEINLINE void Overlaps_avx2_impl(uint16_t *pDst, int nDstPitch, const uint8_t *pSrc, int nSrcPitch, short *pWin, int nWinPitch)
{
    const __m256i zero256 = _mm256_setzero_si256();
    const __m128i zero128 = _mm_setzero_si128();

    for (int j = 0; j < nBlkHeight; ++j)
    {
        int i = 0;
        for (; i + 32 <= nBlkWidth; i += 32)
        {
            __m256i vSrc = _mm256_loadu_si256(reinterpret_cast<const __m256i*>(pSrc + i));
            __m256i w_lo = _mm256_loadu_si256(reinterpret_cast<const __m256i*>(pWin + i));
            __m256i w_hi = _mm256_loadu_si256(reinterpret_cast<const __m256i*>(pWin + i + 16));

            __m256i prod_lo = _mm256_srli_epi16(_mm256_mullo_epi16(_mm256_unpacklo_epi8(vSrc, zero256), w_lo), 8);
            __m256i prod_hi = _mm256_srli_epi16(_mm256_mullo_epi16(_mm256_unpackhi_epi8(vSrc, zero256), w_hi), 8);

            __m256i d_lo = _mm256_loadu_si256(reinterpret_cast<const __m256i*>(pDst + i));
            __m256i d_hi = _mm256_loadu_si256(reinterpret_cast<const __m256i*>(pDst + i + 16));
            _mm256_storeu_si256(reinterpret_cast<__m256i*>(pDst + i), _mm256_add_epi16(d_lo, prod_lo));
            _mm256_storeu_si256(reinterpret_cast<__m256i*>(pDst + i + 16), _mm256_add_epi16(d_hi, prod_hi));
        }
        for (; i + 16 <= nBlkWidth; i += 16)
        {
            __m128i vSrc = _mm_loadu_si128(reinterpret_cast<const __m128i*>(pSrc + i));
            __m128i w_lo = _mm_loadu_si128(reinterpret_cast<const __m128i*>(pWin + i));
            __m128i w_hi = _mm_loadu_si128(reinterpret_cast<const __m128i*>(pWin + i + 8));

            __m128i prod_lo = _mm_srli_epi16(_mm_mullo_epi16(_mm_unpacklo_epi8(vSrc, zero128), w_lo), 8);
            __m128i prod_hi = _mm_srli_epi16(_mm_mullo_epi16(_mm_unpackhi_epi8(vSrc, zero128), w_hi), 8);

            _mm_storeu_si128(reinterpret_cast<__m128i*>(pDst + i), _mm_add_epi16(_mm_loadu_si128(reinterpret_cast<const __m128i*>(pDst + i)), prod_lo));
            _mm_storeu_si128(reinterpret_cast<__m128i*>(pDst + i + 8), _mm_add_epi16(_mm_loadu_si128(reinterpret_cast<const __m128i*>(pDst + i + 8)), prod_hi));
        }
        for (; i < nBlkWidth; ++i)
            pDst[i] += (uint16_t)(((int)pSrc[i] * pWin[i]) >> 8);

        pDst += nDstPitch;
        pSrc += nSrcPitch;
        pWin += nWinPitch;
    }
}

// ============================================================================
// 3. Wiener 6-Tap Implementations
// ============================================================================

static MV_FORCEINLINE void HorizontalWiener_scalar_impl(uint8_t *pDst, const uint8_t *pSrc, int nDstPitch, int nSrcPitch, int nWidth, int nHeight)
{
    for (int y = 0; y < nHeight; ++y)
    {
        for (int x = 0; x < nWidth; ++x)
        {
            int val = (int)pSrc[x - 2] - 5 * (int)pSrc[x - 1] + 20 * (int)pSrc[x] +
                      20 * (int)pSrc[x + 1] - 5 * (int)pSrc[x + 2] + (int)pSrc[x + 3];
            val = (val + 16) >> 5;
            pDst[x] = (uint8_t)std::min(std::max(val, 0), 255);
        }
        pDst += nDstPitch;
        pSrc += nSrcPitch;
    }
}

static MV_FORCEINLINE void HorizontalWiener_avx2_impl(uint8_t *pDst, const uint8_t *pSrc, int nDstPitch, int nSrcPitch, int nWidth, int nHeight)
{
    const __m256i zero256 = _mm256_setzero_si256();
    const __m256i c_pos20 = _mm256_set1_epi16(20);
    const __m256i c_neg5  = _mm256_set1_epi16(-5);
    const __m256i c_pos1  = _mm256_set1_epi16(1);
    const __m256i c_16    = _mm256_set1_epi16(16);

    for (int y = 0; y < nHeight; ++y)
    {
        int x = 0;
        for (; x + 32 <= nWidth; x += 32)
        {
            __m256i s_m2 = _mm256_loadu_si256(reinterpret_cast<const __m256i*>(pSrc + x - 2));
            __m256i s_m1 = _mm256_loadu_si256(reinterpret_cast<const __m256i*>(pSrc + x - 1));
            __m256i s_0  = _mm256_loadu_si256(reinterpret_cast<const __m256i*>(pSrc + x));
            __m256i s_p1 = _mm256_loadu_si256(reinterpret_cast<const __m256i*>(pSrc + x + 1));
            __m256i s_p2 = _mm256_loadu_si256(reinterpret_cast<const __m256i*>(pSrc + x + 2));
            __m256i s_p3 = _mm256_loadu_si256(reinterpret_cast<const __m256i*>(pSrc + x + 3));

            auto filter_16 = [&](__m256i m2, __m256i m1, __m256i z, __m256i p1, __m256i p2, __m256i p3) {
                __m256i sum = _mm256_add_epi16(m2, p3);
                sum = _mm256_add_epi16(sum, _mm256_mullo_epi16(_mm256_add_epi16(m1, p2), c_neg5));
                sum = _mm256_add_epi16(sum, _mm256_mullo_epi16(_mm256_add_epi16(z, p1), c_pos20));
                sum = _mm256_srai_epi16(_mm256_add_epi16(sum, c_16), 5);
                return sum;
            };

            __m256i r_lo = filter_16(
                _mm256_unpacklo_epi8(s_m2, zero256), _mm256_unpacklo_epi8(s_m1, zero256),
                _mm256_unpacklo_epi8(s_0,  zero256), _mm256_unpacklo_epi8(s_p1, zero256),
                _mm256_unpacklo_epi8(s_p2, zero256), _mm256_unpacklo_epi8(s_p3, zero256));

            __m256i r_hi = filter_16(
                _mm256_unpackhi_epi8(s_m2, zero256), _mm256_unpackhi_epi8(s_m1, zero256),
                _mm256_unpackhi_epi8(s_0,  zero256), _mm256_unpackhi_epi8(s_p1, zero256),
                _mm256_unpackhi_epi8(s_p2, zero256), _mm256_unpackhi_epi8(s_p3, zero256));

            _mm256_storeu_si256(reinterpret_cast<__m256i*>(pDst + x), _mm256_packus_epi16(r_lo, r_hi));
        }
        for (; x < nWidth; ++x)
        {
            int val = (int)pSrc[x - 2] - 5 * (int)pSrc[x - 1] + 20 * (int)pSrc[x] +
                      20 * (int)pSrc[x + 1] - 5 * (int)pSrc[x + 2] + (int)pSrc[x + 3];
            val = (val + 16) >> 5;
            pDst[x] = (uint8_t)std::min(std::max(val, 0), 255);
        }
        pDst += nDstPitch;
        pSrc += nSrcPitch;
    }
    _mm256_zeroupper();
}

// ============================================================================
// Main Micro-Benchmark Runner
// ============================================================================

int main()
{
    QueryPerformanceFrequency(&g_freq);
    srand(42);

    printf("======================================================================\n");
    printf(" MVTools2 Native SIMD Micro-Benchmark Harness (x64 AVX2 / SSE2)\n");
    printf("======================================================================\n");

    // 1. SAD Predictors
    {
        printf("\n1. 4-Candidate SAD Predictor Batching (8-bit)\n");
        printf("%-10s | %-12s | %-12s | %-12s | %-12s | %-10s\n",
               "Block Size", "4x Seq SSE2", "Sad_x4 SSE2", "Sad_x4 AVX2", "SSE2 Speedup", "AVX2 Speedup");
        printf("-----------+--------------+--------------+--------------+--------------+------------\n");

        const int pitch = 128;
        const int bufSize = pitch * 128;
        std::vector<uint8_t> src(bufSize), ref0(bufSize), ref1(bufSize), ref2(bufSize), ref3(bufSize);
        for (int i = 0; i < bufSize; ++i) {
            src[i]  = (uint8_t)(rand() & 0xFF); ref0[i] = (uint8_t)(rand() & 0xFF);
            ref1[i] = (uint8_t)(rand() & 0xFF); ref2[i] = (uint8_t)(rand() & 0xFF); ref3[i] = (uint8_t)(rand() & 0xFF);
        }
        const int iters = 2000000;
        sad_t out_x4[4];
        volatile uint64_t sink = 0;

#define RUN_SAD_BENCH(w, h) { \
            LARGE_INTEGER t0, t1; \
            QueryPerformanceCounter(&t0); \
            for (int i = 0; i < iters; ++i) { \
                sink += Sad_sse2_impl<w, h>(src.data(), pitch, ref0.data(), pitch); \
                sink += Sad_sse2_impl<w, h>(src.data(), pitch, ref1.data(), pitch); \
                sink += Sad_sse2_impl<w, h>(src.data(), pitch, ref2.data(), pitch); \
                sink += Sad_sse2_impl<w, h>(src.data(), pitch, ref3.data(), pitch); \
            } \
            QueryPerformanceCounter(&t1); \
            double ms_seq = GetElapsedMs(t0, t1); \
            QueryPerformanceCounter(&t0); \
            for (int i = 0; i < iters; ++i) { \
                Sad_x4_sse2_impl<w, h>(src.data(), pitch, ref0.data(), ref1.data(), ref2.data(), ref3.data(), pitch, out_x4); \
                sink += out_x4[0]; \
            } \
            QueryPerformanceCounter(&t1); \
            double ms_sse2 = GetElapsedMs(t0, t1); \
            QueryPerformanceCounter(&t0); \
            for (int i = 0; i < iters; ++i) { \
                Sad_x4_avx2_impl<w, h>(src.data(), pitch, ref0.data(), ref1.data(), ref2.data(), ref3.data(), pitch, out_x4); \
                sink += out_x4[0]; \
            } \
            QueryPerformanceCounter(&t1); \
            double ms_avx2 = GetElapsedMs(t0, t1); \
            printf("%-10s | %8.2f ms  | %8.2f ms  | %8.2f ms  | %10.2fx   | %8.2fx\n", \
                   #w "x" #h, ms_seq, ms_sse2, ms_avx2, ms_seq / ms_sse2, ms_seq / ms_avx2); \
        }

        RUN_SAD_BENCH(64, 64);
        RUN_SAD_BENCH(32, 32);
        RUN_SAD_BENCH(16, 16);
        RUN_SAD_BENCH(8, 8);
#undef RUN_SAD_BENCH
    }

    // 2. Overlap Blending
    {
        printf("\n2. Overlap Blending (uint8_t)\n");
        printf("%-10s | %-14s | %-14s | %-10s\n",
               "Block Size", "Scalar C Time", "AVX2 Time", "Speedup");
        printf("-----------+----------------+----------------+------------\n");

        const int pitch = 128;
        const int bufSize = pitch * 128;
        std::vector<uint16_t> dst(bufSize, 0);
        std::vector<uint8_t> src(bufSize);
        std::vector<short> win(128 * 128);
        for (int i = 0; i < bufSize; ++i) src[i] = (uint8_t)(rand() & 0xFF);
        for (size_t i = 0; i < win.size(); ++i) win[i] = (short)(rand() & 0xFF);
        const int iters = 2000000;

#define RUN_OVERLAP_BENCH(w, h) { \
            LARGE_INTEGER t0, t1; \
            QueryPerformanceCounter(&t0); \
            for (int i = 0; i < iters; ++i) \
                Overlaps_scalar_impl<w, h>(dst.data(), pitch, src.data(), pitch, win.data(), w); \
            QueryPerformanceCounter(&t1); \
            double ms_c = GetElapsedMs(t0, t1); \
            QueryPerformanceCounter(&t0); \
            for (int i = 0; i < iters; ++i) \
                Overlaps_avx2_impl<w, h>(dst.data(), pitch, src.data(), pitch, win.data(), w); \
            QueryPerformanceCounter(&t1); \
            double ms_avx2 = GetElapsedMs(t0, t1); \
            printf("%-10s | %10.2f ms   | %10.2f ms   | %8.2fx\n", \
                   #w "x" #h, ms_c, ms_avx2, ms_c / ms_avx2); \
        }

        RUN_OVERLAP_BENCH(64, 64);
        RUN_OVERLAP_BENCH(32, 32);
        RUN_OVERLAP_BENCH(16, 16);
        RUN_OVERLAP_BENCH(8, 8);
#undef RUN_OVERLAP_BENCH
    }

    // 3. Wiener 6-Tap FIR
    {
        printf("\n3. 6-Tap Wiener Interpolation (uint8_t, 1080p Slice)\n");
        printf("%-20s | %-14s | %-14s | %-10s\n",
               "Kernel", "Scalar C Time", "AVX2 Time", "Speedup");
        printf("---------------------+----------------+----------------+------------\n");

        const int width = 1920;
        const int height = 256;
        const int pitch = width + 64;
        const int bufSize = pitch * (height + 32);
        std::vector<uint8_t> src(bufSize), dst_c(bufSize), dst_avx2(bufSize);
        for (int i = 0; i < bufSize; ++i) src[i] = (uint8_t)(rand() & 0xFF);
        const int iters = 2000;

        LARGE_INTEGER t0, t1;
        QueryPerformanceCounter(&t0);
        for (int i = 0; i < iters; ++i)
            HorizontalWiener_scalar_impl(dst_c.data(), src.data() + 16, pitch, pitch, width, height);
        QueryPerformanceCounter(&t1);
        double ms_c = GetElapsedMs(t0, t1);

        QueryPerformanceCounter(&t0);
        for (int i = 0; i < iters; ++i)
            HorizontalWiener_avx2_impl(dst_avx2.data(), src.data() + 16, pitch, pitch, width, height);
        QueryPerformanceCounter(&t1);
        double ms_avx2 = GetElapsedMs(t0, t1);

        printf("%-20s | %10.2f ms   | %10.2f ms   | %8.2fx\n",
               "Horizontal Wiener", ms_c, ms_avx2, ms_c / ms_avx2);
    }

    printf("\nAll micro-benchmarks executed successfully.\n");
    return 0;
}
