// HLSL DirectCompute Motion Search Shader (Shader Model 5.0 / Direct3D 12)
// Offloaded to Qualcomm Adreno GPU for Zero-CPU Motion Estimation

cbuffer MotionParams : register(b0)
{
    uint nBlkX;                  // Number of blocks horizontally
    uint nBlkY;                  // Number of blocks vertically
    uint nBlkSizeX;              // Block width in pixels
    uint nBlkSizeY;              // Block height in pixels
    uint nOverlapX;              // Block overlap X
    uint nOverlapY;              // Block overlap Y
    uint nHPadding;              // Horizontal padding in frame
    uint nVPadding;              // Vertical padding in frame
    uint nSrcPitch;              // Pitch of source plane in bytes
    uint nRefPitch;              // Pitch of reference plane in bytes
    uint nPel;                   // Pel accuracy: 1 = integer, 2 = half-pel
    uint nLogScale;              // Plane pyramid level scale (0 = finest)
    uint searchType;             // SearchType enum (1=OneTime, 2=NStep, 4=Log, 8=Exhaustive, 16=Hex2, 32=UMH)
    int  nSearchParam;           // Search radius/parameter in pel units
    int  nLambda;                // Lambda cost multiplier
    uint lsad;                   // Limit SAD for lambda
    int  pnew;                   // Penalty for new vector (scaled by 256)
    int  pzero;                  // Penalty for zero vector (scaled by 256)
    int  pglobal;                // Penalty for global vector (scaled by 256)
    int  fieldShift;             // Field shift for interlaced or field-based processing
    int  globalMvX;              // Global predictor X in pel units
    int  globalMvY;              // Global predictor Y in pel units
    uint verybigSAD;             // Sentinel max SAD (e.g. 0x07FFFFFF)
    uint extendedWidth;          // Width including padding
    uint extendedHeight;         // Height including padding
    uint temporalPredictorValid; // 1 if temporal predictor is provided
    uint hasUpperPredictor;      // 1 if upper pyramid level predictor is provided
    uint bits_per_pixel;         // Pixel bit depth (8, 10, 16)
};

// Input frame plane byte buffers
ByteAddressBuffer g_SrcPlane : register(t0);
ByteAddressBuffer g_RefPlane : register(t1);

// Optional predictor buffers (x, y as int2)
StructuredBuffer<int2> g_PredBuffer : register(t2);
StructuredBuffer<int2> g_TemporalPredBuffer : register(t3);

// Output motion vectors buffer: 12 bytes per block (x: int32, y: int32, sad: uint32)
RWByteAddressBuffer g_OutBuffer : register(u0);

// Helper: load 4 bytes with arbitrary byte alignment from ByteAddressBuffer
uint Load4Bytes(ByteAddressBuffer buf, uint byteOffset)
{
    uint alignedOffset = byteOffset & ~3;
    uint shift = (byteOffset & 3) * 8;
    uint d0 = buf.Load(alignedOffset);
    [flatten]
    if (shift == 0)
    {
        return d0;
    }
    else
    {
        uint d1 = buf.Load(alignedOffset + 4);
        return (d0 >> shift) | (d1 << (32 - shift));
    }
}

// Helper: load a single 8-bit byte from ByteAddressBuffer
uint Load1Byte(ByteAddressBuffer buf, uint byteOffset)
{
    uint alignedOffset = byteOffset & ~3;
    uint shift = (byteOffset & 3) * 8;
    uint d0 = buf.Load(alignedOffset);
    return (d0 >> shift) & 0xFF;
}

// 4-byte packed SAD
uint Sad4(uint a, uint b)
{
    uint diff0 = (uint)abs((int)(a & 0xFF) - (int)(b & 0xFF));
    uint diff1 = (uint)abs((int)((a >> 8) & 0xFF) - (int)((b >> 8) & 0xFF));
    uint diff2 = (uint)abs((int)((a >> 16) & 0xFF) - (int)((b >> 16) & 0xFF));
    uint diff3 = (uint)abs((int)((a >> 24) & 0xFF) - (int)((b >> 24) & 0xFF));
    return diff0 + diff1 + diff2 + diff3;
}

