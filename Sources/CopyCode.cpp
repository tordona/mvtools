// Author: Manao
// See legal notice in Copying.txt for more information
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA, or visit
// http://www.gnu.org/copyleft/gpl.html .

#include "CopyCode.h"
#include <map>
#include <tuple>
#include <stdint.h>


template <typename pixel_t>
void fill_chroma(BYTE* dstp_u, BYTE* dstp_v, int height, int pitch, pixel_t val)
{
  size_t size = height * pitch / sizeof(pixel_t);
  std::fill_n(reinterpret_cast<pixel_t*>(dstp_u), size, val);
  std::fill_n(reinterpret_cast<pixel_t*>(dstp_v), size, val);
}

template <typename pixel_t>
void fill_plane(BYTE* dstp, int height, int pitch, pixel_t val)
{
  size_t size = height * pitch / sizeof(pixel_t);
  std::fill_n(reinterpret_cast<pixel_t*>(dstp), size, val);
}

// instantiate to let them access from other modules
template void fill_chroma<BYTE>(BYTE* dstp_u, BYTE* dstp_v, int height, int pitch, BYTE val);
template void fill_chroma<uint16_t>(BYTE* dstp_u, BYTE* dstp_v, int height, int pitch, uint16_t val);
template void fill_chroma<float>(BYTE* dstp_u, BYTE* dstp_v, int height, int pitch, float val);

template void fill_plane<BYTE>(BYTE* dstp, int height, int pitch, BYTE val);
template void fill_plane<uint16_t>(BYTE* dstp, int height, int pitch, uint16_t val);
template void fill_plane<float>(BYTE* dstp, int height, int pitch, float val);
// I use here the copy code from avisynth. I duplicated it, because I have to use it
// in a class which doesn't have to know what "env" is. Anyway, such static functions
// should not have been put into that class in the first place ( imho )

void BitBlt(unsigned char* dstp, int dst_pitch, const unsigned char* srcp, int src_pitch, int row_size, int height) {
  if ( (!height)|| (!row_size)) return;
  if (height == 1 || (dst_pitch == src_pitch && src_pitch == row_size)) {
    memcpy(dstp, srcp, row_size*height); // Fizick: fixed bug
  } else {
    for (int y=height; y>0; --y) {
      memcpy(dstp, srcp, row_size);
      dstp += dst_pitch;
      srcp += src_pitch;
    }
  }
}

void MemZoneSet(unsigned char *ptr, unsigned char value, int width,
        int height, int offsetX, int offsetY, int pitch)
{
  ptr += offsetX + offsetY*pitch;
  for (int y=offsetY; y<height+offsetY; y++)
  {
    memset(ptr, value, width);
    ptr += pitch;
  }
}

// pitch is in bytes
void MemZoneSet16(uint16_t *ptr, uint16_t value, int width,
  int height, int offsetX, int offsetY, int pitch)
{
  pitch /= sizeof(uint16_t);
  ptr += offsetX + offsetY*pitch;
  for (int y = offsetY; y<height + offsetY; y++)
  {
    std::fill_n(ptr, width, value);
    ptr += pitch;
  }
}


template<int nBlkWidth, int nBlkHeight, typename pixel_t>
void Copy_C (uint8_t *pDst, int nDstPitch, const uint8_t *pSrc, int nSrcPitch)
{
    for (int j = 0; j < nBlkHeight; j++ )
    {
        //      for ( int i = 0; i < nBlkWidth; i++ )  //  waste cycles removed by Fizick in v1.2
      memcpy(pDst, pSrc, nBlkWidth * sizeof(pixel_t));
      pDst += nDstPitch;
      pSrc += nSrcPitch;
    }
}

#if defined(__ARM_NEON) || defined(_M_ARM64) || defined(__aarch64__)
#include <arm_neon.h>

