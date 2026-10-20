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
        float    occlusionNorm;
    };

    struct alignas(16) BlendParamsCB
    {
        uint32_t blendWidth;
        uint32_t blendHeight;
        float    blendTime;
        uint32_t blendPad;
    };
}

struct D3D12FlowSynthesis::Impl
{
    std::mutex m_mutex;
    bool m_initialized = false;
    bool m_available = false;
    bool m_enabled = true;

    ComPtr<IDXGIFactory6> m_factory;
    ComPtr<IDXGIAdapter1> m_adapter;
    ComPtr<ID3D12Device> m_device;
    ComPtr<ID3D12CommandQueue> m_queue;
    ComPtr<ID3D12CommandAllocator> m_cmdAlloc;
    ComPtr<ID3D12GraphicsCommandList> m_cmdList;

    ComPtr<ID3D12RootSignature> m_warpRootSig;
    ComPtr<ID3D12PipelineState> m_warpPSO;

    ComPtr<ID3D12RootSignature> m_blendRootSig;
    ComPtr<ID3D12PipelineState> m_blendPSO;

    ComPtr<ID3D12DescriptorHeap> m_descHeap;
    UINT m_descSize = 0;

    ComPtr<ID3D12Fence> m_fence;
    HANDLE m_fenceEvent = nullptr;
    uint64_t m_fenceValue = 0;

    // Dimensions tracked for dynamic resource resizing
    int m_curWidth = 0;
    int m_curHeight = 0;
    int m_curWidthUV = 0;
    int m_curHeightUV = 0;
    int m_curBlkX = 0;
    int m_curBlkY = 0;

    // Textures: Planes (Y, U, V)
    ComPtr<ID3D12Resource> m_texSrcY;
    ComPtr<ID3D12Resource> m_texSrcU;
    ComPtr<ID3D12Resource> m_texSrcV;

    ComPtr<ID3D12Resource> m_texRefY;
    ComPtr<ID3D12Resource> m_texRefU;
    ComPtr<ID3D12Resource> m_texRefV;

    ComPtr<ID3D12Resource> m_texOutY;
    ComPtr<ID3D12Resource> m_texOutU;
    ComPtr<ID3D12Resource> m_texOutV;

    // Textures: Motion Vectors (Fwd, Bwd)
    ComPtr<ID3D12Resource> m_texMvF;
    ComPtr<ID3D12Resource> m_texMvB;

    // Linear Upload & Readback Buffers
    ComPtr<ID3D12Resource> m_uploadBuffer;
    ComPtr<ID3D12Resource> m_readbackBuffer;
    ComPtr<ID3D12Resource> m_constBuffer;

    void* m_pUploadMapped = nullptr;
    void* m_pReadbackMapped = nullptr;
    void* m_pConstMapped = nullptr;

    size_t m_uploadBufferSize = 0;
    size_t m_readbackBufferSize = 0;

    // Subresource footprint offsets inside m_uploadBuffer
    size_t m_upOffSrcY = 0, m_upPitchSrcY = 0;
    size_t m_upOffSrcU = 0, m_upPitchSrcU = 0;
    size_t m_upOffSrcV = 0, m_upPitchSrcV = 0;

    size_t m_upOffRefY = 0, m_upPitchRefY = 0;
    size_t m_upOffRefU = 0, m_upPitchRefU = 0;
    size_t m_upOffRefV = 0, m_upPitchRefV = 0;

    size_t m_upOffMvF = 0,  m_upPitchMvF = 0;
    size_t m_upOffMvB = 0,  m_upPitchMvB = 0;

    // Subresource footprint offsets inside m_readbackBuffer
    size_t m_rbOffOutY = 0, m_rbPitchOutY = 0;
    size_t m_rbOffOutU = 0, m_rbPitchOutU = 0;
    size_t m_rbOffOutV = 0, m_rbPitchOutV = 0;

    HRESULT CreateBuffer(size_t size, D3D12_HEAP_TYPE heapType, D3D12_RESOURCE_STATES initialState, D3D12_RESOURCE_FLAGS flags, ID3D12Resource** ppResource)
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

