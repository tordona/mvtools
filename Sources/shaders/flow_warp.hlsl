// HLSL DirectCompute Frame Synthesis Shader (Shader Model 5.0 / Direct3D 12)
// Direct3D 12 Gather-Based Subpixel Motion Warping & Frame Synthesis (MFlowFps / MBlockFps)
// Offloaded to Qualcomm Adreno / Direct3D 12 GPU for Zero-CPU Flow Interpolation

// -----------------------------------------------------------------------------
// Constant Buffers
// -----------------------------------------------------------------------------

cbuffer FlowParams : register(b0)
{
    uint   width;          // Plane width in pixels
    uint   height;         // Plane height in pixels
    float  time;           // Normalized interpolation time t in [0.0, 1.0]
    float  nPel;           // Pel accuracy (1.0 = integer, 2.0 = half-pel)

    float  mvScaleX;       // Motion vector scale X (1.0 for Y, 0.5 for chroma)
    float  mvScaleY;       // Motion vector scale Y (1.0 for Y, 0.5 for chroma)
    uint   maskMode;       // 0 = MC blend, 1 = static median, 2 = dynamic median
    uint   nBlkSizeX;      // Block size X for current plane

    uint   nBlkSizeY;      // Block size Y for current plane
    uint   nBlkX;          // Horizontal block count
    uint   nBlkY;          // Vertical block count
    uint   flowMode;       // 0 = block-based (MBlockFps), 1 = continuous (MFlowFps)
};

cbuffer UnpackParams : register(b0)
{
    uint unpackBlkX;       // Block count horizontally
    uint unpackBlkY;       // Block count vertically
    uint unpackPad0;
    uint unpackPad1;
};

cbuffer BlendParams : register(b0)
{
    uint  blendWidth;      // Plane width
    uint  blendHeight;     // Plane height
    float blendTime;       // Blend factor t
    uint  blendPad;
};

// -----------------------------------------------------------------------------
// Resources: Warp & Synthesis Pass (Luma Y & Fused Chroma U+V)
// -----------------------------------------------------------------------------

Texture2D<float>   g_SrcPlane        : register(t0); // Frame N (Source / Left frame - Y or U)
Texture2D<float>   g_RefPlane        : register(t1); // Frame N+1 (Reference / Right frame - Y or U)
Texture2D<float2>  g_MotionVectorsF  : register(t2); // Forward motion vectors (block grid)
Texture2D<float2>  g_MotionVectorsB  : register(t3); // Backward motion vectors (block grid)
Texture2D<float>   g_SrcPlaneV       : register(t4); // Frame N V plane (Fused Chroma pass)
Texture2D<float>   g_RefPlaneV       : register(t5); // Frame N+1 V plane (Fused Chroma pass)

RWTexture2D<float> g_OutPlane        : register(u0); // Interpolated output plane (Y or U)
RWTexture2D<float> g_OutPlaneV       : register(u1); // Interpolated output V plane (Fused Chroma pass)

SamplerState       g_LinearClamp     : register(s0); // Hardware bilinear sampler with border clamp
SamplerState       g_PointClamp      : register(s1); // Point / nearest-neighbor sampler

// -----------------------------------------------------------------------------
// Resources: Motion Vector Unpack Pass
// -----------------------------------------------------------------------------

ByteAddressBuffer   g_RawBlockResults : register(t0); // 12 bytes per block from motion_search_cs
RWTexture2D<float2> g_OutMvTexture    : register(u0); // 2D Vector texture for hardware bilinear sampling

// -----------------------------------------------------------------------------
// Resources: Direct Frame Blend Fallback Pass (Scene Change / Vector Unusable)
// -----------------------------------------------------------------------------

Texture2D<float>   g_BlendSrcPlane   : register(t0);
Texture2D<float>   g_BlendRefPlane   : register(t1);
Texture2D<float>   g_BlendSrcPlaneV  : register(t2);
Texture2D<float>   g_BlendRefPlaneV  : register(t3);
RWTexture2D<float> g_BlendOutPlane   : register(u0);
RWTexture2D<float> g_BlendOutPlaneV  : register(u1);

