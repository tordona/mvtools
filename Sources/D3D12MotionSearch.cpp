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
#include "profile.h"
#include "MVFrame.h"
#include "MVPlane.h"
#include "FakePlaneOfBlocks.h"
#include "shaders/motion_search_cso.h"

#include <windows.h>
#include <d3d12.h>
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <mutex>
#include <atomic>
#include <vector>
#include <algorithm>
#include <cstdio>

#pragma comment(lib, "d3d12.lib")
#pragma comment(lib, "dxgi.lib")

using Microsoft::WRL::ComPtr;

namespace
{
    uint64_t ComputePlaneDigest(const uint8_t* pPlane, size_t size)
    {
        if (!pPlane || size < 8)
            return 0;

        uint64_t h = 14695981039346656037ULL ^ static_cast<uint64_t>(size);
        constexpr int kSamples = 16;
        const size_t maxOffset = size - 8;
        for (int i = 0; i < kSamples; ++i)
        {
            const size_t offset = (i == kSamples - 1) ? maxOffset : (maxOffset * static_cast<size_t>(i)) / (kSamples - 1);
            uint64_t v = 0;
            memcpy(&v, pPlane + offset, sizeof(v));
            h ^= v;
            h *= 1099511628211ULL;
        }
        return h;
    }

    HRESULT CreateD3D12Buffer(ID3D12Device* device, size_t size, D3D12_HEAP_TYPE heapType, D3D12_RESOURCE_STATES initialState, D3D12_RESOURCE_FLAGS flags, ID3D12Resource** ppResource)
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

        return device->CreateCommittedResource(&heapProps, D3D12_HEAP_FLAG_NONE, &desc, initialState, nullptr, IID_PPV_ARGS(ppResource));
    }
}

struct SearchSlot
{
    std::mutex slotMutex;

    ComPtr<ID3D12CommandAllocator> cmdAlloc;
    ComPtr<ID3D12GraphicsCommandList> cmdList;
    ComPtr<ID3D12Fence> fence;
    HANDLE fenceEvent = nullptr;
    uint64_t fenceValue = 0;

    ComPtr<ID3D12Resource> constBuffer;
    ComPtr<ID3D12Resource> predBuffer;
    ComPtr<ID3D12Resource> tempPredBuffer;
    ComPtr<ID3D12Resource> uavBuffer;
    ComPtr<ID3D12Resource> readbackBuffer;

    void* pConstMapped = nullptr;
    void* pPredMapped = nullptr;
    void* pTempPredMapped = nullptr;
    void* pReadbackMapped = nullptr;

    size_t predBufferSize = 0;
    size_t tempPredBufferSize = 0;
    size_t outBufferSize = 0;