// Computes Block SAD for displacement (vx, vy) in pel units
uint ComputeBlockSAD(uint x_src, uint y_src, int vx, int vy)
{
    uint sad = 0;
    uint subplaneOffset = 0;
    int ref_base_x = 0;
    int ref_base_y = 0;

    if (nPel == 1)
    {
        ref_base_x = (int)x_src + vx;
        ref_base_y = (int)y_src + vy;
        subplaneOffset = 0;
    }
    else // nPel == 2
    {
        int fullRefX = ((int)x_src << 1) + vx;
        int fullRefY = ((int)y_src << 1) + vy;
        uint subplane = (uint)(fullRefX & 1) | ((uint)(fullRefY & 1) << 1);
        ref_base_x = fullRefX >> 1;
        ref_base_y = fullRefY >> 1;
        subplaneOffset = subplane * (extendedHeight * nRefPitch);
    }

    uint wordCount = nBlkSizeX >> 2;
    uint byteTail = nBlkSizeX & 3;

    uint srcRowByte = y_src * nSrcPitch + x_src;
    uint refRowByte = subplaneOffset + (uint)ref_base_y * nRefPitch + (uint)ref_base_x;

    for (uint dy = 0; dy < nBlkSizeY; dy++)
    {
        // Process 4 pixels at a time
        for (uint w = 0; w < wordCount; w++)
        {
            uint sBytes = Load4Bytes(g_SrcPlane, srcRowByte + (w << 2));
            uint rBytes = Load4Bytes(g_RefPlane, refRowByte + (w << 2));
            sad += Sad4(sBytes, rBytes);
        }

        // Process remaining tail bytes if block width is not a multiple of 4
        for (uint t = 0; t < byteTail; t++)
        {
            uint sVal = Load1Byte(g_SrcPlane, srcRowByte + (wordCount << 2) + t);
            uint rVal = Load1Byte(g_RefPlane, refRowByte + (wordCount << 2) + t);
            sad += (uint)abs((int)sVal - (int)rVal);
        }

        srcRowByte += nSrcPitch;
        refRowByte += nRefPitch;
    }

    return sad;
}

// Cost function matching MVTools MotionDistorsion and penalty weights
uint EvalCost(int vx, int vy, uint sad, int predX, int predY, int penalty)
{
    int d1 = predX - vx;
    int d2 = predY - vy;
    int dist = d1 * d1 + d2 * d2;
    uint distCost = (uint)((nLambda * dist) >> 8);
    uint penCost = (uint)((penalty * (int)sad) >> 8);
    return sad + distCost + penCost;
}