// -----------------------------------------------------------------------------
// Shared Memory for Block-Based Motion Vector Broadcast (16x8 = four 8x4 quadrants)
// -----------------------------------------------------------------------------

groupshared float2 gs_MvF[4];
groupshared float2 gs_MvB[4];

// =============================================================================
// Compute Shader Entry Point: FlowWarpCS (Luma Plane)
// Gather-based subpixel warping with Adreno Wave64 (16x8) & FP16 Dynamic Median
// =============================================================================

[numthreads(16, 8, 1)]
void FlowWarpCS(uint3 DTid : SV_DispatchThreadID, uint3 Gid : SV_GroupID, uint3 GTid : SV_GroupThreadID, uint GI : SV_GroupIndex)
{
    // 1. Fetch raw motion vectors for current pixel (FP32 coordinates)
    float2 rawMvF, rawMvB;

    [branch]
    if (flowMode == 0)
    {
        // Fast groupshared broadcast when block size is a multiple of 8x4 (4 loads per 128 threads)
        [branch]
        if ((nBlkSizeX & 7) == 0 && (nBlkSizeY & 3) == 0)
        {
            if (GI < 4)
            {
                uint qx = (Gid.x << 4) + ((GI & 1) << 3);
                uint qy = (Gid.y << 3) + ((GI >> 1) << 2);
                uint bx = min(qx / nBlkSizeX, nBlkX - 1);
                uint by = min(qy / nBlkSizeY, nBlkY - 1);
                gs_MvF[GI] = g_MotionVectorsF.Load(int3(bx, by, 0));
                gs_MvB[GI] = g_MotionVectorsB.Load(int3(bx, by, 0));
            }
            GroupMemoryBarrierWithGroupSync();

            if (DTid.x >= width || DTid.y >= height)
                return;

            uint qIdx = ((GTid.y >> 2) << 1) | (GTid.x >> 3);
            rawMvF = gs_MvF[qIdx];
            rawMvB = gs_MvB[qIdx];
        }
        else
        {
            if (DTid.x >= width || DTid.y >= height)
                return;

            uint bx = min(DTid.x / nBlkSizeX, nBlkX - 1);
            uint by = min(DTid.y / nBlkSizeY, nBlkY - 1);
            rawMvF = g_MotionVectorsF.Load(int3(bx, by, 0));
            rawMvB = g_MotionVectorsB.Load(int3(bx, by, 0));
        }
    }
    else
    {
        if (DTid.x >= width || DTid.y >= height)
            return;

        // Continuous flow interpolation (MFlowFps)
        float2 normCoord = (float2(DTid.xy) + 0.5f) / float2(width, height);
        rawMvF = g_MotionVectorsF.SampleLevel(g_LinearClamp, normCoord, 0);
        rawMvB = g_MotionVectorsB.SampleLevel(g_LinearClamp, normCoord, 0);
    }

    // Displacement and sampling coordinates in FP32 for exact subpixel accuracy
    float2 invDims = float2(1.0f / (float)width, 1.0f / (float)height);
    float2 pixelCenter = float2(DTid.xy) + 0.5f;

    float2 dispScale = (1.0f / nPel) * float2(mvScaleX, mvScaleY);
    float2 dispF = rawMvF * dispScale;
    float2 dispB = rawMvB * dispScale;

    float2 warpedCoordF = (pixelCenter + dispF * time) * invDims;
    float2 warpedCoordB = (pixelCenter + dispB * (1.0f - time)) * invDims;

    // Subpixel bilinear motion-compensated samples (evaluated in min16float)
    min16float pMCF = (min16float)g_SrcPlane.SampleLevel(g_LinearClamp, warpedCoordF, 0);
    min16float pMCB = (min16float)g_RefPlane.SampleLevel(g_LinearClamp, warpedCoordB, 0);
    min16float halfTime = (min16float)time;

    min16float finalVal;
    [branch]
    if (maskMode == 0)
    {
        // Mode 0: Pure motion-compensated blend (bypasses static plane texture loads)
        finalVal = lerp(pMCF, pMCB, halfTime);
    }
    else
    {
        // Uncompensated static samples at current pixel (x, y)
        min16float staticF = (min16float)g_SrcPlane.Load(int3(DTid.xy, 0));
        min16float staticB = (min16float)g_RefPlane.Load(int3(DTid.xy, 0));

        if (maskMode == 1)
        {
            // Mode 1: Static Median
            min16float mca = lerp(pMCF, pMCB, halfTime);
            finalVal = clamp(mca, min(staticF, staticB), max(staticF, staticB));
        }
        else
        {
            // Mode 2: Dynamic Median (Exact parity with CPU NEON MBlockFps)
            min16float avg = lerp(staticF, staticB, halfTime);
            finalVal = clamp(avg, min(pMCB, pMCF), max(pMCB, pMCF));
        }
    }

    g_OutPlane[DTid.xy] = (float)saturate(finalVal);
}