    bool Init(ID3D12Device* device, ID3D12PipelineState* pso)
    {
        if (FAILED(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&cmdAlloc))))
            return false;

        if (FAILED(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, cmdAlloc.Get(), pso, IID_PPV_ARGS(&cmdList))))
            return false;
        cmdList->Close();

        if (FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence))))
            return false;

        fenceEvent = CreateEvent(nullptr, FALSE, FALSE, nullptr);
        if (!fenceEvent)
            return false;

        if (FAILED(CreateD3D12Buffer(device, 256, D3D12_HEAP_TYPE_UPLOAD, D3D12_RESOURCE_STATE_GENERIC_READ, D3D12_RESOURCE_FLAG_NONE, &constBuffer)))
            return false;
        if (FAILED(constBuffer->Map(0, nullptr, &pConstMapped)) || !pConstMapped)
        {
            pConstMapped = nullptr;
            return false;
        }

        return true;
    }

    bool EnsureBuffers(ID3D12Device* device, size_t blockCount)
    {
        if (!device || device->GetDeviceRemovedReason() != S_OK)
            return false;

        size_t predSize = blockCount * sizeof(int32_t) * 2;
        if (predBufferSize < predSize || !predBuffer || !pPredMapped)
        {
            if (predBuffer && pPredMapped)
            {
                predBuffer->Unmap(0, nullptr);
                pPredMapped = nullptr;
            }
            predBufferSize = (predSize * 3) / 2;
            predBuffer.Reset();
            if (FAILED(CreateD3D12Buffer(device, predBufferSize, D3D12_HEAP_TYPE_UPLOAD, D3D12_RESOURCE_STATE_GENERIC_READ, D3D12_RESOURCE_FLAG_NONE, &predBuffer)))
                return false;
            if (FAILED(predBuffer->Map(0, nullptr, &pPredMapped)) || !pPredMapped)
            {
                pPredMapped = nullptr;
                return false;
            }
        }

        if (tempPredBufferSize < predSize || !tempPredBuffer || !pTempPredMapped)
        {
            if (tempPredBuffer && pTempPredMapped)
            {
                tempPredBuffer->Unmap(0, nullptr);
                pTempPredMapped = nullptr;
            }
            tempPredBufferSize = (predSize * 3) / 2;
            tempPredBuffer.Reset();
            if (FAILED(CreateD3D12Buffer(device, tempPredBufferSize, D3D12_HEAP_TYPE_UPLOAD, D3D12_RESOURCE_STATE_GENERIC_READ, D3D12_RESOURCE_FLAG_NONE, &tempPredBuffer)))
                return false;
            if (FAILED(tempPredBuffer->Map(0, nullptr, &pTempPredMapped)) || !pTempPredMapped)
            {
                pTempPredMapped = nullptr;
                return false;
            }
        }

        size_t outSize = blockCount * sizeof(D3D12BlockResult);
        if (outBufferSize < outSize || !uavBuffer || !readbackBuffer || !pReadbackMapped)
        {
            if (readbackBuffer && pReadbackMapped)
            {
                readbackBuffer->Unmap(0, nullptr);
                pReadbackMapped = nullptr;
            }
            outBufferSize = (outSize * 3) / 2;
            uavBuffer.Reset();
            readbackBuffer.Reset();
            if (FAILED(CreateD3D12Buffer(device, outBufferSize, D3D12_HEAP_TYPE_DEFAULT, D3D12_RESOURCE_STATE_UNORDERED_ACCESS, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS, &uavBuffer)))
                return false;
            if (FAILED(CreateD3D12Buffer(device, outBufferSize, D3D12_HEAP_TYPE_READBACK, D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_FLAG_NONE, &readbackBuffer)))
                return false;
            if (FAILED(readbackBuffer->Map(0, nullptr, &pReadbackMapped)) || !pReadbackMapped)
            {
                pReadbackMapped = nullptr;
                return false;
            }
        }

        return true;
    }

    ~SearchSlot()
    {
        if (constBuffer && pConstMapped)
        {
            constBuffer->Unmap(0, nullptr);
            pConstMapped = nullptr;
        }
        if (readbackBuffer && pReadbackMapped)
        {
            readbackBuffer->Unmap(0, nullptr);
            pReadbackMapped = nullptr;
        }
        if (predBuffer && pPredMapped)
        {
            predBuffer->Unmap(0, nullptr);
            pPredMapped = nullptr;
        }
        if (tempPredBuffer && pTempPredMapped)
        {
            tempPredBuffer->Unmap(0, nullptr);
            pTempPredMapped = nullptr;
        }
        if (fenceEvent)
        {
            CloseHandle(fenceEvent);
            fenceEvent = nullptr;
        }
    }
};

struct D3D12MotionSearch::Impl
{
    static constexpr int NUM_SLOTS = 2;
    static constexpr int PLANE_CACHE_SLOTS = 8;

    std::mutex m_initMutex;
    std::mutex m_queueMutex;
    std::mutex m_cacheMutex;
    bool m_initialized = false;
    bool m_available = false;
    std::atomic<bool> m_enabled{ false };

    ComPtr<IDXGIFactory6> m_factory;
    ComPtr<IDXGIAdapter1> m_adapter;
    ComPtr<ID3D12Device> m_device;
    ComPtr<ID3D12CommandQueue> m_queue;
    ComPtr<ID3D12RootSignature> m_rootSig;
    ComPtr<ID3D12PipelineState> m_pso;
    ComPtr<ID3D12Resource> m_dummyBuffer;

    std::unique_ptr<SearchSlot> m_slots[NUM_SLOTS];
    std::atomic<uint32_t> m_nextSlot{ 0 };

    struct PlaneCacheEntry
    {
        ComPtr<ID3D12Resource> buffer;
        void* pMapped = nullptr;
        size_t bufferSize = 0;
        const uint8_t* pPtr = nullptr;
        size_t size = 0;
        uint64_t digest = 0;
        uint64_t lruCounter = 0;
        int activeUsers = 0;
    };

    PlaneCacheEntry m_planeCache[PLANE_CACHE_SLOTS];
    uint64_t m_lruTick = 0;

