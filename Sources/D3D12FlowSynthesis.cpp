#ifndef WINVER
#define WINVER 0x0A00
#endif
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#ifndef NTDDI_VERSION
#define NTDDI_VERSION 0x0A000000
#endif

#include "D3D12FlowSynthesis.h"
#include "D3D12MotionSearch.h"
#include "MVClip.h"
#include "FakeBlockData.h"
#include "shaders/flow_warp_cso.h"
#include "shaders/flow_blend_cso.h"

#include <windows.h>
#include <d3d12.h>
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <mutex>
#include <memory>
#include <atomic>
#include <vector>
#include <algorithm>
#include <cstdio>

#pragma comment(lib, "d3d12.lib")
#pragma comment(lib, "dxgi.lib")

using Microsoft::WRL::ComPtr;

namespace
{
    inline size_t AlignUp(size_t val, size_t alignment)
    {
        return (val + alignment - 1) & ~(alignment - 1);
    }

    struct Float2
    {
        float x;
        float y;
    };

    struct alignas(16) FlowParamsCB
    {
        uint32_t width;
        uint32_t height;
        float    time;
        float    nPel;

        float    mvScaleX;
        float    mvScaleY;
        uint32_t maskMode;
        uint32_t nBlkSizeX;

        uint32_t nBlkSizeY;
        uint32_t nBlkX;
        uint32_t nBlkY;
        uint32_t flowMode;
    };

    struct alignas(16) BlendParamsCB
    {
        uint32_t blendWidth;
        uint32_t blendHeight;
        float    blendTime;
        uint32_t blendPad;
    };

    HRESULT CreateBuffer(ID3D12Device* device, size_t size, D3D12_HEAP_TYPE heapType, D3D12_RESOURCE_STATES initialState, D3D12_RESOURCE_FLAGS flags, ID3D12Resource** ppResource)
    {
        D3D12_HEAP_PROPERTIES heapProps = {};
        heapProps.Type = heapType;
        heapProps.CPUPageProperty = D3D12_CPU_PAGE_PROPERTY_UNKNOWN;
        heapProps.MemoryPoolPreference = D3D12_MEMORY_POOL_UNKNOWN;

        D3D12_RESOURCE_DESC desc = {};
        desc.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
        desc.Alignment = 0;
        desc.Width = AlignUp(size, 256);
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

    HRESULT CreateTexture2D(ID3D12Device* device, UINT width, UINT height, DXGI_FORMAT format, D3D12_RESOURCE_FLAGS flags, D3D12_RESOURCE_STATES initialState, ID3D12Resource** ppResource)
    {
        D3D12_HEAP_PROPERTIES heapProps = {};
        heapProps.Type = D3D12_HEAP_TYPE_DEFAULT;
        heapProps.CPUPageProperty = D3D12_CPU_PAGE_PROPERTY_UNKNOWN;
        heapProps.MemoryPoolPreference = D3D12_MEMORY_POOL_UNKNOWN;

        D3D12_RESOURCE_DESC desc = {};
        desc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
        desc.Alignment = 0;
        desc.Width = width;
        desc.Height = height;
        desc.DepthOrArraySize = 1;
        desc.MipLevels = 1;
        desc.Format = format;
        desc.SampleDesc.Count = 1;
        desc.SampleDesc.Quality = 0;
        desc.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
        desc.Flags = flags;

        return device->CreateCommittedResource(&heapProps, D3D12_HEAP_FLAG_NONE, &desc, initialState, nullptr, IID_PPV_ARGS(ppResource));
    }

    void RecordCopyTexture(ID3D12GraphicsCommandList* cmdList, ID3D12Resource* pDstTex, ID3D12Resource* pSrcBuf, size_t bufOffset, size_t rowPitch, UINT width, UINT height, DXGI_FORMAT format)
    {
        D3D12_TEXTURE_COPY_LOCATION dstLoc = {};
        dstLoc.pResource = pDstTex;
        dstLoc.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
        dstLoc.SubresourceIndex = 0;

        D3D12_TEXTURE_COPY_LOCATION srcLoc = {};
        srcLoc.pResource = pSrcBuf;
        srcLoc.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
        srcLoc.PlacedFootprint.Offset = bufOffset;
        srcLoc.PlacedFootprint.Footprint.Format = format;
        srcLoc.PlacedFootprint.Footprint.Width = width;
        srcLoc.PlacedFootprint.Footprint.Height = height;
        srcLoc.PlacedFootprint.Footprint.Depth = 1;
        srcLoc.PlacedFootprint.Footprint.RowPitch = (UINT)rowPitch;

        cmdList->CopyTextureRegion(&dstLoc, 0, 0, 0, &srcLoc, nullptr);
    }

    void RecordReadbackTexture(ID3D12GraphicsCommandList* cmdList, ID3D12Resource* pDstBuf, size_t bufOffset, size_t rowPitch, ID3D12Resource* pSrcTex, UINT width, UINT height, DXGI_FORMAT format)
    {
        D3D12_TEXTURE_COPY_LOCATION dstLoc = {};
        dstLoc.pResource = pDstBuf;
        dstLoc.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
        dstLoc.PlacedFootprint.Offset = bufOffset;
        dstLoc.PlacedFootprint.Footprint.Format = format;
        dstLoc.PlacedFootprint.Footprint.Width = width;
        dstLoc.PlacedFootprint.Footprint.Height = height;
        dstLoc.PlacedFootprint.Footprint.Depth = 1;
        dstLoc.PlacedFootprint.Footprint.RowPitch = (UINT)rowPitch;

        D3D12_TEXTURE_COPY_LOCATION srcLoc = {};
        srcLoc.pResource = pSrcTex;
        srcLoc.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
        srcLoc.SubresourceIndex = 0;

        cmdList->CopyTextureRegion(&dstLoc, 0, 0, 0, &srcLoc, nullptr);
    }

    void RecordBarrier(ID3D12GraphicsCommandList* cmdList, ID3D12Resource* pRes, D3D12_RESOURCE_STATES stateBefore, D3D12_RESOURCE_STATES stateAfter)
    {
        D3D12_RESOURCE_BARRIER b = {};
        b.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        b.Flags = D3D12_RESOURCE_BARRIER_FLAG_NONE;
        b.Transition.pResource = pRes;
        b.Transition.StateBefore = stateBefore;
        b.Transition.StateAfter = stateAfter;
        b.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        cmdList->ResourceBarrier(1, &b);
    }
}

struct RingTexture
{
    ComPtr<ID3D12Resource> texY;
    ComPtr<ID3D12Resource> texU;
    ComPtr<ID3D12Resource> texV;

    const uint8_t* cachedPtr = nullptr;
    uint64_t cachedS0 = 0, cachedS1 = 0, cachedS2 = 0, cachedS3 = 0, cachedS4 = 0;
    bool inShaderResource = false;
};

struct FrameSlot
{
    std::mutex slotMutex;

    ComPtr<ID3D12CommandAllocator> cmdAlloc;
    ComPtr<ID3D12GraphicsCommandList> cmdList;

    ComPtr<ID3D12DescriptorHeap> descHeap;

    ComPtr<ID3D12Fence> fence;
    HANDLE fenceEvent = nullptr;
    uint64_t fenceValue = 0;

    // Linear Upload, Readback, and Constant Buffers
    ComPtr<ID3D12Resource> uploadBuffer;
    ComPtr<ID3D12Resource> readbackBuffer;
    ComPtr<ID3D12Resource> constBuffer;