// =============================================================================
// Compute Shader Entry Point: FlowWarpChromaCS (Fused U + V Chroma Planes)
// Computes motion vector coordinates once and synthesizes U & V in dual FP16
// =============================================================================

[numthreads(16, 8, 1)]
void FlowWarpChromaCS(uint3 DTid : SV_DispatchThreadID, uint3 Gid : SV_GroupID, uint3 GTid : SV_GroupThreadID, uint GI : SV_GroupIndex)
{
    float2 rawMvF, rawMvB;

    [branch]
    if (flowMode == 0)
    {
        [branch]
        if ((nBlkSizeX & 7) == 0 && (nBlkSizeY & 3) == 0)
        {
            if (GI < 4)
            {
                uint qx = (Gid.x << 4) + ((GI & 1) << 3);
                uint qy = (Gid.y << 3) + ((GI >> 1) << 2);
                uint bx = min(qx / nBlkSizeX, nBlkX - 1);
                uint by = min(qy / nBlkSizeY, nBlkY - 1);
                gs_MvF[GI] = g_MotionVectorsF.Load(int3(bx, by, 0));
                gs_MvB[GI] = g_MotionVectorsB.Load(int3(bx, by, 0));
            }
            GroupMemoryBarrierWithGroupSync();

            if (DTid.x >= width || DTid.y >= height)
                return;

            uint qIdx = ((GTid.y >> 2) << 1) | (GTid.x >> 3);
            rawMvF = gs_MvF[qIdx];
            rawMvB = gs_MvB[qIdx];
        }
        else
        {
            if (DTid.x >= width || DTid.y >= height)
                return;

            uint bx = min(DTid.x / nBlkSizeX, nBlkX - 1);
            uint by = min(DTid.y / nBlkSizeY, nBlkY - 1);
            rawMvF = g_MotionVectorsF.Load(int3(bx, by, 0));
            rawMvB = g_MotionVectorsB.Load(int3(bx, by, 0));
        }
    }
    else
    {
        if (DTid.x >= width || DTid.y >= height)
            return;

        float2 normCoord = (float2(DTid.xy) + 0.5f) / float2(width, height);
        rawMvF = g_MotionVectorsF.SampleLevel(g_LinearClamp, normCoord, 0);
        rawMvB = g_MotionVectorsB.SampleLevel(g_LinearClamp, normCoord, 0);
    }

    float2 invDims = float2(1.0f / (float)width, 1.0f / (float)height);
    float2 pixelCenter = float2(DTid.xy) + 0.5f;

    float2 dispScale = (1.0f / nPel) * float2(mvScaleX, mvScaleY);
    float2 dispF = rawMvF * dispScale;
    float2 dispB = rawMvB * dispScale;

    float2 warpedCoordF = (pixelCenter + dispF * time) * invDims;
    float2 warpedCoordB = (pixelCenter + dispB * (1.0f - time)) * invDims;

    // Sample U and V planes simultaneously into packed FP16 vector2
    min16float2 pMCF = min16float2(
        (min16float)g_SrcPlane.SampleLevel(g_LinearClamp, warpedCoordF, 0),
        (min16float)g_SrcPlaneV.SampleLevel(g_LinearClamp, warpedCoordF, 0)
    );
    min16float2 pMCB = min16float2(
        (min16float)g_RefPlane.SampleLevel(g_LinearClamp, warpedCoordB, 0),
        (min16float)g_RefPlaneV.SampleLevel(g_LinearClamp, warpedCoordB, 0)
    );
    min16float halfTime = (min16float)time;

    min16float2 finalUV;
    [branch]
    if (maskMode == 0)
    {
        finalUV = lerp(pMCF, pMCB, halfTime);
    }
    else
    {
        min16float2 staticF = min16float2(
            (min16float)g_SrcPlane.Load(int3(DTid.xy, 0)),
            (min16float)g_SrcPlaneV.Load(int3(DTid.xy, 0))
        );
        min16float2 staticB = min16float2(
            (min16float)g_RefPlane.Load(int3(DTid.xy, 0)),
            (min16float)g_RefPlaneV.Load(int3(DTid.xy, 0))
        );

        if (maskMode == 1)
        {
            min16float2 mca = lerp(pMCF, pMCB, halfTime);
            finalUV = clamp(mca, min(staticF, staticB), max(staticF, staticB));
        }
        else
        {
            min16float2 avg = lerp(staticF, staticB, halfTime);
            finalUV = clamp(avg, min(pMCB, pMCF), max(pMCB, pMCF));
        }
    }

    float2 outUV = (float2)saturate(finalUV);
    g_OutPlane[DTid.xy]  = outUV.x;
    g_OutPlaneV[DTid.xy] = outUV.y;
}