template<int nBlkWidth, int nBlkHeight, typename pixel_t>
void Copy_neon(uint8_t *pDst, int nDstPitch, const uint8_t *pSrc, int nSrcPitch)
{
    constexpr int rowBytes = nBlkWidth * (int)sizeof(pixel_t);

    if constexpr (rowBytes == 16)
    {
        int y = 0;
        if constexpr (nBlkHeight >= 4)
        {
            for (; y + 4 <= nBlkHeight; y += 4)
            {
                uint8x16_t r0 = vld1q_u8(pSrc);
                uint8x16_t r1 = vld1q_u8(pSrc + nSrcPitch);
                uint8x16_t r2 = vld1q_u8(pSrc + nSrcPitch * 2);
                uint8x16_t r3 = vld1q_u8(pSrc + nSrcPitch * 3);
                vst1q_u8(pDst, r0);
                vst1q_u8(pDst + nDstPitch, r1);
                vst1q_u8(pDst + nDstPitch * 2, r2);
                vst1q_u8(pDst + nDstPitch * 3, r3);
                pSrc += nSrcPitch * 4;
                pDst += nDstPitch * 4;
            }
        }
        for (; y < nBlkHeight; ++y)
        {
            vst1q_u8(pDst, vld1q_u8(pSrc));
            pSrc += nSrcPitch;
            pDst += nDstPitch;
        }
    }
    else if constexpr (rowBytes == 8)
    {
        int y = 0;
        if constexpr (nBlkHeight >= 4)
        {
            for (; y + 4 <= nBlkHeight; y += 4)
            {
                uint8x8_t r0 = vld1_u8(pSrc);
                uint8x8_t r1 = vld1_u8(pSrc + nSrcPitch);
                uint8x8_t r2 = vld1_u8(pSrc + nSrcPitch * 2);
                uint8x8_t r3 = vld1_u8(pSrc + nSrcPitch * 3);
                vst1_u8(pDst, r0);
                vst1_u8(pDst + nDstPitch, r1);
                vst1_u8(pDst + nDstPitch * 2, r2);
                vst1_u8(pDst + nDstPitch * 3, r3);
                pSrc += nSrcPitch * 4;
                pDst += nDstPitch * 4;
            }
        }
        for (; y < nBlkHeight; ++y)
        {
            vst1_u8(pDst, vld1_u8(pSrc));
            pSrc += nSrcPitch;
            pDst += nDstPitch;
        }
    }
    else if constexpr (rowBytes == 32)
    {
        int y = 0;
        if constexpr (nBlkHeight >= 2)
        {
            for (; y + 2 <= nBlkHeight; y += 2)
            {
                uint8x16_t r00 = vld1q_u8(pSrc);
                uint8x16_t r01 = vld1q_u8(pSrc + 16);
                uint8x16_t r10 = vld1q_u8(pSrc + nSrcPitch);
                uint8x16_t r11 = vld1q_u8(pSrc + nSrcPitch + 16);
                vst1q_u8(pDst, r00);
                vst1q_u8(pDst + 16, r01);
                vst1q_u8(pDst + nDstPitch, r10);
                vst1q_u8(pDst + nDstPitch + 16, r11);
                pSrc += nSrcPitch * 2;
                pDst += nDstPitch * 2;
            }
        }
        for (; y < nBlkHeight; ++y)
        {
            uint8x16_t r0 = vld1q_u8(pSrc);
            uint8x16_t r1 = vld1q_u8(pSrc + 16);
            vst1q_u8(pDst, r0);
            vst1q_u8(pDst + 16, r1);
            pSrc += nSrcPitch;
            pDst += nDstPitch;
        }
    }
    else if constexpr (rowBytes == 64)
    {
        for (int y = 0; y < nBlkHeight; ++y)
        {
            uint8x16_t r0 = vld1q_u8(pSrc);
            uint8x16_t r1 = vld1q_u8(pSrc + 16);
            uint8x16_t r2 = vld1q_u8(pSrc + 32);
            uint8x16_t r3 = vld1q_u8(pSrc + 48);
            vst1q_u8(pDst, r0);
            vst1q_u8(pDst + 16, r1);
            vst1q_u8(pDst + 32, r2);
            vst1q_u8(pDst + 48, r3);
            pSrc += nSrcPitch;
            pDst += nDstPitch;
        }
    }
    else if constexpr (rowBytes == 4)
    {
        int y = 0;
        if constexpr (nBlkHeight >= 4)
        {
            for (; y + 4 <= nBlkHeight; y += 4)
            {
                uint32_t r0, r1, r2, r3;
                memcpy(&r0, pSrc, 4);
                memcpy(&r1, pSrc + nSrcPitch, 4);
                memcpy(&r2, pSrc + nSrcPitch * 2, 4);
                memcpy(&r3, pSrc + nSrcPitch * 3, 4);
                memcpy(pDst, &r0, 4);
                memcpy(pDst + nDstPitch, &r1, 4);
                memcpy(pDst + nDstPitch * 2, &r2, 4);
                memcpy(pDst + nDstPitch * 3, &r3, 4);
                pSrc += nSrcPitch * 4;
                pDst += nDstPitch * 4;
            }
        }
        for (; y < nBlkHeight; ++y)
        {
            uint32_t r0;
            memcpy(&r0, pSrc, 4);
            memcpy(pDst, &r0, 4);
            pSrc += nSrcPitch;
            pDst += nDstPitch;
        }
    }
    else
    {
        for (int y = 0; y < nBlkHeight; ++y)
        {
            int x = 0;
            if constexpr (rowBytes >= 16)
            {
                for (; x + 16 <= rowBytes; x += 16)
                    vst1q_u8(pDst + x, vld1q_u8(pSrc + x));
            }
            if constexpr ((rowBytes % 16) >= 8)
            {
                vst1_u8(pDst + x, vld1_u8(pSrc + x));
                x += 8;
            }
            if constexpr ((rowBytes % 8) >= 4)
            {
                uint32_t r4;
                memcpy(&r4, pSrc + x, 4);
                memcpy(pDst + x, &r4, 4);
                x += 4;
            }
            if constexpr ((rowBytes % 4) >= 2)
            {
                uint16_t r2;
                memcpy(&r2, pSrc + x, 2);
                memcpy(pDst + x, &r2, 2);
                x += 2;
            }
            if constexpr ((rowBytes % 2) == 1)
            {
                pDst[x] = pSrc[x];
            }
            pSrc += nSrcPitch;
            pDst += nDstPitch;
        }
    }
}
#endif