    void* pUploadMapped = nullptr;
    void* pReadbackMapped = nullptr;
    void* pConstMapped = nullptr;

    size_t uploadBufferSize = 0;
    size_t readbackBufferSize = 0;

    // Subresource footprint offsets inside uploadBuffer
    size_t upPitchPlaneY = 0;
    size_t upPitchPlaneUV = 0;

    size_t upOffRefY = 0;
    size_t upOffRefU = 0;
    size_t upOffRefV = 0;

    size_t upOffSrcY = 0;
    size_t upOffSrcU = 0;
    size_t upOffSrcV = 0;

    size_t upOffMvF = 0,  upPitchMvF = 0;
    size_t upOffMvB = 0,  upPitchMvB = 0;

    // Subresource footprint offsets inside readbackBuffer
    size_t rbOffOutY = 0, rbPitchOutY = 0;
    size_t rbOffOutU = 0, rbPitchOutU = 0;
    size_t rbOffOutV = 0, rbPitchOutV = 0;

    // Dimensions tracked for dynamic resource resizing
    int curWidth = 0;
    int curHeight = 0;
    int curWidthUV = 0;
    int curHeightUV = 0;
    int curBlkX = 0;
    int curBlkY = 0;

    // Textures: Output Planes (Y, U, V)
    ComPtr<ID3D12Resource> texOutY;
    ComPtr<ID3D12Resource> texOutU;
    ComPtr<ID3D12Resource> texOutV;

    // Textures: Motion Vectors (Fwd, Bwd)
    ComPtr<ID3D12Resource> texMvF;
    ComPtr<ID3D12Resource> texMvB;
    bool mvInShaderResource = false;

    D3D12_CPU_DESCRIPTOR_HANDLE GetCPUDescriptor(UINT index, UINT descSize)
    {
        D3D12_CPU_DESCRIPTOR_HANDLE handle = descHeap->GetCPUDescriptorHandleForHeapStart();
        handle.ptr += (SIZE_T)index * descSize;
        return handle;
    }

    D3D12_GPU_DESCRIPTOR_HANDLE GetGPUDescriptor(UINT index, UINT descSize)
    {
        D3D12_GPU_DESCRIPTOR_HANDLE handle = descHeap->GetGPUDescriptorHandleForHeapStart();
        handle.ptr += (UINT64)index * descSize;
        return handle;
    }

    bool Init(ID3D12Device* device, ID3D12PipelineState* initialPSO)
    {
        HRESULT hr = device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&cmdAlloc));
        if (FAILED(hr)) return false;

