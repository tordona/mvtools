#ifndef WINVER
#define WINVER 0x0A00
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#ifndef NTDDI_VERSION
#define NTDDI_VERSION 0x0A000000
#endif

#include "D3D12MotionSearch.h"
#include "MVFrame.h"
#include "MVPlane.h"
#include "FakePlaneOfBlocks.h"
#include "shaders/motion_search_cso.h"

#include <windows.h>
#include <d3d12.h>
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <mutex>
#include <vector>
#include <algorithm>
#include <cstdio>

#pragma comment(lib, "d3d12.lib")
#pragma comment(lib, "dxgi.lib")

using Microsoft::WRL::ComPtr;

struct D3D12MotionSearch::Impl
{
    std::mutex m_mutex;
    bool m_initialized = false;
    bool m_available = false;
    bool m_enabled = false;

    ComPtr<IDXGIFactory6> m_factory;
    ComPtr<IDXGIAdapter1> m_adapter;
    ComPtr<ID3D12Device> m_device;
    ComPtr<ID3D12CommandQueue> m_queue;
    ComPtr<ID3D12CommandAllocator> m_cmdAlloc;
    ComPtr<ID3D12GraphicsCommandList> m_cmdList;
    ComPtr<ID3D12RootSignature> m_rootSig;
    ComPtr<ID3D12PipelineState> m_pso;
    ComPtr<ID3D12Fence> m_fence;
    HANDLE m_fenceEvent = nullptr;
    uint64_t m_fenceValue = 0;

    struct PlaneCacheEntry
    {
        ComPtr<ID3D12Resource> buffer;
        void* pMapped = nullptr;
        size_t bufferSize = 0;
        const uint8_t* pPtr = nullptr;
        size_t size = 0;
        uint64_t sample0 = 0;
        uint64_t sample1 = 0;
        uint64_t sample2 = 0;
        uint64_t sample3 = 0;
        uint64_t sample4 = 0;
        uint64_t lruCounter = 0;
    };

    // Unified 6-slot plane cache (eliminates ping-pong cache thrashing across MAnalyse and MRecalculate)
    static constexpr int PLANE_CACHE_SLOTS = 6;
    PlaneCacheEntry m_planeCache[PLANE_CACHE_SLOTS];
    uint64_t m_lruTick = 0;

    int GetOrUploadPlane(const uint8_t* pPlane, size_t size, int excludeSlot)
    {
        uint64_t s0 = 0, s1 = 0, s2 = 0, s3 = 0, s4 = 0;
        if (size >= 8 && pPlane)
        {
            s0 = *(const uint64_t*)(pPlane);
            s1 = *(const uint64_t*)(pPlane + (size >> 2));
            s2 = *(const uint64_t*)(pPlane + (size >> 1));
            s3 = *(const uint64_t*)(pPlane + ((size * 3) >> 2));
            s4 = *(const uint64_t*)(pPlane + size - 8);
        }

        // 1. Look for existing cache hit
        for (int i = 0; i < PLANE_CACHE_SLOTS; i++)
        {
            if (m_planeCache[i].buffer &&
                m_planeCache[i].pPtr == pPlane &&
                m_planeCache[i].size == size &&
                m_planeCache[i].sample0 == s0 &&
                m_planeCache[i].sample1 == s1 &&
                m_planeCache[i].sample2 == s2 &&
                m_planeCache[i].sample3 == s3 &&
                m_planeCache[i].sample4 == s4)
            {
                m_planeCache[i].lruCounter = ++m_lruTick;
                return i;
            }
        }

        // 2. Cache miss: select LRU slot (avoiding excludeSlot)
        int selectedSlot = -1;
        uint64_t minTick = UINT64_MAX;
        for (int i = 0; i < PLANE_CACHE_SLOTS; i++)
        {
            if (i == excludeSlot) continue;
            if (!m_planeCache[i].buffer)
            {
                selectedSlot = i;
                break;
            }
            if (m_planeCache[i].lruCounter < minTick)
            {
                minTick = m_planeCache[i].lruCounter;
                selectedSlot = i;
            }
        }

        if (selectedSlot < 0) return -1;

        PlaneCacheEntry& entry = m_planeCache[selectedSlot];
        if (entry.bufferSize < size || !entry.buffer || !entry.pMapped)
        {
            if (entry.buffer && entry.pMapped)
            {
                entry.buffer->Unmap(0, nullptr);
                entry.pMapped = nullptr;
            }
            entry.bufferSize = (size * 3) / 2;
            entry.buffer.Reset();
            if (FAILED(CreateBuffer(entry.bufferSize, D3D12_HEAP_TYPE_UPLOAD, D3D12_RESOURCE_STATE_GENERIC_READ, D3D12_RESOURCE_FLAG_NONE, &entry.buffer)))
            {
                return -1;
            }
            if (FAILED(entry.buffer->Map(0, nullptr, &entry.pMapped)) || !entry.pMapped)
            {
                entry.pMapped = nullptr;
                return -1;
            }
        }

        memcpy(entry.pMapped, pPlane, size);
        entry.pPtr = pPlane;
        entry.size = size;
        entry.sample0 = s0;
        entry.sample1 = s1;
        entry.sample2 = s2;
        entry.sample3 = s3;
        entry.sample4 = s4;
        entry.lruCounter = ++m_lruTick;

        return selectedSlot;
    }

