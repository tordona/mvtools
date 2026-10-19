#ifndef __D3D12_MOTION_SEARCH_H__
#define __D3D12_MOTION_SEARCH_H__

#include <cstdint>
#include <cstddef>
#include "types.h"
#include "VECTOR.h"
#include "SearchType.h"

class MVFrame;

struct alignas(16) D3D12MotionParams
{
    uint32_t nBlkX;
    uint32_t nBlkY;
    uint32_t nBlkSizeX;
    uint32_t nBlkSizeY;
    uint32_t nOverlapX;
    uint32_t nOverlapY;
    uint32_t nHPadding;
    uint32_t nVPadding;
    uint32_t nSrcPitch;
    uint32_t nRefPitch;
    uint32_t nPel;
    uint32_t nLogScale;
    uint32_t searchType;
    int32_t  nSearchParam;
    int32_t  nLambda;
    uint32_t lsad;
    int32_t  pnew;
    int32_t  pzero;
    int32_t  pglobal;
    int32_t  fieldShift;
    int32_t  globalMvX;
    int32_t  globalMvY;
    uint32_t verybigSAD;
    uint32_t extendedWidth;
    uint32_t extendedHeight;
    uint32_t temporalPredictorValid;
    uint32_t hasUpperPredictor;
    uint32_t bits_per_pixel;
};

struct D3D12BlockResult
{
    int32_t x;
    int32_t y;
    uint32_t sad;
};

class D3D12MotionSearch
{
public:
    static D3D12MotionSearch& GetInstance();

    bool IsAvailable();
    void SetEnabled(bool enabled);
    bool IsEnabled() const;

    bool SearchMVs(
        MVFrame* pSrcFrame,
        MVFrame* pRefFrame,
        int nBlkX, int nBlkY,
        int nBlkSizeX, int nBlkSizeY,
        int nOverlapX, int nOverlapY,
        int nPel, int nLogScale,
        SearchType searchType, int nSearchParam,
        int lambda, sad_t lsad,
        int pnew, int pzero, int pglobal,
        int fieldShift,
        int globalMvX, int globalMvY,
        uint32_t verybigSAD,
        bool temporal, const int* vecPrev,
        bool hasUpperPredictor, const VECTOR* upperPredictors,
        int* pOutArray, short* pOutFileBuf, VECTOR* pOutVectors
    );

private:
    D3D12MotionSearch();
    ~D3D12MotionSearch();
    D3D12MotionSearch(const D3D12MotionSearch&) = delete;
    D3D12MotionSearch& operator=(const D3D12MotionSearch&) = delete;

    struct Impl;
    Impl* pImpl;
};

#endif // __D3D12_MOTION_SEARCH_H__
