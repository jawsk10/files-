#pragma once
#include <string>
#include <vector>
#include <unordered_map>

struct ThreadRule {
    std::string moduleName;
    std::string threadDesc;
    int priority = 0;
    std::string affinityMask;
    int idealProcessor = -1;
    bool isMainThread = false;
    bool disableBoost = false;
    bool disableClones = false;
    bool suspend = false;
    bool terminate = false;
    std::string priorityClass;
};

class ConfigParser {
public:
    ConfigParser() = default;
    
    bool LoadFromFile(const std::string& filename);
    
    // Settings getters
    int GetUpdateTimeout() const { return updateTimeout_; }
    int GetExplorerKillTimeout() const { return explorerKillTimeout_; }
    bool GetEnableKillExplorer() const { return enableKillExplorer_; }
    bool GetEnableIdleSwitching() const { return enableIdleSwitching_; }
    bool GetWinBlockKeys() const { return winBlockKeys_; }
    std::string GetBlockNoGamingMonitor() const { return blockNoGamingMonitor_; }
    
    // Core configuration getters
    std::vector<int> GetOccupiedAffinityCores() const { return occupiedAffinityCores_; }
    std::vector<int> GetOccupiedIdealProcessorCores() const { return occupiedIdealProcessorCores_; }
    
    // Process lists getters
    std::vector<std::string> GetGames() const { return games_; }
    std::vector<std::string> GetProcessesToSuspend() const { return processesToSuspend_; }
    std::vector<std::string> GetProcessesIdlePriority() const { return processesIdlePriority_; }
    std::vector<std::string> GetDisableBoostProcesses() const { return disableBoostProcesses_; }
    
    // Thread rules getters
    std::vector<std::string> GetProcessSections() const;
    std::vector<ThreadRule> GetThreadRules(const std::string& processName) const;

private:
    static std::string Trim(const std::string& str);
    static std::string ToLower(const std::string& str);
    
    void ParseLine(const std::string& line, const std::string& currentSection);
    void ParseSettingsLine(const std::string& key, const std::string& value);
    void ParseThreadRule(const std::string& processName, const std::string& line);
    std::vector<int> ParseCoreList(const std::string& value);
    
    // Settings
    int updateTimeout_ = 100;
    int explorerKillTimeout_ = 60000;
    bool enableKillExplorer_ = false;
    bool enableIdleSwitching_ = false;
    bool winBlockKeys_ = false;
    std::string blockNoGamingMonitor_;
    
    // Core configuration
    std::vector<int> occupiedAffinityCores_;
    std::vector<int> occupiedIdealProcessorCores_;
    
    // Process lists
    std::vector<std::string> games_;
    std::vector<std::string> processesToSuspend_;
    std::vector<std::string> processesIdlePriority_;
    std::vector<std::string> disableBoostProcesses_;
    
    // Thread rules by process name
    std::unordered_map<std::string, std::vector<ThreadRule>> processThreadRules_;
};