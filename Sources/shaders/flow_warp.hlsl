// HLSL DirectCompute Frame Synthesis Shader (Shader Model 5.0 / Direct3D 12)
// Direct3D 12 Gather-Based Subpixel Motion Warping & Frame Synthesis (MFlowFps)
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
// Resources: Warp & Synthesis Pass
// -----------------------------------------------------------------------------

Texture2D<float>   g_SrcPlane        : register(t0); // Frame N (Source / Left frame)
Texture2D<float>   g_RefPlane        : register(t1); // Frame N+1 (Reference / Right frame)
Texture2D<float2>  g_MotionVectorsF  : register(t2); // Forward motion vectors (coarse block grid)
Texture2D<float2>  g_MotionVectorsB  : register(t3); // Backward motion vectors (coarse block grid)

RWTexture2D<float> g_OutPlane        : register(u0); // Interpolated output plane

SamplerState       g_LinearClamp     : register(s0); // Hardware bilinear sampler with border clamp
SamplerState       g_PointClamp      : register(s1); // Point / nearest-neighbor sampler

// -----------------------------------------------------------------------------
// Resources: Motion Vector Unpack Pass
// -----------------------------------------------------------------------------

ByteAddressBuffer  g_RawBlockResults : register(t0); // 12 bytes per block from motion_search_cs
RWTexture2D<float2> g_OutMvTexture   : register(u0); // 2D Vector texture for hardware bilinear sampling

// -----------------------------------------------------------------------------
// Resources: Direct Frame Blend Fallback Pass (Scene Change / Vector Unusable)
// -----------------------------------------------------------------------------

Texture2D<float>   g_BlendSrcPlane   : register(t0);
Texture2D<float>   g_BlendRefPlane   : register(t1);
RWTexture2D<float> g_BlendOutPlane   : register(u0);

// =============================================================================
// Compute Shader Entry Point: FlowWarpCS
// Gather-based subpixel warping with hardware bilinear texture filtering
// =============================================================================

[numthreads(16, 16, 1)]
void FlowWarpCS(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= width || DTid.y >= height)
        return;

    // 1. Fetch raw motion vectors for current pixel
    float2 rawMvF;
    float2 rawMvB;

    if (flowMode == 0)
    {
        // Block-based discrete vector mapping (MBlockFps exact match)
        uint bx = min(DTid.x / nBlkSizeX, nBlkX - 1);
        uint by = min(DTid.y / nBlkSizeY, nBlkY - 1);
        rawMvF = g_MotionVectorsF.Load(int3(bx, by, 0));
        rawMvB = g_MotionVectorsB.Load(int3(bx, by, 0));
    }
    else
    {
        // Continuous flow interpolation (MFlowFps)
        float2 normCoord = (float2(DTid.xy) + 0.5f) / float2(width, height);
        rawMvF = g_MotionVectorsF.SampleLevel(g_LinearClamp, normCoord, 0);
        rawMvB = g_MotionVectorsB.SampleLevel(g_LinearClamp, normCoord, 0);
    }

    // Convert motion vectors from nPel units to plane pixel displacement
    // mvScale accounts for chroma subsampling (e.g. 0.5 for YUV420 chroma)
    float2 dispF = (rawMvF / nPel) * float2(mvScaleX, mvScaleY);
    float2 dispB = (rawMvB / nPel) * float2(mvScaleX, mvScaleY);

    // Warped sampling coordinates in Frame N (Src) and Frame N+1 (Ref)
    // Forward displacement in src (Frame 0) moves along vector proportional to time t
    // Backward displacement in ref (Frame 1) moves along vector proportional to (1 - t)
    float2 warpedCoordF = (float2(DTid.xy) + 0.5f + dispF * time) / float2(width, height);
    float2 warpedCoordB = (float2(DTid.xy) + 0.5f + dispB * (1.0f - time)) / float2(width, height);

    // Subpixel bilinear motion-compensated samples
    float pMCF = g_SrcPlane.SampleLevel(g_LinearClamp, warpedCoordF, 0);
    float pMCB = g_RefPlane.SampleLevel(g_LinearClamp, warpedCoordB, 0);

    // Uncompensated static samples at current pixel (x, y)
    float staticF = g_SrcPlane.Load(int3(DTid.xy, 0));
    float staticB = g_RefPlane.Load(int3(DTid.xy, 0));

    // Static temporal cross-fade between Frame 0 and Frame 1
    float avg = lerp(staticF, staticB, time);

    float finalVal;

    if (maskMode == 0)
    {
        // Mode 0: Pure motion-compensated blend
        finalVal = lerp(pMCF, pMCB, time);
    }
    else if (maskMode == 1)
    {
        // Mode 1: Static Median
        float mca = lerp(pMCF, pMCB, time);
        finalVal = clamp(mca, min(staticF, staticB), max(staticF, staticB));
    }
    else
    {
        // Mode 2: Dynamic Median (Exact parity with CPU NEON MBlockFps)
        // dyn = MEDIAN(avg, pMCB, pMCF)
        finalVal = clamp(avg, min(pMCB, pMCF), max(pMCB, pMCF));
    }

    g_OutPlane[DTid.xy] = saturate(finalVal);
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
// Compute Shader Entry Point: FlowBlendFallbackCS
// Pure frame blend fallback for scene changes or unusable motion vectors
// =============================================================================

[numthreads(16, 16, 1)]
void FlowBlendFallbackCS(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x >= blendWidth || DTid.y >= blendHeight)
        return;

    float sF = g_BlendSrcPlane[DTid.xy];
    float sB = g_BlendRefPlane[DTid.xy];

    g_BlendOutPlane[DTid.xy] = lerp(sF, sB, blendTime);
}