    ComPtr<ID3D12Resource> m_predBuffer;
    ComPtr<ID3D12Resource> m_tempPredBuffer;
    ComPtr<ID3D12Resource> m_constBuffer;
    ComPtr<ID3D12Resource> m_dummyBuffer;
    ComPtr<ID3D12Resource> m_uavBuffer;
    ComPtr<ID3D12Resource> m_readbackBuffer;

    size_t m_predBufferSize = 0;
    size_t m_tempPredBufferSize = 0;
    size_t m_outBufferSize = 0;

    void* m_pConstMapped = nullptr;
    void* m_pReadbackMapped = nullptr;
    void* m_pPredMapped = nullptr;
    void* m_pTempPredMapped = nullptr;

    std::vector<int32_t> m_hostPred;
    std::vector<int32_t> m_hostTempPred;
    std::vector<D3D12BlockResult> m_hostResults;

    HRESULT CreateBuffer(size_t size, D3D12_HEAP_TYPE heapType, D3D12_RESOURCE_STATES initialState, D3D12_RESOURCE_FLAGS flags, ID3D12Resource** ppResource)
    {
        D3D12_HEAP_PROPERTIES heapProps = {};
        heapProps.Type = heapType;
        heapProps.CPUPageProperty = D3D12_CPU_PAGE_PROPERTY_UNKNOWN;
        heapProps.MemoryPoolPreference = D3D12_MEMORY_POOL_UNKNOWN;

        D3D12_RESOURCE_DESC desc = {};
        desc.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
        desc.Alignment = 0;
        desc.Width = (size + 255) & ~255;
        desc.Height = 1;
        desc.DepthOrArraySize = 1;
        desc.MipLevels = 1;
        desc.Format = DXGI_FORMAT_UNKNOWN;
        desc.SampleDesc.Count = 1;
        desc.SampleDesc.Quality = 0;
        desc.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
        desc.Flags = flags;

        return m_device->CreateCommittedResource(&heapProps, D3D12_HEAP_FLAG_NONE, &desc, initialState, nullptr, IID_PPV_ARGS(ppResource));
    }

