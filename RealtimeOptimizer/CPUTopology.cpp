#include "CpuTopology.h"
#include <iostream>
#include <algorithm>
#include <intrin.h>

// Define SYSTEM_CPU_SET_INFORMATION if not available in Windows SDK
// Use completely unique names to avoid any conflicts
#if !defined(SYSTEM_CPU_SET_INFORMATION)

typedef enum _RT_OPTIMIZER_CPU_SET_INFO_TYPE {
    RtOptimizerCpuSetInformation = 0
} RT_OPTIMIZER_CPU_SET_INFO_TYPE;

typedef struct _RT_OPTIMIZER_CPU_SET_INFO {
    DWORD Size;
    RT_OPTIMIZER_CPU_SET_INFO_TYPE Type;
    union {
        struct {
            DWORD Id;
            WORD Group;
            BYTE LogicalProcessorIndex;
            BYTE CoreIndex;
            BYTE LastLevelCacheIndex;
            BYTE NumaNodeIndex;
            BYTE EfficiencyClass;
            BYTE AllFlags;
        } CpuSet;
    };
} RT_OPTIMIZER_CPU_SET_INFO, *PRT_OPTIMIZER_CPU_SET_INFO;

// Map to standard names only if not already defined
#define SYSTEM_CPU_SET_INFORMATION RT_OPTIMIZER_CPU_SET_INFO
#define PSYSTEM_CPU_SET_INFORMATION PRT_OPTIMIZER_CPU_SET_INFO
#define SYSTEM_CPU_SET_INFORMATION_TYPE RT_OPTIMIZER_CPU_SET_INFO_TYPE
#define CpuSetInformation RtOptimizerCpuSetInformation

#endif

bool CpuTopology::Initialize() {
    SYSTEM_INFO sysInfo;
    GetSystemInfo(&sysInfo);
    
    int logicalCount = static_cast<int>(sysInfo.dwNumberOfProcessors);
    
    // Get CPU brand string
    int cpuInfo[4] = { 0 };
    char brand[49] = { 0 };
    __cpuid(cpuInfo, 0x80000002);
    memcpy(brand, cpuInfo, sizeof(cpuInfo));
    __cpuid(cpuInfo, 0x80000003);
    memcpy(brand + 16, cpuInfo, sizeof(cpuInfo));
    __cpuid(cpuInfo, 0x80000004);
    memcpy(brand + 32, cpuInfo, sizeof(cpuInfo));
    cpuBrand_ = std::string(brand);
    
    // Initialize cores
    cores_.resize(logicalCount);
    for (int i = 0; i < logicalCount; i++) {
        cores_[i].logicalIndex = i;
        cores_[i].physicalCoreId = i;
        cores_[i].smtSibling = -1;
        cores_[i].type = CoreType::Unknown;
        cores_[i].ccdId = -1;
    }
    
    // Detect core features
    DetectCoreTypes();
    DetectSMTPairs();
    DetectDualCCD();
    
    return true;
}

void CpuTopology::PrintTopology() const {
    std::cout << "CPU: " << cpuBrand_ << std::endl;
    std::cout << "Logical Cores: " << cores_.size() << std::endl;
    std::cout << "Physical Cores: " << GetPhysicalCoreCount() << std::endl;
    std::cout << "Hyper-Threading: " << (HasHyperThreading() ? "Enabled" : "Disabled") << std::endl;
    std::cout << "Dual-CCD: " << (isDualCCD_ ? "Yes" : "No") << std::endl;
    std::cout << std::endl;
    
    auto pCores = GetPCores();
    auto eCores = GetECores();
    
    if (!eCores.empty()) {
        std::cout << "P-Cores: ";
        for (size_t i = 0; i < pCores.size(); i++) {
            std::cout << pCores[i];
            if (i < pCores.size() - 1) std::cout << ", ";
        }
        std::cout << std::endl;
        
        std::cout << "E-Cores: ";
        for (size_t i = 0; i < eCores.size(); i++) {
            std::cout << eCores[i];
            if (i < eCores.size() - 1) std::cout << ", ";
        }
        std::cout << std::endl;
    } else {
        std::cout << "All cores are P-cores (no E-cores detected)" << std::endl;
    }
    
    if (isDualCCD_) {
        auto ccd0 = GetCCD0Cores();
        auto ccd1 = GetCCD1Cores();
        std::cout << "CCD0: ";
        for (size_t i = 0; i < ccd0.size(); i++) {
            std::cout << ccd0[i];
            if (i < ccd0.size() - 1) std::cout << ", ";
        }
        std::cout << std::endl;
        std::cout << "CCD1: ";
        for (size_t i = 0; i < ccd1.size(); i++) {
            std::cout << ccd1[i];
            if (i < ccd1.size() - 1) std::cout << ", ";
        }
        std::cout << std::endl;
    }
}

int CpuTopology::GetPhysicalCoreCount() const {
    int maxPhysical = 0;
    for (const auto& core : cores_) {
        if (core.physicalCoreId > maxPhysical) {
            maxPhysical = core.physicalCoreId;
        }
    }
    return maxPhysical + 1;
}

bool CpuTopology::HasHyperThreading() const {
    for (const auto& core : cores_) {
        if (core.smtSibling != -1) {
            return true;
        }
    }
    return false;
}