COPYFunction* get_copy_function(int BlockX, int BlockY, int pixelsize, arch_t arch)
{
    // BlkSizeX, BlkSizeY, pixelsize, arch_t
    std::map<std::tuple<int, int, int, arch_t>, COPYFunction*> func_copy;
    using std::make_tuple;
#if defined(__ARM_NEON) || defined(_M_ARM64) || defined(__aarch64__)
#define MAKE_COPY_FN(x, y) \
func_copy[make_tuple(x, y, 1, NO_SIMD)] = Copy_C<x, y, uint8_t>; \
func_copy[make_tuple(x, y, 2, NO_SIMD)] = Copy_C<x, y, uint16_t>; \
func_copy[make_tuple(x, y, 4, NO_SIMD)] = Copy_C<x, y, float>; \
func_copy[make_tuple(x, y, 1, USE_SSE2)] = Copy_neon<x, y, uint8_t>; \
func_copy[make_tuple(x, y, 2, USE_SSE2)] = Copy_neon<x, y, uint16_t>; \
func_copy[make_tuple(x, y, 4, USE_SSE2)] = Copy_neon<x, y, float>;
#else
#define MAKE_COPY_FN(x, y) func_copy[make_tuple(x, y, 1, NO_SIMD)] = Copy_C<x, y, uint8_t>; \
func_copy[make_tuple(x, y, 2, NO_SIMD)] = Copy_C<x, y, uint16_t>; \
func_copy[make_tuple(x, y, 4, NO_SIMD)] = Copy_C<x, y, float>;
#endif
    // same list as in overlap.cpp SadFunction.cpp, Sad_C selector
    MAKE_COPY_FN(64, 64)
      MAKE_COPY_FN(64, 48)
      MAKE_COPY_FN(64, 32)
      MAKE_COPY_FN(64, 16)
      MAKE_COPY_FN(48, 64)
      MAKE_COPY_FN(48, 48)
      MAKE_COPY_FN(48, 24)
      MAKE_COPY_FN(48, 12)
      MAKE_COPY_FN(32, 64)
      MAKE_COPY_FN(32, 32)
      MAKE_COPY_FN(32, 24)
      MAKE_COPY_FN(32, 16)
      MAKE_COPY_FN(32, 8)
      MAKE_COPY_FN(24, 48)
      MAKE_COPY_FN(24, 32)
      MAKE_COPY_FN(24, 24)
      MAKE_COPY_FN(24, 12)
      MAKE_COPY_FN(24, 6)
      MAKE_COPY_FN(16, 64)
      MAKE_COPY_FN(16, 32)
      MAKE_COPY_FN(16, 16)
      MAKE_COPY_FN(16, 12)
      MAKE_COPY_FN(16, 8)
      MAKE_COPY_FN(16, 4)
      MAKE_COPY_FN(16, 2)
      MAKE_COPY_FN(16, 1)
      MAKE_COPY_FN(12, 48)
      MAKE_COPY_FN(12, 24)
      MAKE_COPY_FN(12, 16)
      MAKE_COPY_FN(12, 12)
      MAKE_COPY_FN(12, 6)
      MAKE_COPY_FN(12, 3)
      MAKE_COPY_FN(8, 32)
      MAKE_COPY_FN(8, 16)
      MAKE_COPY_FN(8, 8)
      MAKE_COPY_FN(8, 4)
      MAKE_COPY_FN(8, 2)
      MAKE_COPY_FN(8, 1)
      MAKE_COPY_FN(6, 24)
      MAKE_COPY_FN(6, 12)
      MAKE_COPY_FN(6, 6)
      MAKE_COPY_FN(6, 3)
      MAKE_COPY_FN(4, 8)
      MAKE_COPY_FN(4, 4)
      MAKE_COPY_FN(4, 2)
      MAKE_COPY_FN(4, 1)
      MAKE_COPY_FN(3, 6)
      MAKE_COPY_FN(3, 3)
      MAKE_COPY_FN(2, 4)
      MAKE_COPY_FN(2, 2)
      MAKE_COPY_FN(2, 1)
#undef MAKE_COPY_FN

#ifdef USE_COPYCODE_ASM
    // we could even ignore copy sse2 assemblers, compilers are smart nowadays
    // no mmx copy for block sizes over 32
    // CopyCode-a.asm
    func_copy[make_tuple(32, 32, 1, USE_SSE2)] = Copy32x32_sse2;
    func_copy[make_tuple(32, 16, 1, USE_SSE2)] = Copy32x16_sse2;
    func_copy[make_tuple(32, 8 , 1, USE_SSE2)] = Copy32x8_sse2;
    func_copy[make_tuple(16, 32, 1, USE_SSE2)] = Copy16x32_sse2;
    func_copy[make_tuple(16, 16, 1, USE_SSE2)] = Copy16x16_sse2;
    func_copy[make_tuple(16, 8 , 1, USE_SSE2)] = Copy16x8_sse2;
    func_copy[make_tuple(16, 4 , 1, USE_SSE2)] = Copy16x4_sse2;
    func_copy[make_tuple(16, 2 , 1, USE_SSE2)] = Copy16x2_sse2;
    func_copy[make_tuple(8 , 16, 1, USE_SSE2)] = Copy8x16_sse2;
    func_copy[make_tuple(8 , 8 , 1, USE_SSE2)] = Copy8x8_sse2;
    func_copy[make_tuple(8 , 4 , 1, USE_SSE2)] = Copy8x4_sse2;
    func_copy[make_tuple(8 , 2 , 1, USE_SSE2)] = Copy8x2_sse2;
    func_copy[make_tuple(8 , 1 , 1, USE_SSE2)] = Copy8x1_sse2;
    func_copy[make_tuple(4 , 8 , 1, USE_SSE2)] = Copy4x8_sse2;
    func_copy[make_tuple(4 , 4 , 1, USE_SSE2)] = Copy4x4_sse2;
    func_copy[make_tuple(4 , 2 , 1, USE_SSE2)] = Copy4x2_sse2;
    func_copy[make_tuple(2 , 4 , 1, USE_SSE2)] = Copy2x4_sse2;
    func_copy[make_tuple(2 , 2 , 1, USE_SSE2)] = Copy2x2_sse2;
    //func_copy[make_tuple(2 , 1 , 1, USE_SSE2)] = Copy2x1_sse2; no such
#endif
    COPYFunction *result = nullptr;
    arch_t archlist[] = { USE_AVX2, USE_AVX, USE_SSE41, USE_SSE2, NO_SIMD };
    int index = 0;
    while (result == nullptr) {
      arch_t current_arch_try = archlist[index++];
      if (current_arch_try > arch) continue;
      result = func_copy[make_tuple(BlockX, BlockY, pixelsize, current_arch_try)];
      if (result == nullptr && current_arch_try == NO_SIMD)
        break;
    }

    return result;
}