    bool InitDevice()
    {
        if (m_initialized) return m_available;
        m_initialized = true;

        HRESULT hr = CreateDXGIFactory2(0, IID_PPV_ARGS(&m_factory));
        if (FAILED(hr)) return false;

        // Prefer high performance hardware GPU (Adreno on Snapdragon)
        for (UINT i = 0; m_factory->EnumAdapterByGpuPreference(i, DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE, IID_PPV_ARGS(&m_adapter)) != DXGI_ERROR_NOT_FOUND; ++i)
        {
            DXGI_ADAPTER_DESC1 desc;
            m_adapter->GetDesc1(&desc);
            if (!(desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE))
            {
                break;
            }
        }

        if (!m_adapter)
        {
            if (FAILED(m_factory->EnumAdapters1(0, &m_adapter))) return false;
        }

        hr = D3D12CreateDevice(m_adapter.Get(), D3D_FEATURE_LEVEL_11_0, IID_PPV_ARGS(&m_device));
        if (FAILED(hr)) return false;

        D3D12_COMMAND_QUEUE_DESC qDesc = {};
        qDesc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
        hr = m_device->CreateCommandQueue(&qDesc, IID_PPV_ARGS(&m_queue));
        if (FAILED(hr)) return false;

        // Root signature with direct root descriptors (no descriptor heap required)
        D3D12_ROOT_PARAMETER rootParams[6] = {};
        // 0: CBV b0 (MotionParams)
        rootParams[0].ParameterType = D3D12_ROOT_PARAMETER_TYPE_CBV;
        rootParams[0].Descriptor.ShaderRegister = 0;
        rootParams[0].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

        // 1: SRV t0 (SrcPlane)
        rootParams[1].ParameterType = D3D12_ROOT_PARAMETER_TYPE_SRV;
        rootParams[1].Descriptor.ShaderRegister = 0;
        rootParams[1].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

        // 2: SRV t1 (RefPlane)
        rootParams[2].ParameterType = D3D12_ROOT_PARAMETER_TYPE_SRV;
        rootParams[2].Descriptor.ShaderRegister = 1;
        rootParams[2].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

        // 3: SRV t2 (PredBuffer)
        rootParams[3].ParameterType = D3D12_ROOT_PARAMETER_TYPE_SRV;
        rootParams[3].Descriptor.ShaderRegister = 2;
        rootParams[3].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

        // 4: SRV t3 (TemporalPredBuffer)
        rootParams[4].ParameterType = D3D12_ROOT_PARAMETER_TYPE_SRV;
        rootParams[4].Descriptor.ShaderRegister = 3;
        rootParams[4].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

        // 5: UAV u0 (OutBuffer)
        rootParams[5].ParameterType = D3D12_ROOT_PARAMETER_TYPE_UAV;
        rootParams[5].Descriptor.ShaderRegister = 0;
        rootParams[5].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

        D3D12_ROOT_SIGNATURE_DESC rsDesc = {};
        rsDesc.NumParameters = 6;
        rsDesc.pParameters = rootParams;
        rsDesc.Flags = D3D12_ROOT_SIGNATURE_FLAG_NONE;

        ComPtr<ID3DBlob> rsBlob, rsError;
        hr = D3D12SerializeRootSignature(&rsDesc, D3D_ROOT_SIGNATURE_VERSION_1, &rsBlob, &rsError);
        if (FAILED(hr)) return false;

        hr = m_device->CreateRootSignature(0, rsBlob->GetBufferPointer(), rsBlob->GetBufferSize(), IID_PPV_ARGS(&m_rootSig));
        if (FAILED(hr)) return false;

        D3D12_COMPUTE_PIPELINE_STATE_DESC psoDesc = {};
        psoDesc.pRootSignature = m_rootSig.Get();
        psoDesc.CS = { g_MotionSearchCS, sizeof(g_MotionSearchCS) };
        hr = m_device->CreateComputePipelineState(&psoDesc, IID_PPV_ARGS(&m_pso));
        if (FAILED(hr)) return false;

        hr = m_device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&m_cmdAlloc));
        if (FAILED(hr)) return false;

        hr = m_device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, m_cmdAlloc.Get(), m_pso.Get(), IID_PPV_ARGS(&m_cmdList));
        if (FAILED(hr)) return false;
        m_cmdList->Close();

        hr = m_device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&m_fence));
        if (FAILED(hr)) return false;

        m_fenceEvent = CreateEvent(nullptr, FALSE, FALSE, nullptr);
        if (!m_fenceEvent) return false;

        CreateBuffer(256, D3D12_HEAP_TYPE_UPLOAD, D3D12_RESOURCE_STATE_GENERIC_READ, D3D12_RESOURCE_FLAG_NONE, &m_constBuffer);
        m_constBuffer->Map(0, nullptr, &m_pConstMapped);
        CreateBuffer(256, D3D12_HEAP_TYPE_UPLOAD, D3D12_RESOURCE_STATE_GENERIC_READ, D3D12_RESOURCE_FLAG_NONE, &m_dummyBuffer);

        m_available = true;
        return true;
    }

    bool EnsureBuffers(size_t blockCount)
    {
        if (!m_device || m_device->GetDeviceRemovedReason() != S_OK)
            return false;

        size_t predSize = blockCount * sizeof(int32_t) * 2;
        if (m_predBufferSize < predSize || !m_predBuffer || !m_pPredMapped)
        {
            if (m_predBuffer && m_pPredMapped)
            {
                m_predBuffer->Unmap(0, nullptr);
                m_pPredMapped = nullptr;
            }
            m_predBufferSize = (predSize * 3) / 2;
            m_predBuffer.Reset();
            if (FAILED(CreateBuffer(m_predBufferSize, D3D12_HEAP_TYPE_UPLOAD, D3D12_RESOURCE_STATE_GENERIC_READ, D3D12_RESOURCE_FLAG_NONE, &m_predBuffer)))
                return false;
            if (FAILED(m_predBuffer->Map(0, nullptr, &m_pPredMapped)) || !m_pPredMapped)
            {
                m_pPredMapped = nullptr;
                return false;
            }
        }

        if (m_tempPredBufferSize < predSize || !m_tempPredBuffer || !m_pTempPredMapped)
        {
            if (m_tempPredBuffer && m_pTempPredMapped)
            {
                m_tempPredBuffer->Unmap(0, nullptr);
                m_pTempPredMapped = nullptr;
            }
            m_tempPredBufferSize = (predSize * 3) / 2;
            m_tempPredBuffer.Reset();
            if (FAILED(CreateBuffer(m_tempPredBufferSize, D3D12_HEAP_TYPE_UPLOAD, D3D12_RESOURCE_STATE_GENERIC_READ, D3D12_RESOURCE_FLAG_NONE, &m_tempPredBuffer)))
                return false;
            if (FAILED(m_tempPredBuffer->Map(0, nullptr, &m_pTempPredMapped)) || !m_pTempPredMapped)
            {
                m_pTempPredMapped = nullptr;
                return false;
            }
        }

        size_t outSize = blockCount * sizeof(D3D12BlockResult);
        if (m_outBufferSize < outSize || !m_uavBuffer || !m_readbackBuffer || !m_pReadbackMapped)
        {
            if (m_readbackBuffer && m_pReadbackMapped)
            {
                m_readbackBuffer->Unmap(0, nullptr);
                m_pReadbackMapped = nullptr;
            }
            m_outBufferSize = (outSize * 3) / 2;
            m_uavBuffer.Reset();
            m_readbackBuffer.Reset();
            if (FAILED(CreateBuffer(m_outBufferSize, D3D12_HEAP_TYPE_DEFAULT, D3D12_RESOURCE_STATE_UNORDERED_ACCESS, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS, &m_uavBuffer)))
                return false;
            if (FAILED(CreateBuffer(m_outBufferSize, D3D12_HEAP_TYPE_READBACK, D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_FLAG_NONE, &m_readbackBuffer)))
                return false;
            if (FAILED(m_readbackBuffer->Map(0, nullptr, &m_pReadbackMapped)) || !m_pReadbackMapped)
            {
                m_pReadbackMapped = nullptr;
                return false;
            }
        }

        return true;
    }

    ~Impl()
    {
        for (int i = 0; i < PLANE_CACHE_SLOTS; i++)
        {
            if (m_planeCache[i].buffer && m_planeCache[i].pMapped)
            {
                m_planeCache[i].buffer->Unmap(0, nullptr);
                m_planeCache[i].pMapped = nullptr;
            }
        }
        if (m_constBuffer && m_pConstMapped)
        {
            m_constBuffer->Unmap(0, nullptr);
            m_pConstMapped = nullptr;
        }
        if (m_readbackBuffer && m_pReadbackMapped)
        {
            m_readbackBuffer->Unmap(0, nullptr);
            m_pReadbackMapped = nullptr;
        }
        if (m_predBuffer && m_pPredMapped)
        {
            m_predBuffer->Unmap(0, nullptr);
            m_pPredMapped = nullptr;
        }
        if (m_tempPredBuffer && m_pTempPredMapped)
        {
            m_tempPredBuffer->Unmap(0, nullptr);
            m_pTempPredMapped = nullptr;
        }
        if (m_fenceEvent)
        {
            CloseHandle(m_fenceEvent);
            m_fenceEvent = nullptr;
        }
    }
};