        return m_device->CreateCommittedResource(&heapProps, D3D12_HEAP_FLAG_NONE, &desc, initialState, nullptr, IID_PPV_ARGS(ppResource));
    }

    HRESULT CreateTexture2D(UINT width, UINT height, DXGI_FORMAT format, D3D12_RESOURCE_FLAGS flags, D3D12_RESOURCE_STATES initialState, ID3D12Resource** ppResource)
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

        return m_device->CreateCommittedResource(&heapProps, D3D12_HEAP_FLAG_NONE, &desc, initialState, nullptr, IID_PPV_ARGS(ppResource));
    }

    D3D12_CPU_DESCRIPTOR_HANDLE GetCPUDescriptor(UINT index)
    {
        D3D12_CPU_DESCRIPTOR_HANDLE handle = m_descHeap->GetCPUDescriptorHandleForHeapStart();
        handle.ptr += (SIZE_T)index * m_descSize;
        return handle;
    }

    D3D12_GPU_DESCRIPTOR_HANDLE GetGPUDescriptor(UINT index)
    {
        D3D12_GPU_DESCRIPTOR_HANDLE handle = m_descHeap->GetGPUDescriptorHandleForHeapStart();
        handle.ptr += (UINT64)index * m_descSize;
        return handle;
    }

    bool InitDevice()
    {
        if (m_initialized) return m_available;
        m_initialized = true;

        // 1. First, attempt to share existing device and command queue from D3D12MotionSearch
        ID3D12Device* sharedDev = D3D12MotionSearch::GetInstance().GetDevice();
        ID3D12CommandQueue* sharedQueue = D3D12MotionSearch::GetInstance().GetCommandQueue();

        if (sharedDev && sharedQueue)
        {
            m_device = sharedDev;
            m_queue = sharedQueue;
        }
        else
        {
            // Fall back to creating independent device
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

            D3D12_COMMAND_QUEUE_DESC qDesc = {};
            qDesc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
            hr = m_device->CreateCommandQueue(&qDesc, IID_PPV_ARGS(&m_queue));
            if (FAILED(hr)) return false;
        }

        HRESULT hr = m_device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&m_cmdAlloc));
        if (FAILED(hr)) return false;

        // 2. Create Descriptor Heap (CBV_SRV_UAV)
        D3D12_DESCRIPTOR_HEAP_DESC heapDesc = {};
        heapDesc.NumDescriptors = 64;
        heapDesc.Type = D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;
        heapDesc.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;
        hr = m_device->CreateDescriptorHeap(&heapDesc, IID_PPV_ARGS(&m_descHeap));
        if (FAILED(hr)) return false;
        m_descSize = m_device->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);

        // 3. Create Root Signature for FlowWarpCS
        // Parameter 0: Root CBV (b0)
        // Parameter 1: Descriptor Table (SRV t0..t3)
        // Parameter 2: Descriptor Table (UAV u0)
        // Static Sampler 0: s0 (Linear clamp)
        // Static Sampler 1: s1 (Point clamp)
        D3D12_ROOT_PARAMETER warpParams[3] = {};

        // 0: Root CBV b0
        warpParams[0].ParameterType = D3D12_ROOT_PARAMETER_TYPE_CBV;
        warpParams[0].Descriptor.ShaderRegister = 0;
        warpParams[0].Descriptor.RegisterSpace = 0;
        warpParams[0].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

        // 1: Descriptor Table SRVs (t0..t3)
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

        // 2: Descriptor Table UAVs (u0)
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

        // Static samplers
        D3D12_STATIC_SAMPLER_DESC samplers[2] = {};
        // s0: Linear Clamp
        samplers[0].Filter = D3D12_FILTER_MIN_MAG_LINEAR_MIP_POINT;
        samplers[0].AddressU = D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
        samplers[0].AddressV = D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
        samplers[0].AddressW = D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
        samplers[0].ShaderRegister = 0;
        samplers[0].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;

        // s1: Point Clamp
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

        // 4. Create Root Signature & PSO for FlowBlendFallbackCS
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

        // 5. Create Command List, Fence, and Constant Buffer
        hr = m_device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, m_cmdAlloc.Get(), m_warpPSO.Get(), IID_PPV_ARGS(&m_cmdList));
        if (FAILED(hr)) return false;
        m_cmdList->Close();

        hr = m_device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&m_fence));
        if (FAILED(hr)) return false;

        m_fenceEvent = CreateEvent(nullptr, FALSE, FALSE, nullptr);
        if (!m_fenceEvent) return false;

        // 256-byte aligned constant buffer
        CreateBuffer(1024, D3D12_HEAP_TYPE_UPLOAD, D3D12_RESOURCE_STATE_GENERIC_READ, D3D12_RESOURCE_FLAG_NONE, &m_constBuffer);
        m_constBuffer->Map(0, nullptr, &m_pConstMapped);

        m_available = true;
        return true;
    }

    void EnsureTexturesAndBuffers(int width, int height, int widthUV, int heightUV, int nBlkX, int nBlkY, int planecount)
    {
        if (m_curWidth == width && m_curHeight == height &&
            m_curWidthUV == widthUV && m_curHeightUV == heightUV &&
            m_curBlkX == nBlkX && m_curBlkY == nBlkY &&
            m_texSrcY && m_uploadBuffer && m_readbackBuffer)
        {
            return;
        }

        m_curWidth = width;
        m_curHeight = height;
        m_curWidthUV = widthUV;
        m_curHeightUV = heightUV;
        m_curBlkX = nBlkX;
        m_curBlkY = nBlkY;

        // Reset existing resources
        m_texSrcY.Reset(); m_texSrcU.Reset(); m_texSrcV.Reset();
        m_texRefY.Reset(); m_texRefU.Reset(); m_texRefV.Reset();
        m_texOutY.Reset(); m_texOutU.Reset(); m_texOutV.Reset();
        m_texMvF.Reset();  m_texMvB.Reset();

        // 1. Create Texture2Ds
        CreateTexture2D(width, height, DXGI_FORMAT_R8_UNORM, D3D12_RESOURCE_FLAG_NONE, D3D12_RESOURCE_STATE_COPY_DEST, &m_texSrcY);
        CreateTexture2D(width, height, DXGI_FORMAT_R8_UNORM, D3D12_RESOURCE_FLAG_NONE, D3D12_RESOURCE_STATE_COPY_DEST, &m_texRefY);
        CreateTexture2D(width, height, DXGI_FORMAT_R8_UNORM, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_UNORDERED_ACCESS, &m_texOutY);

        if (planecount > 1)
        {
            CreateTexture2D(widthUV, heightUV, DXGI_FORMAT_R8_UNORM, D3D12_RESOURCE_FLAG_NONE, D3D12_RESOURCE_STATE_COPY_DEST, &m_texSrcU);
            CreateTexture2D(widthUV, heightUV, DXGI_FORMAT_R8_UNORM, D3D12_RESOURCE_FLAG_NONE, D3D12_RESOURCE_STATE_COPY_DEST, &m_texRefU);
            CreateTexture2D(widthUV, heightUV, DXGI_FORMAT_R8_UNORM, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_UNORDERED_ACCESS, &m_texOutU);

            CreateTexture2D(widthUV, heightUV, DXGI_FORMAT_R8_UNORM, D3D12_RESOURCE_FLAG_NONE, D3D12_RESOURCE_STATE_COPY_DEST, &m_texSrcV);
            CreateTexture2D(widthUV, heightUV, DXGI_FORMAT_R8_UNORM, D3D12_RESOURCE_FLAG_NONE, D3D12_RESOURCE_STATE_COPY_DEST, &m_texRefV);
            CreateTexture2D(widthUV, heightUV, DXGI_FORMAT_R8_UNORM, D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_UNORDERED_ACCESS, &m_texOutV);
        }

        CreateTexture2D(nBlkX, nBlkY, DXGI_FORMAT_R32G32_FLOAT, D3D12_RESOURCE_FLAG_NONE, D3D12_RESOURCE_STATE_COPY_DEST, &m_texMvF);
        CreateTexture2D(nBlkX, nBlkY, DXGI_FORMAT_R32G32_FLOAT, D3D12_RESOURCE_FLAG_NONE, D3D12_RESOURCE_STATE_COPY_DEST, &m_texMvB);

        // 2. Compute footprint layouts in upload buffer
        size_t currentUpOffset = 0;

        m_upPitchSrcY = AlignUp(width, D3D12_TEXTURE_DATA_PITCH_ALIGNMENT);
        m_upOffSrcY = AlignUp(currentUpOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
        currentUpOffset = m_upOffSrcY + m_upPitchSrcY * height;

        m_upPitchRefY = m_upPitchSrcY;
        m_upOffRefY = AlignUp(currentUpOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
        currentUpOffset = m_upOffRefY + m_upPitchRefY * height;

        if (planecount > 1)
        {
            m_upPitchSrcU = AlignUp(widthUV, D3D12_TEXTURE_DATA_PITCH_ALIGNMENT);
            m_upOffSrcU = AlignUp(currentUpOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
            currentUpOffset = m_upOffSrcU + m_upPitchSrcU * heightUV;

            m_upPitchRefU = m_upPitchSrcU;
            m_upOffRefU = AlignUp(currentUpOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
            currentUpOffset = m_upOffRefU + m_upPitchRefU * heightUV;

            m_upPitchSrcV = m_upPitchSrcU;
            m_upOffSrcV = AlignUp(currentUpOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
            currentUpOffset = m_upOffSrcV + m_upPitchSrcV * heightUV;

            m_upPitchRefV = m_upPitchSrcU;
            m_upOffRefV = AlignUp(currentUpOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
            currentUpOffset = m_upOffRefV + m_upPitchRefV * heightUV;
        }

        m_upPitchMvF = AlignUp(nBlkX * sizeof(Float2), D3D12_TEXTURE_DATA_PITCH_ALIGNMENT);
        m_upOffMvF = AlignUp(currentUpOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
        currentUpOffset = m_upOffMvF + m_upPitchMvF * nBlkY;

        m_upPitchMvB = m_upPitchMvF;
        m_upOffMvB = AlignUp(currentUpOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
        currentUpOffset = m_upOffMvB + m_upPitchMvB * nBlkY;

        // Allocate upload buffer
        if (m_uploadBuffer && m_pUploadMapped)
        {
            m_uploadBuffer->Unmap(0, nullptr);
            m_pUploadMapped = nullptr;
        }
        m_uploadBufferSize = currentUpOffset;
        m_uploadBuffer.Reset();
        CreateBuffer(m_uploadBufferSize, D3D12_HEAP_TYPE_UPLOAD, D3D12_RESOURCE_STATE_GENERIC_READ, D3D12_RESOURCE_FLAG_NONE, &m_uploadBuffer);
        m_uploadBuffer->Map(0, nullptr, &m_pUploadMapped);

        // 3. Compute footprint layouts in readback buffer
        size_t currentRbOffset = 0;

        m_rbPitchOutY = AlignUp(width, D3D12_TEXTURE_DATA_PITCH_ALIGNMENT);
        m_rbOffOutY = AlignUp(currentRbOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
        currentRbOffset = m_rbOffOutY + m_rbPitchOutY * height;

        if (planecount > 1)
        {
            m_rbPitchOutU = AlignUp(widthUV, D3D12_TEXTURE_DATA_PITCH_ALIGNMENT);
            m_rbOffOutU = AlignUp(currentRbOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
            currentRbOffset = m_rbOffOutU + m_rbPitchOutU * heightUV;

            m_rbPitchOutV = m_rbPitchOutU;
            m_rbOffOutV = AlignUp(currentRbOffset, D3D12_TEXTURE_DATA_PLACEMENT_ALIGNMENT);
            currentRbOffset = m_rbOffOutV + m_rbPitchOutV * heightUV;
        }

        // Allocate readback buffer
        if (m_readbackBuffer && m_pReadbackMapped)
        {
            m_readbackBuffer->Unmap(0, nullptr);
            m_pReadbackMapped = nullptr;
        }
        m_readbackBufferSize = currentRbOffset;
        m_readbackBuffer.Reset();
        CreateBuffer(m_readbackBufferSize, D3D12_HEAP_TYPE_READBACK, D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_FLAG_NONE, &m_readbackBuffer);
        m_readbackBuffer->Map(0, nullptr, &m_pReadbackMapped);

        // 4. Populate Descriptor Heap
        D3D12_SHADER_RESOURCE_VIEW_DESC srvDesc = {};
        srvDesc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
        srvDesc.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2D;
        srvDesc.Texture2D.MipLevels = 1;

        D3D12_UNORDERED_ACCESS_VIEW_DESC uavDesc = {};
        uavDesc.ViewDimension = D3D12_UAV_DIMENSION_TEXTURE2D;

        // Descriptors:
        // Y Plane:
        // 0: SRV SrcY
        // 1: SRV RefY
        // 2: SRV MvF
        // 3: SRV MvB
        // 4: UAV OutY
        srvDesc.Format = DXGI_FORMAT_R8_UNORM;
        m_device->CreateShaderResourceView(m_texSrcY.Get(), &srvDesc, GetCPUDescriptor(0));
        m_device->CreateShaderResourceView(m_texRefY.Get(), &srvDesc, GetCPUDescriptor(1));

        srvDesc.Format = DXGI_FORMAT_R32G32_FLOAT;
        m_device->CreateShaderResourceView(m_texMvF.Get(), &srvDesc, GetCPUDescriptor(2));
        m_device->CreateShaderResourceView(m_texMvB.Get(), &srvDesc, GetCPUDescriptor(3));

        uavDesc.Format = DXGI_FORMAT_R8_UNORM;
        m_device->CreateUnorderedAccessView(m_texOutY.Get(), nullptr, &uavDesc, GetCPUDescriptor(4));

        if (planecount > 1)
        {
            // U Plane:
            // 5: SRV SrcU
            // 6: SRV RefU
            // 7: SRV MvF
            // 8: SRV MvB
            // 9: UAV OutU
            srvDesc.Format = DXGI_FORMAT_R8_UNORM;
            m_device->CreateShaderResourceView(m_texSrcU.Get(), &srvDesc, GetCPUDescriptor(5));
            m_device->CreateShaderResourceView(m_texRefU.Get(), &srvDesc, GetCPUDescriptor(6));

            srvDesc.Format = DXGI_FORMAT_R32G32_FLOAT;
            m_device->CreateShaderResourceView(m_texMvF.Get(), &srvDesc, GetCPUDescriptor(7));
            m_device->CreateShaderResourceView(m_texMvB.Get(), &srvDesc, GetCPUDescriptor(8));

            uavDesc.Format = DXGI_FORMAT_R8_UNORM;
            m_device->CreateUnorderedAccessView(m_texOutU.Get(), nullptr, &uavDesc, GetCPUDescriptor(9));

            // V Plane:
            // 10: SRV SrcV
            // 11: SRV RefV
            // 12: SRV MvF
            // 13: SRV MvB
            // 14: UAV OutV
            srvDesc.Format = DXGI_FORMAT_R8_UNORM;
            m_device->CreateShaderResourceView(m_texSrcV.Get(), &srvDesc, GetCPUDescriptor(10));
            m_device->CreateShaderResourceView(m_texRefV.Get(), &srvDesc, GetCPUDescriptor(11));

            srvDesc.Format = DXGI_FORMAT_R32G32_FLOAT;
            m_device->CreateShaderResourceView(m_texMvF.Get(), &srvDesc, GetCPUDescriptor(12));
            m_device->CreateShaderResourceView(m_texMvB.Get(), &srvDesc, GetCPUDescriptor(13));

            uavDesc.Format = DXGI_FORMAT_R8_UNORM;
            m_device->CreateUnorderedAccessView(m_texOutV.Get(), nullptr, &uavDesc, GetCPUDescriptor(14));
        }

        // Blend fallback descriptors:
        // 16: SRV BlendSrcY
        // 17: SRV BlendRefY
        // 18: UAV BlendOutY
        srvDesc.Format = DXGI_FORMAT_R8_UNORM;
        m_device->CreateShaderResourceView(m_texSrcY.Get(), &srvDesc, GetCPUDescriptor(16));
        m_device->CreateShaderResourceView(m_texRefY.Get(), &srvDesc, GetCPUDescriptor(17));
        uavDesc.Format = DXGI_FORMAT_R8_UNORM;
        m_device->CreateUnorderedAccessView(m_texOutY.Get(), nullptr, &uavDesc, GetCPUDescriptor(18));

        if (planecount > 1)
        {
            // 19, 20, 21 for U
            m_device->CreateShaderResourceView(m_texSrcU.Get(), &srvDesc, GetCPUDescriptor(19));
            m_device->CreateShaderResourceView(m_texRefU.Get(), &srvDesc, GetCPUDescriptor(20));
            m_device->CreateUnorderedAccessView(m_texOutU.Get(), nullptr, &uavDesc, GetCPUDescriptor(21));

            // 22, 23, 24 for V
            m_device->CreateShaderResourceView(m_texSrcV.Get(), &srvDesc, GetCPUDescriptor(22));
            m_device->CreateShaderResourceView(m_texRefV.Get(), &srvDesc, GetCPUDescriptor(23));
            m_device->CreateUnorderedAccessView(m_texOutV.Get(), nullptr, &uavDesc, GetCPUDescriptor(24));
        }
    }

    void RecordCopyTexture(ID3D12Resource* pDstTex, ID3D12Resource* pSrcBuf, size_t bufOffset, size_t rowPitch, UINT width, UINT height, DXGI_FORMAT format)
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

        m_cmdList->CopyTextureRegion(&dstLoc, 0, 0, 0, &srcLoc, nullptr);
    }

    void RecordReadbackTexture(ID3D12Resource* pDstBuf, size_t bufOffset, size_t rowPitch, ID3D12Resource* pSrcTex, UINT width, UINT height, DXGI_FORMAT format)
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

        m_cmdList->CopyTextureRegion(&dstLoc, 0, 0, 0, &srcLoc, nullptr);
    }

    void RecordBarrier(ID3D12Resource* pRes, D3D12_RESOURCE_STATES stateBefore, D3D12_RESOURCE_STATES stateAfter)
    {
        D3D12_RESOURCE_BARRIER b = {};
        b.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        b.Flags = D3D12_RESOURCE_BARRIER_FLAG_NONE;
        b.Transition.pResource = pRes;
        b.Transition.StateBefore = stateBefore;
        b.Transition.StateAfter = stateAfter;
        b.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        m_cmdList->ResourceBarrier(1, &b);
    }

    ~Impl()
    {
        if (m_uploadBuffer && m_pUploadMapped)
        {
            m_uploadBuffer->Unmap(0, nullptr);
            m_pUploadMapped = nullptr;
        }
        if (m_readbackBuffer && m_pReadbackMapped)
        {
            m_readbackBuffer->Unmap(0, nullptr);
            m_pReadbackMapped = nullptr;
        }
        if (m_constBuffer && m_pConstMapped)
        {
            m_constBuffer->Unmap(0, nullptr);
            m_pConstMapped = nullptr;
        }
        if (m_fenceEvent)
        {
            CloseHandle(m_fenceEvent);
            m_fenceEvent = nullptr;
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
    std::lock_guard<std::mutex> lock(pImpl->m_mutex);
    return pImpl->InitDevice() && pImpl->m_enabled;
}

void D3D12FlowSynthesis::SetEnabled(bool enabled)
{
    std::lock_guard<std::mutex> lock(pImpl->m_mutex);
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
    int maskMode
)
{
    if (!pSrc || !pRef || !pDst || width <= 0 || height <= 0 || nBlkX <= 0 || nBlkY <= 0)
        return false;

    std::lock_guard<std::mutex> lock(pImpl->m_mutex);
    if (!pImpl->InitDevice() || !pImpl->m_enabled)
        return false;

    pImpl->EnsureTexturesAndBuffers(width, height, widthUV, heightUV, nBlkX, nBlkY, planecount);

    uint8_t* pUploadBase = (uint8_t*)pImpl->m_pUploadMapped;
    uint8_t* pReadbackBase = (uint8_t*)pImpl->m_pReadbackMapped;
    if (!pUploadBase || !pReadbackBase)
        return false;

    // 1. Copy Source & Reference Plane data to upload buffer
    for (int y = 0; y < height; ++y)
    {
        memcpy(pUploadBase + pImpl->m_upOffSrcY + y * pImpl->m_upPitchSrcY, pSrc[0] + y * nSrcPitches[0], width);
        memcpy(pUploadBase + pImpl->m_upOffRefY + y * pImpl->m_upPitchRefY, pRef[0] + y * nRefPitches[0], width);
    }

    if (planecount > 1)
    {
        for (int y = 0; y < heightUV; ++y)
        {
            memcpy(pUploadBase + pImpl->m_upOffSrcU + y * pImpl->m_upPitchSrcU, pSrc[1] + y * nSrcPitches[1], widthUV);
            memcpy(pUploadBase + pImpl->m_upOffRefU + y * pImpl->m_upPitchRefU, pRef[1] + y * nRefPitches[1], widthUV);
            memcpy(pUploadBase + pImpl->m_upOffSrcV + y * pImpl->m_upPitchSrcV, pSrc[2] + y * nSrcPitches[2], widthUV);
            memcpy(pUploadBase + pImpl->m_upOffRefV + y * pImpl->m_upPitchRefV, pRef[2] + y * nRefPitches[2], widthUV);
        }
    }

    // 2. Extract block motion vectors from mvClipF and mvClipB to upload buffer
    bool isUsableB = mvClipB.IsUsable();
    bool isUsableF = mvClipF.IsUsable();
    bool fallbackBlend = (!isUsableB || !isUsableF);

    if (!fallbackBlend)
    {
        uint8_t* pMvFBase = pUploadBase + pImpl->m_upOffMvF;
        uint8_t* pMvBBase = pUploadBase + pImpl->m_upOffMvB;

        for (int by = 0; by < nBlkY; ++by)
        {
            Float2* pRowMvF = (Float2*)(pMvFBase + by * pImpl->m_upPitchMvF);
            Float2* pRowMvB = (Float2*)(pMvBBase + by * pImpl->m_upPitchMvB);

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

    // 3. Reset and record Command List
    pImpl->m_cmdAlloc->Reset();
    pImpl->m_cmdList->Reset(pImpl->m_cmdAlloc.Get(), fallbackBlend ? pImpl->m_blendPSO.Get() : pImpl->m_warpPSO.Get());

    // Copy upload footprints to textures
    pImpl->RecordCopyTexture(pImpl->m_texSrcY.Get(), pImpl->m_uploadBuffer.Get(), pImpl->m_upOffSrcY, pImpl->m_upPitchSrcY, width, height, DXGI_FORMAT_R8_UNORM);
    pImpl->RecordCopyTexture(pImpl->m_texRefY.Get(), pImpl->m_uploadBuffer.Get(), pImpl->m_upOffRefY, pImpl->m_upPitchRefY, width, height, DXGI_FORMAT_R8_UNORM);

    if (planecount > 1)
    {
        pImpl->RecordCopyTexture(pImpl->m_texSrcU.Get(), pImpl->m_uploadBuffer.Get(), pImpl->m_upOffSrcU, pImpl->m_upPitchSrcU, widthUV, heightUV, DXGI_FORMAT_R8_UNORM);
        pImpl->RecordCopyTexture(pImpl->m_texRefU.Get(), pImpl->m_uploadBuffer.Get(), pImpl->m_upOffRefU, pImpl->m_upPitchRefU, widthUV, heightUV, DXGI_FORMAT_R8_UNORM);
        pImpl->RecordCopyTexture(pImpl->m_texSrcV.Get(), pImpl->m_uploadBuffer.Get(), pImpl->m_upOffSrcV, pImpl->m_upPitchSrcV, widthUV, heightUV, DXGI_FORMAT_R8_UNORM);
        pImpl->RecordCopyTexture(pImpl->m_texRefV.Get(), pImpl->m_uploadBuffer.Get(), pImpl->m_upOffRefV, pImpl->m_upPitchRefV, widthUV, heightUV, DXGI_FORMAT_R8_UNORM);
    }

    if (!fallbackBlend)
    {
        pImpl->RecordCopyTexture(pImpl->m_texMvF.Get(), pImpl->m_uploadBuffer.Get(), pImpl->m_upOffMvF, pImpl->m_upPitchMvF, nBlkX, nBlkY, DXGI_FORMAT_R32G32_FLOAT);
        pImpl->RecordCopyTexture(pImpl->m_texMvB.Get(), pImpl->m_uploadBuffer.Get(), pImpl->m_upOffMvB, pImpl->m_upPitchMvB, nBlkX, nBlkY, DXGI_FORMAT_R32G32_FLOAT);
    }

    // Transition textures from COPY_DEST to NON_PIXEL_SHADER_RESOURCE
    pImpl->RecordBarrier(pImpl->m_texSrcY.Get(), D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    pImpl->RecordBarrier(pImpl->m_texRefY.Get(), D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);

    if (planecount > 1)
    {
        pImpl->RecordBarrier(pImpl->m_texSrcU.Get(), D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
        pImpl->RecordBarrier(pImpl->m_texRefU.Get(), D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
        pImpl->RecordBarrier(pImpl->m_texSrcV.Get(), D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
        pImpl->RecordBarrier(pImpl->m_texRefV.Get(), D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    }

    if (!fallbackBlend)
    {
        pImpl->RecordBarrier(pImpl->m_texMvF.Get(), D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
        pImpl->RecordBarrier(pImpl->m_texMvB.Get(), D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    }

    // Bind Descriptor Heap
    ID3D12DescriptorHeap* ppHeaps[] = { pImpl->m_descHeap.Get() };
    pImpl->m_cmdList->SetDescriptorHeaps(1, ppHeaps);

    float normTime = (float)time256 / 256.0f;

    if (!fallbackBlend)
    {
        pImpl->m_cmdList->SetComputeRootSignature(pImpl->m_warpRootSig.Get());

        // Dispatch Y Plane
        FlowParamsCB cbY = {};
        cbY.width = (uint32_t)width;
        cbY.height = (uint32_t)height;
        cbY.time = normTime;
        cbY.nPel = (float)nPel;
        cbY.mvScaleX = 1.0f;
        cbY.mvScaleY = 1.0f;
        cbY.maskMode = (uint32_t)maskMode;
        cbY.occlusionNorm = 0.05f;

        memcpy(pImpl->m_pConstMapped, &cbY, sizeof(cbY));
        pImpl->m_cmdList->SetComputeRootConstantBufferView(0, pImpl->m_constBuffer->GetGPUVirtualAddress());
        pImpl->m_cmdList->SetComputeRootDescriptorTable(1, pImpl->GetGPUDescriptor(0)); // SRV t0..t3 for Y
        pImpl->m_cmdList->SetComputeRootDescriptorTable(2, pImpl->GetGPUDescriptor(4)); // UAV u0 for Y

        pImpl->m_cmdList->Dispatch((width + 15) / 16, (height + 15) / 16, 1);

        if (planecount > 1)
        {
            // Dispatch U Plane
            FlowParamsCB cbUV = cbY;
            cbUV.width = (uint32_t)widthUV;
            cbUV.height = (uint32_t)heightUV;
            cbUV.mvScaleX = (float)widthUV / (float)width;
            cbUV.mvScaleY = (float)heightUV / (float)height;

            uint8_t* pCbUVLoc = (uint8_t*)pImpl->m_pConstMapped + 256;
            memcpy(pCbUVLoc, &cbUV, sizeof(cbUV));
            pImpl->m_cmdList->SetComputeRootConstantBufferView(0, pImpl->m_constBuffer->GetGPUVirtualAddress() + 256);
            pImpl->m_cmdList->SetComputeRootDescriptorTable(1, pImpl->GetGPUDescriptor(5)); // SRV t0..t3 for U
            pImpl->m_cmdList->SetComputeRootDescriptorTable(2, pImpl->GetGPUDescriptor(9)); // UAV u0 for U

            pImpl->m_cmdList->Dispatch((widthUV + 15) / 16, (heightUV + 15) / 16, 1);

            // Dispatch V Plane
            pImpl->m_cmdList->SetComputeRootDescriptorTable(1, pImpl->GetGPUDescriptor(10)); // SRV t0..t3 for V
            pImpl->m_cmdList->SetComputeRootDescriptorTable(2, pImpl->GetGPUDescriptor(14)); // UAV u0 for V

            pImpl->m_cmdList->Dispatch((widthUV + 15) / 16, (heightUV + 15) / 16, 1);
        }
    }
    else
    {
        // Fallback: Pure direct frame crossfade
        pImpl->m_cmdList->SetComputeRootSignature(pImpl->m_blendRootSig.Get());

        BlendParamsCB blendCB = {};
        blendCB.blendWidth = (uint32_t)width;
        blendCB.blendHeight = (uint32_t)height;
        blendCB.blendTime = normTime;

        memcpy(pImpl->m_pConstMapped, &blendCB, sizeof(blendCB));
        pImpl->m_cmdList->SetComputeRootConstantBufferView(0, pImpl->m_constBuffer->GetGPUVirtualAddress());
        pImpl->m_cmdList->SetComputeRootDescriptorTable(1, pImpl->GetGPUDescriptor(16));
        pImpl->m_cmdList->SetComputeRootDescriptorTable(2, pImpl->GetGPUDescriptor(18));

        pImpl->m_cmdList->Dispatch((width + 15) / 16, (height + 15) / 16, 1);

        if (planecount > 1)
        {
            BlendParamsCB blendCBUV = blendCB;
            blendCBUV.blendWidth = (uint32_t)widthUV;
            blendCBUV.blendHeight = (uint32_t)heightUV;

            uint8_t* pCbUVLoc = (uint8_t*)pImpl->m_pConstMapped + 256;
            memcpy(pCbUVLoc, &blendCBUV, sizeof(blendCBUV));
            pImpl->m_cmdList->SetComputeRootConstantBufferView(0, pImpl->m_constBuffer->GetGPUVirtualAddress() + 256);
            pImpl->m_cmdList->SetComputeRootDescriptorTable(1, pImpl->GetGPUDescriptor(19));
            pImpl->m_cmdList->SetComputeRootDescriptorTable(2, pImpl->GetGPUDescriptor(21));

            pImpl->m_cmdList->Dispatch((widthUV + 15) / 16, (heightUV + 15) / 16, 1);

            pImpl->m_cmdList->SetComputeRootDescriptorTable(1, pImpl->GetGPUDescriptor(22));
            pImpl->m_cmdList->SetComputeRootDescriptorTable(2, pImpl->GetGPUDescriptor(24));

            pImpl->m_cmdList->Dispatch((widthUV + 15) / 16, (heightUV + 15) / 16, 1);
        }
    }

    // Transition Output Textures from UNORDERED_ACCESS to COPY_SOURCE
    pImpl->RecordBarrier(pImpl->m_texOutY.Get(), D3D12_RESOURCE_STATE_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_COPY_SOURCE);
    pImpl->RecordReadbackTexture(pImpl->m_readbackBuffer.Get(), pImpl->m_rbOffOutY, pImpl->m_rbPitchOutY, pImpl->m_texOutY.Get(), width, height, DXGI_FORMAT_R8_UNORM);
    pImpl->RecordBarrier(pImpl->m_texOutY.Get(), D3D12_RESOURCE_STATE_COPY_SOURCE, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);

    if (planecount > 1)
    {
        pImpl->RecordBarrier(pImpl->m_texOutU.Get(), D3D12_RESOURCE_STATE_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_COPY_SOURCE);
        pImpl->RecordReadbackTexture(pImpl->m_readbackBuffer.Get(), pImpl->m_rbOffOutU, pImpl->m_rbPitchOutU, pImpl->m_texOutU.Get(), widthUV, heightUV, DXGI_FORMAT_R8_UNORM);
        pImpl->RecordBarrier(pImpl->m_texOutU.Get(), D3D12_RESOURCE_STATE_COPY_SOURCE, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);

        pImpl->RecordBarrier(pImpl->m_texOutV.Get(), D3D12_RESOURCE_STATE_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_COPY_SOURCE);
        pImpl->RecordReadbackTexture(pImpl->m_readbackBuffer.Get(), pImpl->m_rbOffOutV, pImpl->m_rbPitchOutV, pImpl->m_texOutV.Get(), widthUV, heightUV, DXGI_FORMAT_R8_UNORM);
        pImpl->RecordBarrier(pImpl->m_texOutV.Get(), D3D12_RESOURCE_STATE_COPY_SOURCE, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    }

    // Transition Source & Reference Textures back to COPY_DEST for next frame
    pImpl->RecordBarrier(pImpl->m_texSrcY.Get(), D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, D3D12_RESOURCE_STATE_COPY_DEST);
    pImpl->RecordBarrier(pImpl->m_texRefY.Get(), D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, D3D12_RESOURCE_STATE_COPY_DEST);

    if (planecount > 1)
    {
        pImpl->RecordBarrier(pImpl->m_texSrcU.Get(), D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, D3D12_RESOURCE_STATE_COPY_DEST);
        pImpl->RecordBarrier(pImpl->m_texRefU.Get(), D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, D3D12_RESOURCE_STATE_COPY_DEST);
        pImpl->RecordBarrier(pImpl->m_texSrcV.Get(), D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, D3D12_RESOURCE_STATE_COPY_DEST);
        pImpl->RecordBarrier(pImpl->m_texRefV.Get(), D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, D3D12_RESOURCE_STATE_COPY_DEST);
    }

    if (!fallbackBlend)
    {
        pImpl->RecordBarrier(pImpl->m_texMvF.Get(), D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, D3D12_RESOURCE_STATE_COPY_DEST);
        pImpl->RecordBarrier(pImpl->m_texMvB.Get(), D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE, D3D12_RESOURCE_STATE_COPY_DEST);
    }

    pImpl->m_cmdList->Close();

    // 4. Execute on Queue & Synchronize via Fence
    ID3D12CommandList* ppLists[] = { pImpl->m_cmdList.Get() };
    pImpl->m_queue->ExecuteCommandLists(1, ppLists);

    pImpl->m_fenceValue++;
    pImpl->m_queue->Signal(pImpl->m_fence.Get(), pImpl->m_fenceValue);
    pImpl->m_fence->SetEventOnCompletion(pImpl->m_fenceValue, pImpl->m_fenceEvent);
    WaitForSingleObject(pImpl->m_fenceEvent, INFINITE);

    // 5. Read back pixels to destination frame planes
    for (int y = 0; y < height; ++y)
    {
        memcpy(pDst[0] + y * nDstPitches[0], pReadbackBase + pImpl->m_rbOffOutY + y * pImpl->m_rbPitchOutY, width);
    }

    if (planecount > 1)
    {
        for (int y = 0; y < heightUV; ++y)
        {
            memcpy(pDst[1] + y * nDstPitches[1], pReadbackBase + pImpl->m_rbOffOutU + y * pImpl->m_rbPitchOutU, widthUV);
            memcpy(pDst[2] + y * nDstPitches[2], pReadbackBase + pImpl->m_rbOffOutV + y * pImpl->m_rbPitchOutV, widthUV);
        }
    }

    return true;
}
