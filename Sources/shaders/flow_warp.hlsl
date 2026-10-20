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
    uint   maskMode;       // 0 = simple cross-fade, 1 = occlusion-aware, 2 = advanced consistency
    float  occlusionNorm;  // Occlusion threshold / normalization factor
};

cbuffer UnpackParams : register(b0)
{
    uint nBlkX;            // Block count horizontally
    uint nBlkY;            // Block count vertically
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

    // Normalized UV coordinate of current pixel center in output frame
    float2 normCoord = (float2(DTid.xy) + 0.5f) / float2(width, height);

    // Hardware bilinear fetch of coarse motion vector field at pixel location
    float2 rawMvF = g_MotionVectorsF.SampleLevel(g_LinearClamp, normCoord, 0);
    float2 rawMvB = g_MotionVectorsB.SampleLevel(g_LinearClamp, normCoord, 0);

    // Convert motion vectors from nPel units to plane pixel displacement
    // mvScale accounts for chroma subsampling (e.g. 0.5 for YUV420 chroma)
    float2 dispF = (rawMvF / nPel) * float2(mvScaleX, mvScaleY);
    float2 dispB = (rawMvB / nPel) * float2(mvScaleX, mvScaleY);

    // Warped sampling coordinates in Frame N and Frame N+1
    // Forward displacement moves along vector proportional to time t
    // Backward displacement moves along vector proportional to (1 - t)
    float2 warpedCoordF = (float2(DTid.xy) + 0.5f + dispF * time) / float2(width, height);
    float2 warpedCoordB = (float2(DTid.xy) + 0.5f + dispB * (1.0f - time)) / float2(width, height);

    // Hardware subpixel bilinear sampling of source and reference planes
    float sampleF = g_SrcPlane.SampleLevel(g_LinearClamp, warpedCoordF, 0);
    float sampleB = g_RefPlane.SampleLevel(g_LinearClamp, warpedCoordB, 0);

    float finalVal;

    [branch]
    if (maskMode == 0)
    {
        // Simple fast motion-compensated linear cross-fade
        finalVal = lerp(sampleF, sampleB, time);
    }
    else
    {
        // Bidirectional consistency and occlusion detection
        // Sample opposing vector at the warped locations
        float2 mvB_at_F = g_MotionVectorsB.SampleLevel(g_LinearClamp, warpedCoordF, 0);
        float2 dispB_at_F = (mvB_at_F / nPel) * float2(mvScaleX, mvScaleY);
        float errF = length(dispF + dispB_at_F);

        float2 mvF_at_B = g_MotionVectorsF.SampleLevel(g_LinearClamp, warpedCoordB, 0);
        float2 dispF_at_B = (mvF_at_B / nPel) * float2(mvScaleX, mvScaleY);
        float errB = length(dispB + dispF_at_B);

        // Photometric difference between predictions
        float photoErr = abs(sampleF - sampleB);

        // Combined occlusion metrics
        float occF = saturate(errF * occlusionNorm + photoErr * 0.5f);
        float occB = saturate(errB * occlusionNorm + photoErr * 0.5f);

        // When forward motion is occluded (occF -> 1), fall back to backward prediction
        // When backward motion is occluded (occB -> 1), fall back to forward prediction
        float contribF = lerp(sampleF, sampleB, occF);
        float contribB = lerp(sampleB, sampleF, occB);

        finalVal = lerp(contribF, contribB, time);
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
    if (DTid.x >= nBlkX || DTid.y >= nBlkY)
        return;

    uint blockIdx = DTid.y * nBlkX + DTid.x;
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