D3D12MotionSearch::D3D12MotionSearch()
    : pImpl(new Impl())
{
}

D3D12MotionSearch::~D3D12MotionSearch()
{
    delete pImpl;
}

D3D12MotionSearch& D3D12MotionSearch::GetInstance()
{
    static D3D12MotionSearch instance;
    return instance;
}

bool D3D12MotionSearch::IsAvailable()
{
    std::lock_guard<std::mutex> lock(pImpl->m_mutex);
    return pImpl->InitDevice() && pImpl->m_enabled && pImpl->m_device && (pImpl->m_device->GetDeviceRemovedReason() == S_OK);
}

void D3D12MotionSearch::SetEnabled(bool enabled)
{
    std::lock_guard<std::mutex> lock(pImpl->m_mutex);
    pImpl->m_enabled = enabled;
}

bool D3D12MotionSearch::IsEnabled() const
{
    return pImpl->m_enabled;
}

ID3D12Device* D3D12MotionSearch::GetDevice()
{
    std::lock_guard<std::mutex> lock(pImpl->m_mutex);
    pImpl->InitDevice();
    return pImpl->m_device.Get();
}

ID3D12CommandQueue* D3D12MotionSearch::GetCommandQueue()
{
    std::lock_guard<std::mutex> lock(pImpl->m_mutex);
    pImpl->InitDevice();
    return pImpl->m_queue.Get();
}