[numthreads(8, 8, 1)]
void CSMain(uint3 id : SV_DispatchThreadID)
{
    uint blkx = id.x;
    uint blky = id.y;

    if (blkx >= nBlkX || blky >= nBlkY)
    {
        return;
    }

    uint blkIdx = blky * nBlkX + blkx;

    // Block upper-left coordinate in extended frame
    uint x_src = nHPadding + blkx * (nBlkSizeX - nOverlapX);
    uint y_src = nVPadding + blky * (nBlkSizeY - nOverlapY);

    // Compute search bounds in pel units
    int nHPaddingScaled = (int)(nHPadding >> nLogScale);
    int nVPaddingScaled = (int)(nVPadding >> nLogScale);
    int nDxMax = (int)nPel * (int)(extendedWidth - x_src - nBlkSizeX - nHPadding + nHPaddingScaled);
    int nDyMax = (int)nPel * (int)(extendedHeight - y_src - nBlkSizeY - nVPadding + nVPaddingScaled);
    int nDxMin = -(int)nPel * (int)(x_src - nHPadding + nHPaddingScaled);
    int nDyMin = -(int)nPel * (int)(y_src - nVPadding + nVPaddingScaled);

    int2 bestMV = int2(0, fieldShift);
    uint bestSAD = verybigSAD;
    uint minCost = verybigSAD;

    // --- Candidate 1: Zero Vector (shifted by fieldShift) ---
    int2 zeroMV = int2(0, fieldShift);
    zeroMV.x = clamp(zeroMV.x, nDxMin, nDxMax);
    zeroMV.y = clamp(zeroMV.y, nDyMin, nDyMax);
    uint sadZero = ComputeBlockSAD(x_src, y_src, zeroMV.x, zeroMV.y);
    uint costZero = sadZero + (uint)((pzero * (int)sadZero) >> 8);
    bestMV = zeroMV;
    bestSAD = sadZero;
    minCost = costZero;

    // --- Candidate 2: Global Predictor ---
    int2 globMV = int2(globalMvX, globalMvY);
    globMV.x = clamp(globMV.x, nDxMin, nDxMax);
    globMV.y = clamp(globMV.y, nDyMin, nDyMax);
    if (globMV.x != zeroMV.x || globMV.y != zeroMV.y)
    {
        uint sadG = ComputeBlockSAD(x_src, y_src, globMV.x, globMV.y);
        uint costG = sadG + (uint)((pglobal * (int)sadG) >> 8);
        if (costG < minCost)
        {
            bestMV = globMV;
            bestSAD = sadG;
            minCost = costG;
        }
    }

    // --- Candidate 3: Upper Level Hierarchical Predictor ---
    int2 upperPred = int2(0, 0);
    if (hasUpperPredictor != 0)
    {
        upperPred = g_PredBuffer[blkIdx];
        upperPred.x = clamp(upperPred.x, nDxMin, nDxMax);
        upperPred.y = clamp(upperPred.y, nDyMin, nDyMax);

        if ((upperPred.x != bestMV.x || upperPred.y != bestMV.y) &&
            (upperPred.x != zeroMV.x || upperPred.y != zeroMV.y))
        {
            uint sadU = ComputeBlockSAD(x_src, y_src, upperPred.x, upperPred.y);
            uint costU = EvalCost(upperPred.x, upperPred.y, sadU, upperPred.x, upperPred.y, pnew);
            if (costU < minCost)
            {
                bestMV = upperPred;
                bestSAD = sadU;
                minCost = costU;
            }
        }
    }

    // --- Candidate 4: Temporal Predictor ---
    if (temporalPredictorValid != 0)
    {
        int2 tempPred = g_TemporalPredBuffer[blkIdx];
        tempPred.x = clamp(tempPred.x, nDxMin, nDxMax);
        tempPred.y = clamp(tempPred.y, nDyMin, nDyMax);

        if (tempPred.x != bestMV.x || tempPred.y != bestMV.y)
        {
            uint sadT = ComputeBlockSAD(x_src, y_src, tempPred.x, tempPred.y);
            uint costT = EvalCost(tempPred.x, tempPred.y, sadT, bestMV.x, bestMV.y, pnew);
            if (costT < minCost)
            {
                bestMV = tempPred;
                bestSAD = sadT;
                minCost = costT;
            }
        }
    }

    // --- Local Motion Vector Search Refinement ---
    // If coarse predictor is already a near-perfect match (e.g. static background or smooth motion),
    // skip refinement search completely.
    if (hasUpperPredictor != 0 && bestSAD <= 128)
    {
        // Coarse predictor is already optimal
    }
    else
    {
        int searchRadius = (hasUpperPredictor != 0) ? max(1, nSearchParam) : max(1, nSearchParam * (int)nPel);
        int2 center = bestMV;
        int2 predictor = (hasUpperPredictor != 0) ? upperPred : center;

        // Small radius (<= 1) or EXHAUSTIVE: Perform full 2D grid evaluation
        if (searchRadius <= 1 || searchType == 8)
        {
            [loop]
            for (int dy = -searchRadius; dy <= searchRadius; dy++)
            {
                int cy = center.y + dy;
                if (cy < nDyMin || cy > nDyMax) continue;

                [loop]
                for (int dx = -searchRadius; dx <= searchRadius; dx++)
                {
                    if (dx == 0 && dy == 0) continue;
                    int cx = center.x + dx;
                    if (cx < nDxMin || cx > nDxMax) continue;

                    uint sad = ComputeBlockSAD(x_src, y_src, cx, cy);
                    uint cost = EvalCost(cx, cy, sad, predictor.x, predictor.y, pnew);
                    if (cost < minCost)
                    {
                        minCost = cost;
                        bestSAD = sad;
                        bestMV = int2(cx, cy);
                    }
                }
            }
        }
        else
        {
        // Hexagonal / Multi-step search for larger search radius
        static const int2 hexOffsets[6] = {
            int2(-2, 0), int2(2, 0),
            int2(-1, -2), int2(1, -2),
            int2(-1, 2), int2(1, 2)
        };

        int step = max(1, (int)((uint)searchRadius >> 1));
        int iterCount = 0;
        [loop]
        while (step >= 1 && iterCount < 6)
        {
            iterCount++;
            int2 bestCenter = center;
            [unroll]
            for (int i = 0; i < 6; i++)
            {
                int cx = center.x + hexOffsets[i].x * step;
                int cy = center.y + hexOffsets[i].y * step;
                if (cx < nDxMin || cx > nDxMax || cy < nDyMin || cy > nDyMax) continue;

                uint sad = ComputeBlockSAD(x_src, y_src, cx, cy);
                uint cost = EvalCost(cx, cy, sad, predictor.x, predictor.y, pnew);
                if (cost < minCost)
                {
                    minCost = cost;
                    bestSAD = sad;
                    bestCenter = int2(cx, cy);
                }
            }
            if (bestCenter.x == center.x && bestCenter.y == center.y)
            {
                step >>= 1; // refine to smaller step
            }
            else
            {
                center = bestCenter;
            }
        }

        // Final 1-pel cross refinement
        static const int2 crossOffsets[4] = {
            int2(-1, 0), int2(1, 0), int2(0, -1), int2(0, 1)
        };
        [unroll]
        for (int j = 0; j < 4; j++)
        {
            int cx = center.x + crossOffsets[j].x;
            int cy = center.y + crossOffsets[j].y;
            if (cx < nDxMin || cx > nDxMax || cy < nDyMin || cy > nDyMax) continue;

            uint sad = ComputeBlockSAD(x_src, y_src, cx, cy);
            uint cost = EvalCost(cx, cy, sad, predictor.x, predictor.y, pnew);
            if (cost < minCost)
            {
                minCost = cost;
                bestSAD = sad;
                center = int2(cx, cy);
            }
        }
        bestMV = center;
        }
    }

    // Output motion vector (X, Y, SAD) for this block (12 bytes per block)
    uint outOffset = blkIdx * 12;
    g_OutBuffer.Store3(outOffset, uint3(asuint(bestMV.x), asuint(bestMV.y), bestSAD));
}
