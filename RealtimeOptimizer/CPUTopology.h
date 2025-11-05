#pragma once
#include <windows.h>
#include <vector>
#include <string>

enum class CoreType {
    Unknown,
    PCore,
    ECore
};

struct LogicalCore {
    int logicalIndex;
    int physicalCoreId;
    int smtSibling;
    CoreType type;
    int ccdId;
};

class CpuTopology {
public:
    CpuTopology() = default;
    
    bool Initialize();
    void PrintTopology() const;
    
    // Core count getters
    int GetLogicalCoreCount() const { return static_cast<int>(cores_.size()); }
    int GetPhysicalCoreCount() const;
    bool HasHyperThreading() const;
    bool IsDualCCD() const { return isDualCCD_; }
    
    // Core information
    const LogicalCore* GetCoreInfo(int logicalIndex) const;
    
    // Core type lists
    std::vector<int> GetPCores() const;
    std::vector<int> GetECores() const;
    std::vector<int> GetCCD0Cores() const;
    std::vector<int> GetCCD1Cores() const;

private:
    void DetectCoreTypes();
    void DetectSMTPairs();
    void DetectDualCCD();
    
    std::vector<LogicalCore> cores_;
    bool isDualCCD_ = false;
    std::string cpuBrand_;
};