bool D3D12MotionSearch::SearchMVs(
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
    int* pOutArray, short* pOutFileBuf, VECTOR* pOutVectors,
    const FakePlaneOfBlocks* pCoarsePlane, int smooth
)
{
    if (!pSrcFrame || !pRefFrame || !pOutArray || !pOutVectors)
    {
        return false;
    }

    MVPlane* srcPlane = pSrcFrame->GetPlane(YPLANE);
    MVPlane* refPlane = pRefFrame->GetPlane(YPLANE);
    if (!srcPlane || !refPlane)
    {
        return false;
    }

    const uint8_t* pSrc = srcPlane->GetAbsolutePelPointer(0, 0);
    const uint8_t* pRef = refPlane->GetAbsolutePelPointer(0, 0);
    if (!pSrc || !pRef)
    {
        return false;
    }

    int blkCount = nBlkX * nBlkY;
    int coarseBlkCount = (pCoarsePlane != nullptr) ? (pCoarsePlane->GetReducedWidth() * pCoarsePlane->GetReducedHeight()) : 0;
    int maxPredBlocks = std::max(blkCount, coarseBlkCount);
    int srcPitch = srcPlane->GetPitch();
    int refPitch = refPlane->GetPitch();
    int extHeight = srcPlane->GetExtendedHeight();
    int extWidth = srcPlane->GetExtendedWidth();
    int actualRefPel = refPlane->GetPel();
    int effectivePel = (actualRefPel > 0) ? std::min(nPel, actualRefPel) : nPel;
    size_t srcSize = (size_t)srcPitch * extHeight;
    size_t refSize = (size_t)refPitch * extHeight * effectivePel * effectivePel;

    std::lock_guard<std::mutex> lock(pImpl->m_mutex);
    if (!pImpl->InitDevice() || !pImpl->m_enabled || !pImpl->m_device)
    {
        return false;
    }
    if (pImpl->m_device->GetDeviceRemovedReason() != S_OK)
    {
        pImpl->m_available = false;
        return false;
    }

    if (!pImpl->EnsureBuffers(maxPredBlocks))
    {
        return false;
    }

    // 1. Source and Reference plane upload via unified 6-slot LRU cache
    int srcSlot = pImpl->GetOrUploadPlane(pSrc, srcSize, -1);
    if (srcSlot < 0) return false;

    int refSlot = pImpl->GetOrUploadPlane(pRef, refSize, srcSlot);
    if (refSlot < 0) return false;

    // Predictors upload: stream directly to mapped GPU buffer (eliminates intermediate vector allocations)
    bool validUpperPred = false;
    uint32_t coarseMode = 0;
    if (hasUpperPredictor && pCoarsePlane && coarseBlkCount > 0 && pImpl->m_pPredMapped)
    {
        int32_t* pDstPred = static_cast<int32_t*>(pImpl->m_pPredMapped);
        for (int i = 0; i < coarseBlkCount; i++)
        {
            VECTOR mv = pCoarsePlane->GetBlock(i).GetMV();
            pDstPred[i * 2 + 0] = mv.x;
            pDstPred[i * 2 + 1] = mv.y;
        }
        validUpperPred = true;
        coarseMode = (smooth == 1) ? 2u : 1u;
    }
    else if (hasUpperPredictor && upperPredictors && pImpl->m_pPredMapped)
    {
        int32_t* pDstPred = static_cast<int32_t*>(pImpl->m_pPredMapped);
        for (int i = 0; i < blkCount; i++)
        {
            pDstPred[i * 2 + 0] = upperPredictors[i].x;
            pDstPred[i * 2 + 1] = upperPredictors[i].y;
        }
        validUpperPred = true;
        coarseMode = 0;
    }

    if (temporal && vecPrev && pImpl->m_pTempPredMapped)
    {
        int32_t* pDstTemp = static_cast<int32_t*>(pImpl->m_pTempPredMapped);
        for (int i = 0; i < blkCount; i++)
        {
            pDstTemp[i * 2 + 0] = vecPrev[i * 3 + 0];
            pDstTemp[i * 2 + 1] = vecPrev[i * 3 + 1];
        }
    }

    // Populate Constant Buffer
    D3D12MotionParams params = {};
    params.nBlkX = (uint32_t)nBlkX;
    params.nBlkY = (uint32_t)nBlkY;
    params.nBlkSizeX = (uint32_t)nBlkSizeX;
    params.nBlkSizeY = (uint32_t)nBlkSizeY;
    params.nOverlapX = (uint32_t)nOverlapX;
    params.nOverlapY = (uint32_t)nOverlapY;
    params.nHPadding = (uint32_t)srcPlane->GetHPadding();
    params.nVPadding = (uint32_t)srcPlane->GetVPadding();
    params.nSrcPitch = (uint32_t)srcPitch;
    params.nRefPitch = (uint32_t)refPitch;
    params.nPel = (uint32_t)nPel;
    params.nLogScale = (uint32_t)nLogScale;
    params.searchType = (uint32_t)searchType;
    params.nSearchParam = nSearchParam;
    params.nLambda = lambda;
    params.lsad = (uint32_t)lsad;
    params.pnew = pnew;
    params.pzero = pzero;
    params.pglobal = pglobal;
    params.fieldShift = fieldShift;
    params.globalMvX = globalMvX;
    params.globalMvY = globalMvY;
    params.verybigSAD = verybigSAD;
    params.extendedWidth = (uint32_t)extWidth;
    params.extendedHeight = (uint32_t)extHeight;
    params.temporalPredictorValid = (temporal && vecPrev != nullptr) ? 1 : 0;
    params.hasUpperPredictor = validUpperPred ? 1 : 0;
    params.bits_per_pixel = 8;
    params.coarsePredMode = coarseMode;
    if (pCoarsePlane != nullptr)
    {
        params.nBlkXold = (uint32_t)pCoarsePlane->GetReducedWidth();
        params.nBlkYold = (uint32_t)pCoarsePlane->GetReducedHeight();
        params.nBlkSizeXold = (uint32_t)pCoarsePlane->GetBlockSizeX();
        params.nBlkSizeYold = (uint32_t)pCoarsePlane->GetBlockSizeY();
        params.nStepXold = (uint32_t)(pCoarsePlane->GetBlockSizeX() - pCoarsePlane->GetOverlapX());
        params.nStepYold = (uint32_t)(pCoarsePlane->GetBlockSizeY() - pCoarsePlane->GetOverlapY());
    }
    params.padding0 = 0;

    if (pImpl->m_pConstMapped)
    {
        memcpy(pImpl->m_pConstMapped, &params, sizeof(params));
    }

    // Record & execute compute command list
    pImpl->m_cmdAlloc->Reset();
    pImpl->m_cmdList->Reset(pImpl->m_cmdAlloc.Get(), pImpl->m_pso.Get());

    pImpl->m_cmdList->SetComputeRootSignature(pImpl->m_rootSig.Get());
    pImpl->m_cmdList->SetComputeRootConstantBufferView(0, pImpl->m_constBuffer->GetGPUVirtualAddress());
    pImpl->m_cmdList->SetComputeRootShaderResourceView(1, pImpl->m_planeCache[srcSlot].buffer->GetGPUVirtualAddress());
    pImpl->m_cmdList->SetComputeRootShaderResourceView(2, pImpl->m_planeCache[refSlot].buffer->GetGPUVirtualAddress());
    pImpl->m_cmdList->SetComputeRootShaderResourceView(3, validUpperPred ? pImpl->m_predBuffer->GetGPUVirtualAddress() : pImpl->m_dummyBuffer->GetGPUVirtualAddress());
    pImpl->m_cmdList->SetComputeRootShaderResourceView(4, (temporal && vecPrev) ? pImpl->m_tempPredBuffer->GetGPUVirtualAddress() : pImpl->m_dummyBuffer->GetGPUVirtualAddress());
    pImpl->m_cmdList->SetComputeRootUnorderedAccessView(5, pImpl->m_uavBuffer->GetGPUVirtualAddress());

    pImpl->m_cmdList->Dispatch((nBlkX + 7) / 8, (nBlkY + 7) / 8, 1);

    // Barrier UAV -> COPY_SOURCE
    D3D12_RESOURCE_BARRIER barrier = {};
    barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition.pResource = pImpl->m_uavBuffer.Get();
    barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_UNORDERED_ACCESS;
    barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
    barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    pImpl->m_cmdList->ResourceBarrier(1, &barrier);

    pImpl->m_cmdList->CopyResource(pImpl->m_readbackBuffer.Get(), pImpl->m_uavBuffer.Get());

    // Restore UAV state
    barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COPY_SOURCE;
    barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_UNORDERED_ACCESS;
    pImpl->m_cmdList->ResourceBarrier(1, &barrier);

    pImpl->m_cmdList->Close();

    ID3D12CommandList* ppLists[] = { pImpl->m_cmdList.Get() };
    pImpl->m_queue->ExecuteCommandLists(1, ppLists);

    pImpl->m_fenceValue++;
    pImpl->m_queue->Signal(pImpl->m_fence.Get(), pImpl->m_fenceValue);
    pImpl->m_fence->SetEventOnCompletion(pImpl->m_fenceValue, pImpl->m_fenceEvent);
    DWORD waitResult = WaitForSingleObject(pImpl->m_fenceEvent, 2000);
    if (waitResult != WAIT_OBJECT_0)
    {
        if (pImpl->m_device->GetDeviceRemovedReason() != S_OK)
        {
            pImpl->m_available = false;
        }
        return false;
    }

    // Read back results directly into output arrays (D3D12BlockResult, VECTOR, and pBlkData share identical 12-byte layout)
    static_assert(sizeof(D3D12BlockResult) == 12, "D3D12BlockResult must be 12 bytes");
    static_assert(sizeof(VECTOR) == 12, "VECTOR must be 12 bytes");
    if (!pImpl->m_pReadbackMapped)
    {
        return false;
    }

    int* pBlkData = pOutArray + 1; // Skips header
    memcpy(pBlkData, pImpl->m_pReadbackMapped, blkCount * sizeof(D3D12BlockResult));

    if (pOutVectors)
    {
        memcpy(pOutVectors, pBlkData, blkCount * sizeof(VECTOR));
    }

    if (pOutFileBuf)
    {
        const D3D12BlockResult* pRes = reinterpret_cast<const D3D12BlockResult*>(pBlkData);
        for (int i = 0; i < blkCount; i++)
        {
            pOutFileBuf[i * 4 + 0] = (short)pRes[i].x;
            pOutFileBuf[i * 4 + 1] = (short)pRes[i].y;
            pOutFileBuf[i * 4 + 2] = (short)(pRes[i].sad & 0xFFFF);
            pOutFileBuf[i * 4 + 3] = (short)(pRes[i].sad >> 16);
        }
    }

    return true;
}