        hr = device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, cmdAlloc.Get(), initialPSO, IID_PPV_ARGS(&cmdList));
        if (FAILED(hr)) return false;
        cmdList->Close();

        hr = device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence));
        if (FAILED(hr)) return false;

        fenceEvent = CreateEvent(nullptr, FALSE, FALSE, nullptr);
        if (!fenceEvent) return false;

        // Create Descriptor Heap (CBV_SRV_UAV)
        D3D12_DESCRIPTOR_HEAP_DESC heapDesc = {};
        heapDesc.NumDescriptors = 64;
        heapDesc.Type = D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;
        heapDesc.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;
        hr = device->CreateDescriptorHeap(&heapDesc, IID_PPV_ARGS(&descHeap));
        if (FAILED(hr)) return false;

        // 256-byte aligned constant buffer
        hr = CreateBuffer(device, 1024, D3D12_HEAP_TYPE_UPLOAD, D3D12_RESOURCE_STATE_GENERIC_READ, D3D12_RESOURCE_FLAG_NONE, &constBuffer);
        if (FAILED(hr)) return false;
        hr = constBuffer->Map(0, nullptr, &pConstMapped);
        if (FAILED(hr) || !pConstMapped) return false;

        return true;
    }

    bool EnsureSlotBuffers(ID3D12Device* device, int width, int height, int widthUV, int heightUV, int nBlkX, int nBlkY, int planecount)
    {
        if (curWidth == width && curHeight == height &&
            curWidthUV == widthUV && curHeightUV == heightUV &&
            curBlkX == nBlkX && curBlkY == nBlkY &&
            uploadBuffer && readbackBuffer && texOutY && texMvF &&
            pUploadMapped && pReadbackMapped)
        {
            return true;
        }

        curWidth = width;
        curHeight = height;
        curWidthUV = widthUV;
        curHeightUV = heightUV;
        curBlkX = nBlkX;
        curBlkY = nBlkY;

        // Reset existing resources
        texOutY.Reset(); texOutU.Reset(); texOutV.Reset();
        texMvF.Reset();  texMvB.Reset();

        // Output UAV textures
        if (FAILED(CreateTexture2D(device, width, height, DXGI_FORMAT_R8_UNORM, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_UNORDERED_ACCESS, &texOutY))) return false;

        if (planecount > 1)
        {
            if (FAILED(CreateTexture2D(device, widthUV, heightUV, DXGI_FORMAT_R8_UNORM, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_UNORDERED_ACCESS, &texOutU))) return false;
            if (FAILED(CreateTexture2D(device, widthUV, heightUV, DXGI_FORMAT_R8_UNORM, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_UNORDERED_ACCESS, &texOutV))) return false;
        }

        // Motion vector textures
        if (FAILED(CreateTexture2D(device, nBlkX, nBlkY, DXGI_FORMAT_R32G32_FLOAT, D3D12_RESOURCE_FLAG_NONE, D3D12_RESOURCE_STATE_COPY_DEST, &texMvF))) return false;
        if (FAILED(CreateTexture2D(device, nBlkX, nBlkY, DXGI_FORMAT_R32G32_FLOAT, D3D12_RESOURCE_FLAG_NONE, D3D12_RESOURCE_STATE_COPY_DEST, &texMvB))) return false;

        // Upload buffer footprint layouts: Ref plane, Src plane (cold start fallback), MVs
        size_t currentUpOffset = 0;

        upPitchPlaneY = AlignUp(width, D3D12_TEXTURE_DATA_PITCH_ALIGNMENT);
        upOffRefY = AlignUp(currentUpOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
        currentUpOffset = upOffRefY + upPitchPlaneY * height;

        upOffSrcY = AlignUp(currentUpOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
        currentUpOffset = upOffSrcY + upPitchPlaneY * height;

        if (planecount > 1)
        {
            upPitchPlaneUV = AlignUp(widthUV, D3D12_TEXTURE_DATA_PITCH_ALIGNMENT);
            upOffRefU = AlignUp(currentUpOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
            currentUpOffset = upOffRefU + upPitchPlaneUV * heightUV;

            upOffSrcU = AlignUp(currentUpOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
            currentUpOffset = upOffSrcU + upPitchPlaneUV * heightUV;

            upOffRefV = AlignUp(currentUpOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
            currentUpOffset = upOffRefV + upPitchPlaneUV * heightUV;

            upOffSrcV = AlignUp(currentUpOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
            currentUpOffset = upOffSrcV + upPitchPlaneUV * heightUV;
        }

        upPitchMvF = AlignUp(nBlkX * sizeof(Float2), D3D12_TEXTURE_DATA_PITCH_ALIGNMENT);
        upOffMvF = AlignUp(currentUpOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
        currentUpOffset = upOffMvF + upPitchMvF * nBlkY;

        upPitchMvB = upPitchMvF;
        upOffMvB = AlignUp(currentUpOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
        currentUpOffset = upOffMvB + upPitchMvB * nBlkY;

        // Allocate upload buffer
        if (uploadBuffer && pUploadMapped)
        {
            uploadBuffer->Unmap(0, nullptr);
            pUploadMapped = nullptr;
        }
        uploadBufferSize = currentUpOffset;
        uploadBuffer.Reset();
        if (FAILED(CreateBuffer(device, uploadBufferSize, D3D12_HEAP_TYPE_UPLOAD, D3D12_RESOURCE_STATE_GENERIC_READ, D3D12_RESOURCE_FLAG_NONE, &uploadBuffer)))
            return false;
        if (FAILED(uploadBuffer->Map(0, nullptr, &pUploadMapped)) || !pUploadMapped)
        {
            pUploadMapped = nullptr;
            return false;
        }

        // Readback buffer footprint layouts
        size_t currentRbOffset = 0;

        rbPitchOutY = AlignUp(width, D3D12_TEXTURE_DATA_PITCH_ALIGNMENT);
        rbOffOutY = AlignUp(currentRbOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
        currentRbOffset = rbOffOutY + rbPitchOutY * height;

        if (planecount > 1)
        {
            rbPitchOutU = AlignUp(widthUV, D3D12_TEXTURE_DATA_PITCH_ALIGNMENT);
            rbOffOutU = AlignUp(currentRbOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
            currentRbOffset = rbOffOutU + rbPitchOutU * heightUV;

            rbPitchOutV = rbPitchOutU;
            rbOffOutV = AlignUp(currentRbOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
            currentRbOffset = rbOffOutV + rbPitchOutV * heightUV;
        }

        // Allocate readback buffer
        if (readbackBuffer && pReadbackMapped)
        {
            readbackBuffer->Unmap(0, nullptr);
            pReadbackMapped = nullptr;
        }
        readbackBufferSize = currentRbOffset;
        readbackBuffer.Reset();
        if (FAILED(CreateBuffer(device, readbackBufferSize, D3D12_HEAP_TYPE_READBACK, D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_FLAG_NONE, &readbackBuffer)))
            return false;
        if (FAILED(readbackBuffer->Map(0, nullptr, &pReadbackMapped)) || !pReadbackMapped)
        {
            pReadbackMapped = nullptr;
            return false;
        }

        mvInShaderResource = false;
        return true;
    }

    void SetupDescriptors(ID3D12Device* device, const RingTexture& srcRing, const RingTexture& refRing, int planecount, UINT descSize)
    {
        D3D12_UNORDERED_ACCESS_VIEW_DESC uavDesc = {};
        uavDesc.ViewDimension = D3D12_UAV_DIMENSION_TEXTURE2D;
        uavDesc.Format = DXGI_FORMAT_R8_UNORM;

        // Output UAVs
        device->CreateUnorderedAccessView(texOutY.Get(), nullptr, &uavDesc, GetCPUDescriptor(4, descSize));
        device->CreateUnorderedAccessView(texOutY.Get(), nullptr, &uavDesc, GetCPUDescriptor(18, descSize));

        if (planecount > 1)
        {
            device->CreateUnorderedAccessView(texOutU.Get(), nullptr, &uavDesc, GetCPUDescriptor(9, descSize));
            device->CreateUnorderedAccessView(texOutV.Get(), nullptr, &uavDesc, GetCPUDescriptor(14, descSize));
            device->CreateUnorderedAccessView(texOutU.Get(), nullptr, &uavDesc, GetCPUDescriptor(21, descSize));
            device->CreateUnorderedAccessView(texOutV.Get(), nullptr, &uavDesc, GetCPUDescriptor(24, descSize));
        }

        D3D12_SHADER_RESOURCE_VIEW_DESC srvDesc = {};
        srvDesc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
        srvDesc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2D;
        srvDesc.Texture2D.MipLevels = 1;

        // Y Plane:
        // 0: SRV SrcY
        // 1: SRV RefY
        // 2: SRV MvF
        // 3: SRV MvB
        srvDesc.Format = DXGI_FORMAT_R8_UNORM;
        device->CreateShaderResourceView(srcRing.texY.Get(), &srvDesc, GetCPUDescriptor(0, descSize));
        device->CreateShaderResourceView(refRing.texY.Get(), &srvDesc, GetCPUDescriptor(1, descSize));

        srvDesc.Format = DXGI_FORMAT_R32G32_FLOAT;
        device->CreateShaderResourceView(texMvF.Get(), &srvDesc, GetCPUDescriptor(2, descSize));
        device->CreateShaderResourceView(texMvB.Get(), &srvDesc, GetCPUDescriptor(3, descSize));

        if (planecount > 1)
        {
            // U Plane:
            srvDesc.Format = DXGI_FORMAT_R8_UNORM;
            device->CreateShaderResourceView(srcRing.texU.Get(), &srvDesc, GetCPUDescriptor(5, descSize));
            device->CreateShaderResourceView(refRing.texU.Get(), &srvDesc, GetCPUDescriptor(6, descSize));

            srvDesc.Format = DXGI_FORMAT_R32G32_FLOAT;
            device->CreateShaderResourceView(texMvF.Get(), &srvDesc, GetCPUDescriptor(7, descSize));
            device->CreateShaderResourceView(texMvB.Get(), &srvDesc, GetCPUDescriptor(8, descSize));

            // V Plane:
            srvDesc.Format = DXGI_FORMAT_R8_UNORM;
            device->CreateShaderResourceView(srcRing.texV.Get(), &srvDesc, GetCPUDescriptor(10, descSize));
            device->CreateShaderResourceView(refRing.texV.Get(), &srvDesc, GetCPUDescriptor(11, descSize));

            srvDesc.Format = DXGI_FORMAT_R32G32_FLOAT;
            device->CreateShaderResourceView(texMvF.Get(), &srvDesc, GetCPUDescriptor(12, descSize));
            device->CreateShaderResourceView(texMvB.Get(), &srvDesc, GetCPUDescriptor(13, descSize));
        }

        // Blend fallback descriptors:
        srvDesc.Format = DXGI_FORMAT_R8_UNORM;
        device->CreateShaderResourceView(srcRing.texY.Get(), &srvDesc, GetCPUDescriptor(16, descSize));
        device->CreateShaderResourceView(refRing.texY.Get(), &srvDesc, GetCPUDescriptor(17, descSize));

        if (planecount > 1)
        {
            device->CreateShaderResourceView(srcRing.texU.Get(), &srvDesc, GetCPUDescriptor(19, descSize));
            device->CreateShaderResourceView(refRing.texU.Get(), &srvDesc, GetCPUDescriptor(20, descSize));

            device->CreateShaderResourceView(srcRing.texV.Get(), &srvDesc, GetCPUDescriptor(22, descSize));
            device->CreateShaderResourceView(refRing.texV.Get(), &srvDesc, GetCPUDescriptor(23, descSize));
        }
    }

    ~FrameSlot()
    {
        if (uploadBuffer && pUploadMapped)
        {
            uploadBuffer->Unmap(0, nullptr);
            pUploadMapped = nullptr;
        }
        if (readbackBuffer && pReadbackMapped)
        {
            readbackBuffer->Unmap(0, nullptr);
            pReadbackMapped = nullptr;
        }
        if (constBuffer && pConstMapped)
        {
            constBuffer->Unmap(0, nullptr);
            pConstMapped = nullptr;
        }
        if (fenceEvent)
        {
            CloseHandle(fenceEvent);
            fenceEvent = nullptr;
        }
    }
};

struct D3D12FlowSynthesis::Impl
{
    static constexpr int NUM_SLOTS = 2;
    static constexpr int RING_SIZE = 3;

    std::mutex m_initMutex;
    bool m_initialized = false;
    bool m_available = false;
    bool m_enabled = true;

    ComPtr<IDXGIFactory6> m_factory;
    ComPtr<IDXGIAdapter1> m_adapter;
    ComPtr<ID3D12Device> m_device;
    ComPtr<ID3D12CommandQueue> m_queue;
    std::mutex m_queueMutex;

    ComPtr<ID3D12RootSignature> m_warpRootSig;
    ComPtr<ID3D12PipelineState> m_warpPSO;

    ComPtr<ID3D12RootSignature> m_blendRootSig;
    ComPtr<ID3D12PipelineState> m_blendPSO;

    UINT m_descSize = 0;

    // Dimensions tracked for dynamic resizing of Ring textures
    int m_curWidth = 0;
    int m_curHeight = 0;
    int m_curWidthUV = 0;
    int m_curHeightUV = 0;

    // 3-Texture Ring for zero-copy source frame reuse across interleaved slots
    RingTexture m_ring[RING_SIZE];
    int m_lastRefRingIdx = -1;
    std::mutex m_ringMutex;

    std::unique_ptr<FrameSlot> m_slots[NUM_SLOTS];
    std::atomic<uint32_t> m_nextSlot{0};

    bool InitDevice()
    {
        if (m_initialized) return m_available;
        m_initialized = true;

        ID3D12Device* sharedDev = D3D12MotionSearch::GetInstance().GetDevice();

        if (sharedDev)
        {
            m_device = sharedDev;
        }
        else
        {
            HRESULT hr = CreateDXGIFactory2(0, IID_PPV_ARGS(&m_factory));
            if (FAILED(hr)) return false;

            for (UINT i = 0; m_factory->EnumAdapterByGpuPreference(i, DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE, IID_PPV_ARGS(&m_adapter)) != DXGI_ERROR_NOT_FOUND; ++i)
            {
                DXGI_ADAPTER_DESC1 desc;
                m_adapter->GetDesc1(&desc);
                if (!(desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE))
                    break;
            }

            if (!m_adapter)
            {
                if (FAILED(m_factory->EnumAdapters1(0, &m_adapter))) return false;
            }

            hr = D3D12CreateDevice(m_adapter.Get(), D3D_FEATURE_LEVEL_11_0, IID_PPV_ARGS(&m_device));
            if (FAILED(hr)) return false;
        }

        // Dedicated Direct Command Queue for Flow Synthesis
        D3D12_COMMAND_QUEUE_DESC qDesc = {};
        qDesc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
        HRESULT hr = m_device->CreateCommandQueue(&qDesc, IID_PPV_ARGS(&m_queue));
        if (FAILED(hr)) return false;

        m_descSize = m_device->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);

        // 2. Create Root Signature for FlowWarpCS
        D3D12_ROOT_PARAMETER warpParams[3] = {};

        warpParams[0].ParameterType = D3D12_ROOT_PARAMETER_TYPE_CBV;
        warpParams[0].Descriptor.ShaderRegister = 0;
        warpParams[0].Descriptor.RegisterSpace = 0;
        warpParams[0].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

        D3D12_DESCRIPTOR_RANGE srvRange = {};
        srvRange.RangeType = D3D12_DESCRIPTOR_RANGE_TYPE_SRV;
        srvRange.NumDescriptors = 4;
        srvRange.BaseShaderRegister = 0;
        srvRange.RegisterSpace = 0;
        srvRange.OffsetInDescriptorsFromTableStart = D3D12_DESCRIPTOR_RANGE_OFFSET_APPEND;

        warpParams[1].ParameterType = D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
        warpParams[1].DescriptorTable.NumDescriptorRanges = 1;
        warpParams[1].DescriptorTable.pDescriptorRanges = &srvRange;
        warpParams[1].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

        D3D12_DESCRIPTOR_RANGE uavRange = {};
        uavRange.RangeType = D3D12_DESCRIPTOR_RANGE_TYPE_UAV;
        uavRange.NumDescriptors = 1;
        uavRange.BaseShaderRegister = 0;
        uavRange.RegisterSpace = 0;
        uavRange.OffsetInDescriptorsFromTableStart = D3D12_DESCRIPTOR_RANGE_OFFSET_APPEND;

        warpParams[2].ParameterType = D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
        warpParams[2].DescriptorTable.NumDescriptorRanges = 1;
        warpParams[2].DescriptorTable.pDescriptorRanges = &uavRange;
        warpParams[2].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

        D3D12_STATIC_SAMPLER_DESC samplers[2] = {};
        samplers[0].Filter = D3D12_FILTER_MIN_MAG_LINEAR_MIP_POINT;
        samplers[0].AddressU = D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
        samplers[0].AddressV = D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
        samplers[0].AddressW = D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
        samplers[0].ShaderRegister = 0;
        samplers[0].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

        samplers[1].Filter = D3D12_FILTER_MIN_MAG_MIP_POINT;
        samplers[1].AddressU = D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
        samplers[1].AddressV = D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
        samplers[1].AddressW = D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
        samplers[1].ShaderRegister = 1;
        samplers[1].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

        D3D12_ROOT_SIGNATURE_DESC warpRsDesc = {};
        warpRsDesc.NumParameters = 3;
        warpRsDesc.pParameters = warpParams;
        warpRsDesc.NumStaticSamplers = 2;
        warpRsDesc.pStaticSamplers = samplers;
        warpRsDesc.Flags = D3D12_ROOT_SIGNATURE_FLAG_NONE;

        ComPtr<ID3DBlob> rsBlob, rsError;
        hr = D3D12SerializeRootSignature(&warpRsDesc, D3D_ROOT_SIGNATURE_VERSION_1, &rsBlob, &rsError);
        if (FAILED(hr)) return false;

        hr = m_device->CreateRootSignature(0, rsBlob->GetBufferPointer(), rsBlob->GetBufferSize(), IID_PPV_ARGS(&m_warpRootSig));
        if (FAILED(hr)) return false;

        D3D12_COMPUTE_PIPELINE_STATE_DESC warpPsoDesc = {};
        warpPsoDesc.pRootSignature = m_warpRootSig.Get();
        warpPsoDesc.CS = { g_FlowWarpCS, sizeof(g_FlowWarpCS) };
        hr = m_device->CreateComputePipelineState(&warpPsoDesc, IID_PPV_ARGS(&m_warpPSO));
        if (FAILED(hr)) return false;

        // 3. Create Root Signature & PSO for FlowBlendFallbackCS
        D3D12_ROOT_PARAMETER blendParams[3] = {};
        blendParams[0].ParameterType = D3D12_ROOT_PARAMETER_TYPE_CBV;
        blendParams[0].Descriptor.ShaderRegister = 0;
        blendParams[0].Descriptor.RegisterSpace = 0;
        blendParams[0].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

        D3D12_DESCRIPTOR_RANGE blendSrvRange = {};
        blendSrvRange.RangeType = D3D12_DESCRIPTOR_RANGE_TYPE_SRV;
        blendSrvRange.NumDescriptors = 2;
        blendSrvRange.BaseShaderRegister = 0;
        blendSrvRange.RegisterSpace = 0;
        blendSrvRange.OffsetInDescriptorsFromTableStart = D3D12_DESCRIPTOR_RANGE_OFFSET_APPEND;

        blendParams[1].ParameterType = D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
        blendParams[1].DescriptorTable.NumDescriptorRanges = 1;
        blendParams[1].DescriptorTable.pDescriptorRanges = &blendSrvRange;
        blendParams[1].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

        D3D12_DESCRIPTOR_RANGE blendUavRange = {};
        blendUavRange.RangeType = D3D12_DESCRIPTOR_RANGE_TYPE_UAV;
        blendUavRange.NumDescriptors = 1;
        blendUavRange.BaseShaderRegister = 0;
        blendUavRange.RegisterSpace = 0;
        blendUavRange.OffsetInDescriptorsFromTableStart = D3D12_DESCRIPTOR_RANGE_OFFSET_APPEND;

        blendParams[2].ParameterType = D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
        blendParams[2].DescriptorTable.NumDescriptorRanges = 1;
        blendParams[2].DescriptorTable.pDescriptorRanges = &blendUavRange;
        blendParams[2].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

        D3D12_ROOT_SIGNATURE_DESC blendRsDesc = {};
        blendRsDesc.NumParameters = 3;
        blendRsDesc.pParameters = blendParams;
        blendRsDesc.NumStaticSamplers = 0;
        blendRsDesc.pStaticSamplers = nullptr;
        blendRsDesc.Flags = D3D12_ROOT_SIGNATURE_FLAG_NONE;

        rsBlob.Reset();
        rsError.Reset();
        hr = D3D12SerializeRootSignature(&blendRsDesc, D3D_ROOT_SIGNATURE_VERSION_1, &rsBlob, &rsError);
        if (FAILED(hr)) return false;

        hr = m_device->CreateRootSignature(0, rsBlob->GetBufferPointer(), rsBlob->GetBufferSize(), IID_PPV_ARGS(&m_blendRootSig));
        if (FAILED(hr)) return false;

        D3D12_COMPUTE_PIPELINE_STATE_DESC blendPsoDesc = {};
        blendPsoDesc.pRootSignature = m_blendRootSig.Get();
        blendPsoDesc.CS = { g_FlowBlendCS, sizeof(g_FlowBlendCS) };
        hr = m_device->CreateComputePipelineState(&blendPsoDesc, IID_PPV_ARGS(&m_blendPSO));
        if (FAILED(hr)) return false;

        // 4. Initialize Multi-Buffering Frame Slots
        for (int i = 0; i < NUM_SLOTS; ++i)
        {
            m_slots[i] = std::make_unique<FrameSlot>();
            if (!m_slots[i]->Init(m_device.Get(), m_warpPSO.Get()))
                return false;
        }

        m_available = true;
        return true;
    }

    bool EnsureGlobalRingTextures(int width, int height, int widthUV, int heightUV, int planecount)
    {
        if (m_curWidth == width && m_curHeight == height &&
            m_curWidthUV == widthUV && m_curHeightUV == heightUV &&
            m_ring[0].texY)
        {
            return true;
        }

        m_curWidth = width;
        m_curHeight = height;
        m_curWidthUV = widthUV;
        m_curHeightUV = heightUV;
        m_lastRefRingIdx = -1;

        for (int i = 0; i < RING_SIZE; ++i)
        {
            m_ring[i].texY.Reset();
            m_ring[i].texU.Reset();
            m_ring[i].texV.Reset();
            m_ring[i].cachedPtr = nullptr;
            m_ring[i].inShaderResource = false;

            if (FAILED(CreateTexture2D(m_device.Get(), width, height, DXGI_FORMAT_R8_UNORM, D3D12_RESOURCE_FLAG_NONE, D3D12_RESOURCE_STATE_COPY_DEST, &m_ring[i].texY)))
                return false;

            if (planecount > 1)
            {
                if (FAILED(CreateTexture2D(m_device.Get(), widthUV, heightUV, DXGI_FORMAT_R8_UNORM, D3D12_RESOURCE_FLAG_NONE, D3D12_RESOURCE_STATE_COPY_DEST, &m_ring[i].texU)))
                    return false;
                if (FAILED(CreateTexture2D(m_device.Get(), widthUV, heightUV, DXGI_FORMAT_R8_UNORM, D3D12_RESOURCE_FLAG_NONE, D3D12_RESOURCE_STATE_COPY_DEST, &m_ring[i].texV)))
                    return false;
            }
        }

        return true;
    }

    ~Impl()
    {
        for (int i = 0; i < NUM_SLOTS; ++i)
        {
            m_slots[i].reset();
        }
    }
};

D3D12FlowSynthesis::D3D12FlowSynthesis()
    : pImpl(new Impl())
{
}

D3D12FlowSynthesis::~D3D12FlowSynthesis()
{
    delete pImpl;
}

D3D12FlowSynthesis& D3D12FlowSynthesis::GetInstance()
{
    static D3D12FlowSynthesis instance;
    return instance;
}

bool D3D12FlowSynthesis::IsAvailable()
{
    std::lock_guard<std::mutex> lock(pImpl->m_initMutex);
    return pImpl->InitDevice() && pImpl->m_enabled && pImpl->m_device && (pImpl->m_device->GetDeviceRemovedReason() == S_OK);
}

void D3D12FlowSynthesis::SetEnabled(bool enabled)
{
    std::lock_guard<std::mutex> lock(pImpl->m_initMutex);
    pImpl->m_enabled = enabled;
}

bool D3D12FlowSynthesis::IsEnabled() const
{
    return pImpl->m_enabled;
}

bool D3D12FlowSynthesis::SynthesizeFrame(
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
    int maskMode,
    int blkSizeX,
    int blkSizeY,
    int flowMode
)
{
    if (!pSrc || !pRef || !pDst || width <= 0 || height <= 0 || nBlkX <= 0 || nBlkY <= 0)
        return false;

    // Verify D3D12 Device state under initialization lock
    {
        std::lock_guard<std::mutex> initLock(pImpl->m_initMutex);
        if (!pImpl->InitDevice() || !pImpl->m_enabled || !pImpl->m_device)
            return false;
        if (pImpl->m_device->GetDeviceRemovedReason() != S_OK)
        {
            pImpl->m_available = false;
            return false;
        }

        if (!pImpl->EnsureGlobalRingTextures(width, height, widthUV, heightUV, planecount))
            return false;
    }

    // Double-Buffering Slot Selection: Non-blocking try_lock on available slot, with round-robin fallback
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

    if (slotIdx == -1)
    {
        slotIdx = (int)(pImpl->m_nextSlot.fetch_add(1, std::memory_order_relaxed) % Impl::NUM_SLOTS);
        slotLock = std::unique_lock<std::mutex>(pImpl->m_slots[slotIdx]->slotMutex);
    }

    FrameSlot& slot = *pImpl->m_slots[slotIdx];

    if (!slot.EnsureSlotBuffers(pImpl->m_device.Get(), width, height, widthUV, heightUV, nBlkX, nBlkY, planecount))
        return false;

    uint8_t* pUploadBase = (uint8_t*)slot.pUploadMapped;
    uint8_t* pReadbackBase = (uint8_t*)slot.pReadbackMapped;
    if (!pUploadBase || !pReadbackBase)
        return false;

    // 1. Content sample checksums for Source & Reference planes
    size_t srcSizeY = (size_t)width * height;
    uint64_t srcS0 = 0, srcS1 = 0, srcS2 = 0, srcS3 = 0, srcS4 = 0;
    if (srcSizeY >= 8 && pSrc[0])
    {
        srcS0 = *(const uint64_t*)(pSrc[0]);
        srcS1 = *(const uint64_t*)(pSrc[0] + (srcSizeY >> 2));
        srcS2 = *(const uint64_t*)(pSrc[0] + (srcSizeY >> 1));
        srcS3 = *(const uint64_t*)(pSrc[0] + ((srcSizeY * 3) >> 2));
        srcS4 = *(const uint64_t*)(pSrc[0] + srcSizeY - 8);
    }

    size_t refSizeY = (size_t)width * height;
    uint64_t refS0 = 0, refS1 = 0, refS2 = 0, refS3 = 0, refS4 = 0;
    if (refSizeY >= 8 && pRef[0])
    {
        refS0 = *(const uint64_t*)(pRef[0]);
        refS1 = *(const uint64_t*)(pRef[0] + (refSizeY >> 2));
        refS2 = *(const uint64_t*)(pRef[0] + (refSizeY >> 1));
        refS3 = *(const uint64_t*)(pRef[0] + ((refSizeY * 3) >> 2));
        refS4 = *(const uint64_t*)(pRef[0] + refSizeY - 8);
    }

    // 2. Determine Ring Texture assignments for zero-copy source reuse
    int srcRingIdx = -1;
    int refRingIdx = -1;
    bool needUploadSrc = false;
    bool needUploadRef = false;

    {
        std::lock_guard<std::mutex> rLock(pImpl->m_ringMutex);

        if (pImpl->m_lastRefRingIdx >= 0 &&
            pImpl->m_ring[pImpl->m_lastRefRingIdx].cachedPtr == pSrc[0] &&
            pImpl->m_ring[pImpl->m_lastRefRingIdx].cachedS0 == srcS0 &&
            pImpl->m_ring[pImpl->m_lastRefRingIdx].cachedS1 == srcS1 &&
            pImpl->m_ring[pImpl->m_lastRefRingIdx].cachedS2 == srcS2 &&
            pImpl->m_ring[pImpl->m_lastRefRingIdx].cachedS3 == srcS3 &&
            pImpl->m_ring[pImpl->m_lastRefRingIdx].cachedS4 == srcS4 &&
            pImpl->m_ring[pImpl->m_lastRefRingIdx].inShaderResource)
        {
            // Consecutive playback hit: pSrc is already in GPU memory!
            srcRingIdx = pImpl->m_lastRefRingIdx;
            refRingIdx = (pImpl->m_lastRefRingIdx + 1) % Impl::RING_SIZE;
            needUploadSrc = false;
            needUploadRef = true;
            pImpl->m_lastRefRingIdx = refRingIdx;
        }
        else
        {
            // Cold start or seek: upload both Src and Ref
            srcRingIdx = 0;
            refRingIdx = 1;
            needUploadSrc = true;
            needUploadRef = true;
            pImpl->m_lastRefRingIdx = 1;
        }

        if (needUploadSrc)
        {
            auto& rSrc = pImpl->m_ring[srcRingIdx];
            rSrc.cachedPtr = pSrc[0];
            rSrc.cachedS0 = srcS0; rSrc.cachedS1 = srcS1; rSrc.cachedS2 = srcS2;
            rSrc.cachedS3 = srcS3; rSrc.cachedS4 = srcS4;
            rSrc.inShaderResource = false;
        }
        if (needUploadRef)
        {
            auto& rRef = pImpl->m_ring[refRingIdx];
            rRef.cachedPtr = pRef[0];
            rRef.cachedS0 = refS0; rRef.cachedS1 = refS1; rRef.cachedS2 = refS2;
            rRef.cachedS3 = refS3; rRef.cachedS4 = refS4;
            rRef.inShaderResource = false;
        }
    }

    // 3. Upload missing plane data to active slot upload buffer
    if (needUploadSrc)
    {
        if (slot.upPitchPlaneY == (size_t)nSrcPitches[0] && (size_t)nSrcPitches[0] == (size_t)width)
        {
            memcpy(pUploadBase + slot.upOffSrcY, pSrc[0], (size_t)width * height);
        }
        else
        {
            for (int y = 0; y < height; ++y)
            {
                memcpy(pUploadBase + slot.upOffSrcY + y * slot.upPitchPlaneY, pSrc[0] + y * nSrcPitches[0], width);
            }
        }

        if (planecount > 1)
        {
            if (slot.upPitchPlaneUV == (size_t)nSrcPitches[1] && (size_t)nSrcPitches[1] == (size_t)widthUV)
            {
                memcpy(pUploadBase + slot.upOffSrcU, pSrc[1], (size_t)widthUV * heightUV);
                memcpy(pUploadBase + slot.upOffSrcV, pSrc[2], (size_t)widthUV * heightUV);
            }
            else
            {
                for (int y = 0; y < heightUV; ++y)
                {
                    memcpy(pUploadBase + slot.upOffSrcU + y * slot.upPitchPlaneUV, pSrc[1] + y * nSrcPitches[1], widthUV);
                    memcpy(pUploadBase + slot.upOffSrcV + y * slot.upPitchPlaneUV, pSrc[2] + y * nSrcPitches[2], widthUV);
                }
            }
        }
    }

    if (needUploadRef)
    {
        if (slot.upPitchPlaneY == (size_t)nRefPitches[0] && (size_t)nRefPitches[0] == (size_t)width)
        {
            memcpy(pUploadBase + slot.upOffRefY, pRef[0], (size_t)width * height);
        }
        else
        {
            for (int y = 0; y < height; ++y)
            {
                memcpy(pUploadBase + slot.upOffRefY + y * slot.upPitchPlaneY, pRef[0] + y * nRefPitches[0], width);
            }
        }

        if (planecount > 1)
        {
            if (slot.upPitchPlaneUV == (size_t)nRefPitches[1] && (size_t)nRefPitches[1] == (size_t)widthUV)
            {
                memcpy(pUploadBase + slot.upOffRefU, pRef[1], (size_t)widthUV * heightUV);
                memcpy(pUploadBase + slot.upOffRefV, pRef[2], (size_t)widthUV * heightUV);
            }
            else
            {
                for (int y = 0; y < heightUV; ++y)
                {
                    memcpy(pUploadBase + slot.upOffRefU + y * slot.upPitchPlaneUV, pRef[1] + y * nRefPitches[1], widthUV);
                    memcpy(pUploadBase + slot.upOffRefV + y * slot.upPitchPlaneUV, pRef[2] + y * nRefPitches[2], widthUV);
                }
            }
        }
    }

    // Extract block motion vectors from mvClipF and mvClipB to upload buffer
    bool isUsableB = mvClipB.IsUsable();
    bool isUsableF = mvClipF.IsUsable();
    bool fallbackBlend = (!isUsableB || !isUsableF);

    if (!fallbackBlend)
    {
        uint8_t* pMvFBase = pUploadBase + slot.upOffMvF;
        uint8_t* pMvBBase = pUploadBase + slot.upOffMvB;

        for (int by = 0; by < nBlkY; ++by)
        {
            Float2* pRowMvF = (Float2*)(pMvFBase + by * slot.upPitchMvF);
            Float2* pRowMvB = (Float2*)(pMvBBase + by * slot.upPitchMvB);

            for (int bx = 0; bx < nBlkX; ++bx)
            {
                int blkIdx = bx + by * nBlkX;
                const FakeBlockData& blkF = mvClipF.GetBlock(0, blkIdx);
                const FakeBlockData& blkB = mvClipB.GetBlock(0, blkIdx);

                pRowMvF[bx] = { (float)blkF.GetMV().x, (float)blkF.GetMV().y };
                pRowMvB[bx] = { (float)blkB.GetMV().x, (float)blkB.GetMV().y };
            }
        }
    }

    // 4. Reset and record Command List for the active slot
    slot.cmdAlloc->Reset();
    slot.cmdList->Reset(slot.cmdAlloc.Get(), fallbackBlend ? pImpl->m_blendPSO.Get() : pImpl->m_warpPSO.Get());

    RingTexture& rSrc = pImpl->m_ring[srcRingIdx];
    RingTexture& rRef = pImpl->m_ring[refRingIdx];

    if (needUploadSrc)
    {
        if (rSrc.inShaderResource)
        {
            RecordBarrier(slot.cmdList.Get(), rSrc.texY.Get(), D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, D3D12_RESOURCE_STATE_COPY_DEST);
            if (planecount > 1)
            {
                RecordBarrier(slot.cmdList.Get(), rSrc.texU.Get(), D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, D3D12_RESOURCE_STATE_COPY_DEST);
                RecordBarrier(slot.cmdList.Get(), rSrc.texV.Get(), D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, D3D12_RESOURCE_STATE_COPY_DEST);
            }
        }
        RecordCopyTexture(slot.cmdList.Get(), rSrc.texY.Get(), slot.uploadBuffer.Get(), slot.upOffSrcY, slot.upPitchPlaneY, width, height, DXGI_FORMAT_R8_UNORM);
        if (planecount > 1)
        {
            RecordCopyTexture(slot.cmdList.Get(), rSrc.texU.Get(), slot.uploadBuffer.Get(), slot.upOffSrcU, slot.upPitchPlaneUV, widthUV, heightUV, DXGI_FORMAT_R8_UNORM);
            RecordCopyTexture(slot.cmdList.Get(), rSrc.texV.Get(), slot.uploadBuffer.Get(), slot.upOffSrcV, slot.upPitchPlaneUV, widthUV, heightUV, DXGI_FORMAT_R8_UNORM);
        }
        RecordBarrier(slot.cmdList.Get(), rSrc.texY.Get(), D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
        if (planecount > 1)
        {
            RecordBarrier(slot.cmdList.Get(), rSrc.texU.Get(), D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
            RecordBarrier(slot.cmdList.Get(), rSrc.texV.Get(), D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
        }
        rSrc.inShaderResource = true;
    }

    if (needUploadRef)
    {
        if (rRef.inShaderResource)
        {
            RecordBarrier(slot.cmdList.Get(), rRef.texY.Get(), D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, D3D12_RESOURCE_STATE_COPY_DEST);
            if (planecount > 1)
            {
                RecordBarrier(slot.cmdList.Get(), rRef.texU.Get(), D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, D3D12_RESOURCE_STATE_COPY_DEST);
                RecordBarrier(slot.cmdList.Get(), rRef.texV.Get(), D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, D3D12_RESOURCE_STATE_COPY_DEST);
            }
        }
        RecordCopyTexture(slot.cmdList.Get(), rRef.texY.Get(), slot.uploadBuffer.Get(), slot.upOffRefY, slot.upPitchPlaneY, width, height, DXGI_FORMAT_R8_UNORM);
        if (planecount > 1)
        {
            RecordCopyTexture(slot.cmdList.Get(), rRef.texU.Get(), slot.uploadBuffer.Get(), slot.upOffRefU, slot.upPitchPlaneUV, widthUV, heightUV, DXGI_FORMAT_R8_UNORM);
            RecordCopyTexture(slot.cmdList.Get(), rRef.texV.Get(), slot.uploadBuffer.Get(), slot.upOffRefV, slot.upPitchPlaneUV, widthUV, heightUV, DXGI_FORMAT_R8_UNORM);
        }
        RecordBarrier(slot.cmdList.Get(), rRef.texY.Get(), D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
        if (planecount > 1)
        {
            RecordBarrier(slot.cmdList.Get(), rRef.texU.Get(), D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
            RecordBarrier(slot.cmdList.Get(), rRef.texV.Get(), D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
        }
        rRef.inShaderResource = true;
    }

    if (!fallbackBlend)
    {
        if (slot.mvInShaderResource)
        {
            RecordBarrier(slot.cmdList.Get(), slot.texMvF.Get(), D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, D3D12_RESOURCE_STATE_COPY_DEST);
            RecordBarrier(slot.cmdList.Get(), slot.texMvB.Get(), D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, D3D12_RESOURCE_STATE_COPY_DEST);
        }
        RecordCopyTexture(slot.cmdList.Get(), slot.texMvF.Get(), slot.uploadBuffer.Get(), slot.upOffMvF, slot.upPitchMvF, nBlkX, nBlkY, DXGI_FORMAT_R32G32_FLOAT);
        RecordCopyTexture(slot.cmdList.Get(), slot.texMvB.Get(), slot.uploadBuffer.Get(), slot.upOffMvB, slot.upPitchMvB, nBlkX, nBlkY, DXGI_FORMAT_R32G32_FLOAT);
        RecordBarrier(slot.cmdList.Get(), slot.texMvF.Get(), D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
        RecordBarrier(slot.cmdList.Get(), slot.texMvB.Get(), D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
        slot.mvInShaderResource = true;
    }

    // Bind active slot Descriptor Heap and setup descriptors
    slot.SetupDescriptors(pImpl->m_device.Get(), rSrc, rRef, planecount, pImpl->m_descSize);
    ID3D12DescriptorHeap* ppHeaps[] = { slot.descHeap.Get() };
    slot.cmdList->SetDescriptorHeaps(1, ppHeaps);

    float normTime = (float)time256 / 256.0f;

    if (!fallbackBlend)
    {
        slot.cmdList->SetComputeRootSignature(pImpl->m_warpRootSig.Get());

        // Dispatch Y Plane
        FlowParamsCB cbY = {};
        cbY.width = (uint32_t)width;
        cbY.height = (uint32_t)height;
        cbY.time = normTime;
        cbY.nPel = (float)nPel;
        cbY.mvScaleX = 1.0f;
        cbY.mvScaleY = 1.0f;
        cbY.maskMode = (uint32_t)maskMode;
        cbY.nBlkSizeX = (uint32_t)blkSizeX;
        cbY.nBlkSizeY = (uint32_t)blkSizeY;
        cbY.nBlkX = (uint32_t)nBlkX;
        cbY.nBlkY = (uint32_t)nBlkY;
        cbY.flowMode = (uint32_t)flowMode;

        memcpy(slot.pConstMapped, &cbY, sizeof(cbY));
        slot.cmdList->SetComputeRootConstantBufferView(0, slot.constBuffer->GetGPUVirtualAddress());
        slot.cmdList->SetComputeRootDescriptorTable(1, slot.GetGPUDescriptor(0, pImpl->m_descSize)); // SRV t0..t3 for Y
        slot.cmdList->SetComputeRootDescriptorTable(2, slot.GetGPUDescriptor(4, pImpl->m_descSize)); // UAV u0 for Y

        slot.cmdList->Dispatch((width + 15) / 16, (height + 7) / 8, 1);

        if (planecount > 1)
        {
            // Dispatch U Plane
            FlowParamsCB cbUV = cbY;
            cbUV.width = (uint32_t)widthUV;
            cbUV.height = (uint32_t)heightUV;
            cbUV.mvScaleX = (float)widthUV / (float)width;
            cbUV.mvScaleY = (float)heightUV / (float)height;
            cbUV.nBlkSizeX = (uint32_t)std::max(1, blkSizeX * widthUV / width);
            cbUV.nBlkSizeY = (uint32_t)std::max(1, blkSizeY * heightUV / height);

            uint8_t* pCbUVLoc = (uint8_t*)slot.pConstMapped + 256;
            memcpy(pCbUVLoc, &cbUV, sizeof(cbUV));
            slot.cmdList->SetComputeRootConstantBufferView(0, slot.constBuffer->GetGPUVirtualAddress() + 256);
            slot.cmdList->SetComputeRootDescriptorTable(1, slot.GetGPUDescriptor(5, pImpl->m_descSize)); // SRV t0..t3 for U
            slot.cmdList->SetComputeRootDescriptorTable(2, slot.GetGPUDescriptor(9, pImpl->m_descSize)); // UAV u0 for U

            slot.cmdList->Dispatch((widthUV + 15) / 16, (heightUV + 7) / 8, 1);

            // Dispatch V Plane
            slot.cmdList->SetComputeRootDescriptorTable(1, slot.GetGPUDescriptor(10, pImpl->m_descSize)); // SRV t0..t3 for V
            slot.cmdList->SetComputeRootDescriptorTable(2, slot.GetGPUDescriptor(14, pImpl->m_descSize)); // UAV u0 for V

            slot.cmdList->Dispatch((widthUV + 15) / 16, (heightUV + 7) / 8, 1);
        }
    }
    else
    {
        // Fallback: Pure direct frame crossfade
        slot.cmdList->SetComputeRootSignature(pImpl->m_blendRootSig.Get());

        BlendParamsCB blendCB = {};
        blendCB.blendWidth = (uint32_t)width;
        blendCB.blendHeight = (uint32_t)height;
        blendCB.blendTime = normTime;

        memcpy(slot.pConstMapped, &blendCB, sizeof(blendCB));
        slot.cmdList->SetComputeRootConstantBufferView(0, slot.constBuffer->GetGPUVirtualAddress());
        slot.cmdList->SetComputeRootDescriptorTable(1, slot.GetGPUDescriptor(16, pImpl->m_descSize));
        slot.cmdList->SetComputeRootDescriptorTable(2, slot.GetGPUDescriptor(18, pImpl->m_descSize));

        slot.cmdList->Dispatch((width + 15) / 16, (height + 7) / 8, 1);

        if (planecount > 1)
        {
            BlendParamsCB blendCBUV = blendCB;
            blendCBUV.blendWidth = (uint32_t)widthUV;
            blendCBUV.blendHeight = (uint32_t)heightUV;

            uint8_t* pCbUVLoc = (uint8_t*)slot.pConstMapped + 256;
            memcpy(pCbUVLoc, &blendCBUV, sizeof(blendCBUV));
            slot.cmdList->SetComputeRootConstantBufferView(0, slot.constBuffer->GetGPUVirtualAddress() + 256);
            slot.cmdList->SetComputeRootDescriptorTable(1, slot.GetGPUDescriptor(19, pImpl->m_descSize));
            slot.cmdList->SetComputeRootDescriptorTable(2, slot.GetGPUDescriptor(21, pImpl->m_descSize));

            slot.cmdList->Dispatch((widthUV + 15) / 16, (heightUV + 7) / 8, 1);

            slot.cmdList->SetComputeRootDescriptorTable(1, slot.GetGPUDescriptor(22, pImpl->m_descSize));
            slot.cmdList->SetComputeRootDescriptorTable(2, slot.GetGPUDescriptor(24, pImpl->m_descSize));

            slot.cmdList->Dispatch((widthUV + 15) / 16, (heightUV + 7) / 8, 1);
        }
    }

    // Transition Output Textures from UNORDERED_ACCESS to COPY_SOURCE and record readback
    RecordBarrier(slot.cmdList.Get(), slot.texOutY.Get(), D3D12_RESOURCE_STATE_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_COPY_SOURCE);
    RecordReadbackTexture(slot.cmdList.Get(), slot.readbackBuffer.Get(), slot.rbOffOutY, slot.rbPitchOutY, slot.texOutY.Get(), width, height, DXGI_FORMAT_R8_UNORM);
    RecordBarrier(slot.cmdList.Get(), slot.texOutY.Get(), D3D12_RESOURCE_STATE_COPY_SOURCE, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);

    if (planecount > 1)
    {
        RecordBarrier(slot.cmdList.Get(), slot.texOutU.Get(), D3D12_RESOURCE_STATE_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_COPY_SOURCE);
        RecordReadbackTexture(slot.cmdList.Get(), slot.readbackBuffer.Get(), slot.rbOffOutU, slot.rbPitchOutU, slot.texOutU.Get(), widthUV, heightUV, DXGI_FORMAT_R8_UNORM);
        RecordBarrier(slot.cmdList.Get(), slot.texOutU.Get(), D3D12_RESOURCE_STATE_COPY_SOURCE, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);

        RecordBarrier(slot.cmdList.Get(), slot.texOutV.Get(), D3D12_RESOURCE_STATE_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_COPY_SOURCE);
        RecordReadbackTexture(slot.cmdList.Get(), slot.readbackBuffer.Get(), slot.rbOffOutV, slot.rbPitchOutV, slot.texOutV.Get(), widthUV, heightUV, DXGI_FORMAT_R8_UNORM);
        RecordBarrier(slot.cmdList.Get(), slot.texOutV.Get(), D3D12_RESOURCE_STATE_COPY_SOURCE, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    }

    slot.cmdList->Close();

    // 5. Asynchronous Queue Execution: lightweight lock around command submission
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
        return false;
    }

    // 6. Read back pixels to destination frame planes
    // Fast path: bulk contiguous memcpy when pitches match row width
    if (slot.rbPitchOutY == (size_t)nDstPitches[0] && (size_t)nDstPitches[0] == (size_t)width)
    {
        memcpy(pDst[0], pReadbackBase + slot.rbOffOutY, (size_t)width * height);
    }
    else
    {
        for (int y = 0; y < height; ++y)
        {
            memcpy(pDst[0] + y * nDstPitches[0], pReadbackBase + slot.rbOffOutY + y * slot.rbPitchOutY, width);
        }
    }

    if (planecount > 1)
    {
        if (slot.rbPitchOutU == (size_t)nDstPitches[1] && (size_t)nDstPitches[1] == (size_t)widthUV)
        {
            memcpy(pDst[1], pReadbackBase + slot.rbOffOutU, (size_t)widthUV * heightUV);
            memcpy(pDst[2], pReadbackBase + slot.rbOffOutV, (size_t)widthUV * heightUV);
        }
        else
        {
            for (int y = 0; y < heightUV; ++y)
            {
                memcpy(pDst[1] + y * nDstPitches[1], pReadbackBase + slot.rbOffOutU + y * slot.rbPitchOutU, widthUV);
                memcpy(pDst[2] + y * nDstPitches[2], pReadbackBase + slot.rbOffOutV + y * slot.rbPitchOutV, widthUV);
            }
        }
    }

    return true;
}