    int AcquirePlaneSlot(const uint8_t* pPlane, size_t size, int excludeSlot)
    {
        const uint64_t digest = ComputePlaneDigest(pPlane, size);

        std::lock_guard<std::mutex> cLock(m_cacheMutex);

        // 1. Look for existing cache hit
        for (int i = 0; i < PLANE_CACHE_SLOTS; ++i)
        {
            if (m_planeCache[i].buffer &&
                m_planeCache[i].pPtr == pPlane &&
                m_planeCache[i].size == size &&
                m_planeCache[i].digest == digest)
            {
                m_planeCache[i].lruCounter = ++m_lruTick;
                m_planeCache[i].activeUsers++;
                return i;
            }
        }

        // 2. Cache miss: select LRU slot with activeUsers == 0 (avoiding excludeSlot)
        int selectedSlot = -1;
        uint64_t minTick = UINT64_MAX;
        for (int i = 0; i < PLANE_CACHE_SLOTS; ++i)
        {
            if (i == excludeSlot || m_planeCache[i].activeUsers > 0)
                continue;
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

        if (selectedSlot < 0)
            return -1;

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
            if (FAILED(CreateD3D12Buffer(m_device.Get(), entry.bufferSize, D3D12_HEAP_TYPE_UPLOAD, D3D12_RESOURCE_STATE_GENERIC_READ, D3D12_RESOURCE_FLAG_NONE, &entry.buffer)))
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
        entry.digest = digest;
        entry.lruCounter = ++m_lruTick;
        entry.activeUsers++;

        return selectedSlot;
    }

    void ReleasePlaneSlot(int slot)
    {
        if (slot < 0 || slot >= PLANE_CACHE_SLOTS)
            return;
        std::lock_guard<std::mutex> cLock(m_cacheMutex);
        if (m_planeCache[slot].activeUsers > 0)
        {
            m_planeCache[slot].activeUsers--;
        }
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
        rootParams[0].ParameterType = D3D12_ROOT_PARAMETER_TYPE_CBV;
        rootParams[0].Descriptor.ShaderRegister = 0;
        rootParams[0].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

        rootParams[1].ParameterType = D3D12_ROOT_PARAMETER_TYPE_SRV;
        rootParams[1].Descriptor.ShaderRegister = 0;
        rootParams[1].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

        rootParams[2].ParameterType = D3D12_ROOT_PARAMETER_TYPE_SRV;
        rootParams[2].Descriptor.ShaderRegister = 1;
        rootParams[2].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

        rootParams[3].ParameterType = D3D12_ROOT_PARAMETER_TYPE_SRV;
        rootParams[3].Descriptor.ShaderRegister = 2;
        rootParams[3].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

        rootParams[4].ParameterType = D3D12_ROOT_PARAMETER_TYPE_SRV;
        rootParams[4].Descriptor.ShaderRegister = 3;
        rootParams[4].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

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

        if (FAILED(CreateD3D12Buffer(m_device.Get(), 256, D3D12_HEAP_TYPE_UPLOAD, D3D12_RESOURCE_STATE_GENERIC_READ, D3D12_RESOURCE_FLAG_NONE, &m_dummyBuffer)))
            return false;

        for (int i = 0; i < NUM_SLOTS; ++i)
        {
            m_slots[i] = std::make_unique<SearchSlot>();
            if (!m_slots[i]->Init(m_device.Get(), m_pso.Get()))
                return false;
        }

        m_available = true;
        return true;
    }

    void ReleaseResources()
    {
        std::lock_guard<std::mutex> initLock(m_initMutex);
        std::unique_lock<std::mutex> slotLocks[NUM_SLOTS];
        for (int i = 0; i < NUM_SLOTS; ++i)
        {
            if (m_slots[i])
            {
                slotLocks[i] = std::unique_lock<std::mutex>(m_slots[i]->slotMutex);
            }
        }
        std::lock_guard<std::mutex> cLock(m_cacheMutex);

        for (int i = 0; i < PLANE_CACHE_SLOTS; ++i)
        {
            if (m_planeCache[i].buffer && m_planeCache[i].pMapped)
            {
                m_planeCache[i].buffer->Unmap(0, nullptr);
                m_planeCache[i].pMapped = nullptr;
            }
            m_planeCache[i].buffer.Reset();
            m_planeCache[i].bufferSize = 0;
            m_planeCache[i].pPtr = nullptr;
            m_planeCache[i].size = 0;
            m_planeCache[i].digest = 0;
            m_planeCache[i].activeUsers = 0;
        }

        for (int i = 0; i < NUM_SLOTS; ++i)
        {
            slotLocks[i] = std::unique_lock<std::mutex>();
            m_slots[i].reset();
        }

        m_dummyBuffer.Reset();
        m_pso.Reset();
        m_rootSig.Reset();
        m_queue.Reset();
        m_device.Reset();
        m_adapter.Reset();
        m_factory.Reset();

        m_initialized = false;
        m_available = false;
    }

    ~Impl()
    {
        ReleaseResources();
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

void D3D12MotionSearch::Shutdown()
{
    GetInstance().pImpl->ReleaseResources();
}

bool D3D12MotionSearch::IsAvailable()
{
    std::lock_guard<std::mutex> lock(pImpl->m_initMutex);
    return pImpl->m_enabled.load(std::memory_order_relaxed) && pImpl->InitDevice() && pImpl->m_device && (pImpl->m_device->GetDeviceRemovedReason() == S_OK);
}

void D3D12MotionSearch::SetEnabled(bool enabled)
{
    pImpl->m_enabled.store(enabled, std::memory_order_relaxed);
}

bool D3D12MotionSearch::IsEnabled() const
{
    return pImpl->m_enabled.load(std::memory_order_relaxed);
}

ID3D12Device* D3D12MotionSearch::GetDevice()
{
    std::lock_guard<std::mutex> lock(pImpl->m_initMutex);
    pImpl->InitDevice();
    return pImpl->m_device.Get();
}

ID3D12CommandQueue* D3D12MotionSearch::GetCommandQueue()
{
    std::lock_guard<std::mutex> lock(pImpl->m_initMutex);
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

    {
        std::lock_guard<std::mutex> initLock(pImpl->m_initMutex);
        if (!pImpl->m_enabled.load(std::memory_order_relaxed) || !pImpl->InitDevice() || !pImpl->m_device)
        {
            return false;
        }
        if (pImpl->m_device->GetDeviceRemovedReason() != S_OK)
        {
            pImpl->m_available = false;
            return false;
        }
    }

    PROFILE_START(MOTION_PROFILE_GPU_SEARCH);

    // Non-blocking slot selection for concurrent Prefetch() execution, with round-robin fallback
    int slotIdx = -1;
    std::unique_lock<std::mutex> slotLock;
    for (int i = 0; i < Impl::NUM_SLOTS; ++i)
    {
        std::unique_lock<std::mutex> tryLock(pImpl->m_slots[i]->slotMutex, std::try_to_lock);
        if (tryLock.owns_lock())
        {
            slotIdx = i;
            slotLock = std::move(tryLock);
            break;
        }
    }
    if (slotIdx < 0)
    {
        slotIdx = static_cast<int>(pImpl->m_nextSlot.fetch_add(1, std::memory_order_relaxed) % Impl::NUM_SLOTS);
        slotLock = std::unique_lock<std::mutex>(pImpl->m_slots[slotIdx]->slotMutex);
    }

    SearchSlot& slot = *pImpl->m_slots[slotIdx];
    if (!slot.EnsureBuffers(pImpl->m_device.Get(), maxPredBlocks))
    {
        PROFILE_STOP(MOTION_PROFILE_GPU_SEARCH);
        return false;
    }

    struct PlaneSlotGuard
    {
        D3D12MotionSearch::Impl* impl;
        int srcSlot = -1;
        int refSlot = -1;
        ~PlaneSlotGuard()
        {
            impl->ReleasePlaneSlot(refSlot);
            impl->ReleasePlaneSlot(srcSlot);
        }
    } planeGuard { pImpl };

    // 1. Source and Reference plane upload via unified 8-slot LRU cache
    planeGuard.srcSlot = pImpl->AcquirePlaneSlot(pSrc, srcSize, -1);
    if (planeGuard.srcSlot < 0)
    {
        PROFILE_STOP(MOTION_PROFILE_GPU_SEARCH);
        return false;
    }

    planeGuard.refSlot = pImpl->AcquirePlaneSlot(pRef, refSize, planeGuard.srcSlot);
    if (planeGuard.refSlot < 0)
    {
        PROFILE_STOP(MOTION_PROFILE_GPU_SEARCH);
        return false;
    }

    // Predictors upload: stream directly to mapped GPU buffer
    bool validUpperPred = false;
    uint32_t coarseMode = 0;
    if (hasUpperPredictor && pCoarsePlane && coarseBlkCount > 0 && slot.pPredMapped)
    {
        int32_t* pDstPred = static_cast<int32_t*>(slot.pPredMapped);
        for (int i = 0; i < coarseBlkCount; i++)
        {
            VECTOR mv = pCoarsePlane->GetBlock(i).GetMV();
            pDstPred[i * 2 + 0] = mv.x;
            pDstPred[i * 2 + 1] = mv.y;
        }
        validUpperPred = true;
        coarseMode = (smooth == 1) ? 2u : 1u;
    }
    else if (hasUpperPredictor && upperPredictors && slot.pPredMapped)
    {
        int32_t* pDstPred = static_cast<int32_t*>(slot.pPredMapped);
        for (int i = 0; i < blkCount; i++)
        {
            pDstPred[i * 2 + 0] = upperPredictors[i].x;
            pDstPred[i * 2 + 1] = upperPredictors[i].y;
        }
        validUpperPred = true;
        coarseMode = 0;
    }

    if (temporal && vecPrev && slot.pTempPredMapped)
    {
        int32_t* pDstTemp = static_cast<int32_t*>(slot.pTempPredMapped);
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

    if (slot.pConstMapped)
    {
        memcpy(slot.pConstMapped, &params, sizeof(params));
    }

    // Record & execute compute command list
    slot.cmdAlloc->Reset();
    slot.cmdList->Reset(slot.cmdAlloc.Get(), pImpl->m_pso.Get());

    slot.cmdList->SetComputeRootSignature(pImpl->m_rootSig.Get());
    slot.cmdList->SetComputeRootConstantBufferView(0, slot.constBuffer->GetGPUVirtualAddress());
    slot.cmdList->SetComputeRootShaderResourceView(1, pImpl->m_planeCache[planeGuard.srcSlot].buffer->GetGPUVirtualAddress());
    slot.cmdList->SetComputeRootShaderResourceView(2, pImpl->m_planeCache[planeGuard.refSlot].buffer->GetGPUVirtualAddress());
    slot.cmdList->SetComputeRootShaderResourceView(3, validUpperPred ? slot.predBuffer->GetGPUVirtualAddress() : pImpl->m_dummyBuffer->GetGPUVirtualAddress());
    slot.cmdList->SetComputeRootShaderResourceView(4, (temporal && vecPrev) ? slot.tempPredBuffer->GetGPUVirtualAddress() : pImpl->m_dummyBuffer->GetGPUVirtualAddress());
    slot.cmdList->SetComputeRootUnorderedAccessView(5, slot.uavBuffer->GetGPUVirtualAddress());

    slot.cmdList->Dispatch((nBlkX + 7) / 8, (nBlkY + 7) / 8, 1);

    // Barrier UAV -> COPY_SOURCE
    D3D12_RESOURCE_BARRIER barrier = {};
    barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition.pResource = slot.uavBuffer.Get();
    barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_UNORDERED_ACCESS;
    barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
    barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    slot.cmdList->ResourceBarrier(1, &barrier);

    slot.cmdList->CopyResource(slot.readbackBuffer.Get(), slot.uavBuffer.Get());

    // Restore UAV state
    barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COPY_SOURCE;
    barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_UNORDERED_ACCESS;
    slot.cmdList->ResourceBarrier(1, &barrier);

    slot.cmdList->Close();

    {
        std::lock_guard<std::mutex> qLock(pImpl->m_queueMutex);
        ID3D12CommandList* ppLists[] = { slot.cmdList.Get() };
        pImpl->m_queue->ExecuteCommandLists(1, ppLists);

        slot.fenceValue++;
        pImpl->m_queue->Signal(slot.fence.Get(), slot.fenceValue);
    }

    slot.fence->SetEventOnCompletion(slot.fenceValue, slot.fenceEvent);
    DWORD waitResult = WaitForSingleObject(slot.fenceEvent, 2000);
    if (waitResult != WAIT_OBJECT_0)
    {
        if (pImpl->m_device->GetDeviceRemovedReason() != S_OK)
        {
            pImpl->m_available = false;
        }
        PROFILE_STOP(MOTION_PROFILE_GPU_SEARCH);
        return false;
    }

    // Read back results directly into output arrays (D3D12BlockResult, VECTOR, and pBlkData share identical 12-byte layout)
    static_assert(sizeof(D3D12BlockResult) == 12, "D3D12BlockResult must be 12 bytes");
    static_assert(sizeof(VECTOR) == 12, "VECTOR must be 12 bytes");
    if (!slot.pReadbackMapped)
    {
        PROFILE_STOP(MOTION_PROFILE_GPU_SEARCH);
        return false;
    }

    int* pBlkData = pOutArray + 1; // Skips header
    memcpy(pBlkData, slot.pReadbackMapped, blkCount * sizeof(D3D12BlockResult));

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

    PROFILE_STOP(MOTION_PROFILE_GPU_SEARCH);
    return true;
}
