/*****************************************************************************
 * cpu.c: h264 encoder library
 *****************************************************************************
 * Copyright (C) 2003 Laurent Aimar
 * $Id: cpu.c,v 1.1 2004/06/03 19:27:06 fenrir Exp $
 *
 * Authors: Laurent Aimar <fenrir@via.ecp.fr>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111, USA.
 *****************************************************************************/
// adapted to be used by MVTools by TSchniede

#include "AnaFlags.h"
#include "cpu.h"
#include "debugprintf.h"
#include "string.h"
#include <avisynth.h>
#if (defined(_M_ARM64) || defined(__aarch64__)) && defined(_WIN32)
#include "avs/win.h"
#ifndef PF_ARM_V82_DP_INSTRUCTIONS_AVAILABLE
#define PF_ARM_V82_DP_INSTRUCTIONS_AVAILABLE 43
#endif
#endif

#define uint32_t unsigned int

int conv_cpuf_flags_to_cpu(int avscpu)
{
  int acpu = 0;
#if defined(_M_ARM64) || defined(__aarch64__)
  // On ARM64, 128-bit NEON SIMD is architectural and guaranteed on all processors.
  // Map baseline ARMv8.0 NEON to CPU_SSE2, and ARMv8.2-A DotProd (UDOT) to CPU_SSE4.
  acpu |= CPU_SSE2;
#if defined(_WIN32)
  if ((avscpu & CPUF_ARM_DOTPROD) || IsProcessorFeaturePresent(PF_ARM_V82_DP_INSTRUCTIONS_AVAILABLE))
    acpu |= CPU_SSE4;
#else
  if (avscpu & CPUF_ARM_DOTPROD)
    acpu |= CPU_SSE4;
#endif
#else
  if (avscpu & CPUF_SSE2) acpu |= CPU_SSE2;
  if (avscpu & CPUF_SSE3) acpu |= CPU_SSE3;
  if (avscpu & CPUF_SSSE3) acpu |= CPU_SSSE3;
  if (avscpu & CPUF_SSE4_1) acpu |= CPU_SSE4;
  if (avscpu & CPUF_SSE4_2) acpu |= CPU_SSE42;
  if (avscpu & CPUF_AVX) acpu |= CPU_AVX;
  if (avscpu & CPUF_AVX2) acpu |= CPU_AVX2;
#endif
  return acpu;
}

int get_simd_cpu_flags(int avscpu)
{
#if defined(_M_ARM64) || defined(__aarch64__)
  // AviSynth+ on ARM64 returns CPUF_ARM_* flags rather than x86 CPUF_SSE* flags.
  // Enable SSE2..SSE4.1 dispatch flags so sse2neon and native NEON paths are active.
  return avscpu | CPUF_SSE2 | CPUF_SSE3 | CPUF_SSSE3 | CPUF_SSE4_1;
#else
  return avscpu;
#endif
}


#undef uint32_t
