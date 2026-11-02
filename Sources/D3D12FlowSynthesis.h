#ifndef __D3D12_FLOW_SYNTHESIS_H__
#define __D3D12_FLOW_SYNTHESIS_H__

#include <cstdint>
#include <cstddef>
#include "types.h"

class MVClip;

class D3D12FlowSynthesis
{
public:
    static D3D12FlowSynthesis& GetInstance();

    bool IsAvailable();
    void SetEnabled(bool enabled);
    bool IsEnabled() const;

    bool SynthesizeFrame(
        const uint8_t* pSrc[3], const int nSrcPitches[3],
        const uint8_t* pRef[3], const int nRefPitches[3],
        uint8_t* pDst[3], const int nDstPitches[3],
        int width, int height,
        int widthUV, int heightUV,
        int planecount,
        int time256,
        int nPel,
        int nBlkX, int nBlkY,
        const MVClip& mvClipB,
        const MVClip& mvClipF,
        int maskMode = 2,
        int blkSizeX = 16,
        int blkSizeY = 16,
        int flowMode = 0
    );

private:
    D3D12FlowSynthesis();
    ~D3D12FlowSynthesis();
    D3D12FlowSynthesis(const D3D12FlowSynthesis&) = delete;
    D3D12FlowSynthesis& operator=(const D3D12FlowSynthesis&) = delete;

    struct Impl;
    Impl* pImpl;
};

#endif // __D3D12_FLOW_SYNTHESIS_H__