// =============================================================================
// Compute Shader Entry Point: UnpackMotionVectorsCS
// Converts raw 12-byte GPU block results to Texture2D<float2> for hardware sampling
// =============================================================================

[numthreads(8, 8, 1)]
void UnpackMotionVectorsCS(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= unpackBlkX || DTid.y >= unpackBlkY)
        return;

    uint blockIdx = DTid.y * unpackBlkX + DTid.x;
    uint byteOffset = blockIdx * 12;

    int vx = asint(g_RawBlockResults.Load(byteOffset));
    int vy = asint(g_RawBlockResults.Load(byteOffset + 4));

    g_OutMvTexture[DTid.xy] = float2(vx, vy);
}

// =============================================================================
// Compute Shader Entry Point: FlowBlendFallbackCS (Luma Plane)
// Pure frame blend fallback for scene changes or unusable motion vectors
// =============================================================================

[numthreads(16, 8, 1)]
void FlowBlendFallbackCS(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= blendWidth || DTid.y >= blendHeight)
        return;

    min16float sF = (min16float)g_BlendSrcPlane[DTid.xy];
    min16float sB = (min16float)g_BlendRefPlane[DTid.xy];

    g_BlendOutPlane[DTid.xy] = (float)lerp(sF, sB, (min16float)blendTime);
}

// =============================================================================
// Compute Shader Entry Point: FlowBlendChromaCS (Fused U + V Chroma Planes)
// =============================================================================

[numthreads(16, 8, 1)]
void FlowBlendChromaCS(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= blendWidth || DTid.y >= blendHeight)
        return;

    min16float2 sF = min16float2((min16float)g_BlendSrcPlane[DTid.xy], (min16float)g_BlendSrcPlaneV[DTid.xy]);
    min16float2 sB = min16float2((min16float)g_BlendRefPlane[DTid.xy], (min16float)g_BlendRefPlaneV[DTid.xy]);

    float2 outUV = (float2)lerp(sF, sB, (min16float)blendTime);
    g_BlendOutPlane[DTid.xy]  = outUV.x;
    g_BlendOutPlaneV[DTid.xy] = outUV.y;
}