const LogicalCore* CpuTopology::GetCoreInfo(int logicalIndex) const {
    if (logicalIndex >= 0 && logicalIndex < static_cast<int>(cores_.size())) {
        return &cores_[logicalIndex];
    }
    return nullptr;
}

std::vector<int> CpuTopology::GetPCores() const {
    std::vector<int> pCores;
    for (const auto& core : cores_) {
        if (core.type == CoreType::PCore) {
            pCores.push_back(core.logicalIndex);
        }
    }
    return pCores;
}

std::vector<int> CpuTopology::GetECores() const {
    std::vector<int> eCores;
    for (const auto& core : cores_) {
        if (core.type == CoreType::ECore) {
            eCores.push_back(core.logicalIndex);
        }
    }
    return eCores;
}

std::vector<int> CpuTopology::GetCCD0Cores() const {
    std::vector<int> ccd0;
    for (const auto& core : cores_) {
        if (core.ccdId == 0) {
            ccd0.push_back(core.logicalIndex);
        }
    }
    return ccd0;
}

std::vector<int> CpuTopology::GetCCD1Cores() const {
    std::vector<int> ccd1;
    for (const auto& core : cores_) {
        if (core.ccdId == 1) {
            ccd1.push_back(core.logicalIndex);
        }
    }
    return ccd1;
}

void CpuTopology::DetectCoreTypes() {
    typedef BOOL(WINAPI* GetSystemCpuSetInformationFunc)(
        PSYSTEM_CPU_SET_INFORMATION, ULONG, PULONG, HANDLE, ULONG);
    
    HMODULE kernel32 = GetModuleHandleA("kernel32.dll");
    auto GetSystemCpuSetInformationPtr = (GetSystemCpuSetInformationFunc)
        GetProcAddress(kernel32, "GetSystemCpuSetInformation");
    
    if (GetSystemCpuSetInformationPtr) {
        ULONG bufferSize = 0;
        GetSystemCpuSetInformationPtr(nullptr, 0, &bufferSize, GetCurrentProcess(), 0);
        
        if (bufferSize > 0) {
            std::vector<BYTE> buffer(bufferSize);
            PSYSTEM_CPU_SET_INFORMATION cpuSetInfo = 
                reinterpret_cast<PSYSTEM_CPU_SET_INFORMATION>(buffer.data());
            
            if (GetSystemCpuSetInformationPtr(cpuSetInfo, bufferSize, &bufferSize, 
                                             GetCurrentProcess(), 0)) {
                ULONG offset = 0;
                while (offset < bufferSize) {
                    PSYSTEM_CPU_SET_INFORMATION info = 
                        reinterpret_cast<PSYSTEM_CPU_SET_INFORMATION>(buffer.data() + offset);
                    
                    if (info->Type == CpuSetInformation) {
                        DWORD logicalIndex = info->CpuSet.LogicalProcessorIndex;
                        if (logicalIndex < static_cast<DWORD>(cores_.size())) {
                            if (info->CpuSet.EfficiencyClass == 0) {
                                cores_[logicalIndex].type = CoreType::ECore;
                            } else if (info->CpuSet.EfficiencyClass == 1) {
                                cores_[logicalIndex].type = CoreType::PCore;
                            }
                        }
                    }
                    
                    offset += info->Size;
                }
            }
        }
    }
    
    // If no E-cores detected, mark all as P-cores
    bool hasECores = false;
    for (const auto& core : cores_) {
        if (core.type == CoreType::ECore) {
            hasECores = true;
            break;
        }
    }
    
    if (!hasECores) {
        for (auto& core : cores_) {
            core.type = CoreType::PCore;
        }
    }
}

void CpuTopology::DetectSMTPairs() {
    int logicalCount = static_cast<int>(cores_.size());
    
    // Simple pairing for SMT siblings (assuming consecutive logical IDs)
    for (int i = 0; i < logicalCount; i += 2) {
        if (i + 1 < logicalCount) {
            if (cores_[i].type == cores_[i + 1].type) {
                cores_[i].smtSibling = i + 1;
                cores_[i + 1].smtSibling = i;
                cores_[i].physicalCoreId = i / 2;
                cores_[i + 1].physicalCoreId = i / 2;
            }
        }
    }
}

void CpuTopology::DetectDualCCD() {
    std::string brandLower = cpuBrand_;
    std::transform(brandLower.begin(), brandLower.end(), brandLower.begin(), ::tolower);
    
    // Known dual-CCD AMD Ryzen models
    const char* dualCCDModels[] = {
        "ryzen 9 7900x", "ryzen 9 7950x",
        "ryzen 9 9900x", "ryzen 9 9950x",
        "ryzen 9 5900x", "ryzen 9 5950x",
        "ryzen 9 3900x", "ryzen 9 3950x"
    };
    
    for (const char* model : dualCCDModels) {
        if (brandLower.find(model) != std::string::npos) {
            isDualCCD_ = true;
            break;
        }
    }
    
    if (isDualCCD_) {
        // Assign cores to CCDs (first half to CCD0, second half to CCD1)
        int halfCount = static_cast<int>(cores_.size()) / 2;
        for (size_t i = 0; i < cores_.size(); i++) {
            cores_[i].ccdId = (static_cast<int>(i) < halfCount) ? 0 : 1;
        }
    }
}