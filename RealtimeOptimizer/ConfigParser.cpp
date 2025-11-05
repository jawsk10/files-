#include "ConfigParser.h"
#include <fstream>
#include <sstream>
#include <algorithm>
#include <cctype>

bool ConfigParser::LoadFromFile(const std::string& filename) {
    std::ifstream file(filename);
    if (!file.is_open()) {
        return false;
    }

    std::string line;
    std::string currentSection;
    
    while (std::getline(file, line)) {
        line = Trim(line);
        
        // Skip empty lines and comments
        if (line.empty() || line[0] == '#' || line[0] == ';') {
            continue;
        }
        
        // Check for section header
        if (line[0] == '[' && line.back() == ']') {
            currentSection = line.substr(1, line.length() - 2);
            currentSection = Trim(currentSection);
            continue;
        }
        
        // Parse line based on current section
        ParseLine(line, currentSection);
    }
    
    return true;
}

std::vector<std::string> ConfigParser::GetProcessSections() const {
    std::vector<std::string> sections;
    for (const auto& pair : processThreadRules_) {
        sections.push_back(pair.first);
    }
    return sections;
}

std::vector<ThreadRule> ConfigParser::GetThreadRules(const std::string& processName) const {
    auto it = processThreadRules_.find(processName);
    if (it != processThreadRules_.end()) {
        return it->second;
    }
    return {};
}

std::string ConfigParser::Trim(const std::string& str) {
    size_t first = str.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) return "";
    size_t last = str.find_last_not_of(" \t\r\n");
    return str.substr(first, last - first + 1);
}

std::string ConfigParser::ToLower(const std::string& str) {
    std::string result = str;
    std::transform(result.begin(), result.end(), result.begin(), ::tolower);
    return result;
}

void ConfigParser::ParseLine(const std::string& line, const std::string& currentSection) {
    if (currentSection.empty()) {
        return;
    }
    
    std::string sectionLower = ToLower(currentSection);
    
    // Handle different sections
    if (sectionLower == "settings" || sectionLower == "debug settings") {
        size_t eqPos = line.find('=');
        if (eqPos != std::string::npos) {
            std::string key = Trim(line.substr(0, eqPos));
            std::string value = Trim(line.substr(eqPos + 1));
            ParseSettingsLine(key, value);
        }
    }
    else if (sectionLower == "games") {
        games_.push_back(Trim(line));
    }
    else if (sectionLower == "processestosuspend") {
        processesToSuspend_.push_back(Trim(line));
    }
    else if (sectionLower == "setprocessestoidlepriority") {
        processesIdlePriority_.push_back(Trim(line));
    }
    else if (sectionLower == "disableboost") {
        disableBoostProcesses_.push_back(Trim(line));
    }
    else {
        // Assume it's a process-specific section with thread rules
        ParseThreadRule(currentSection, line);
    }
}

void ConfigParser::ParseSettingsLine(const std::string& key, const std::string& value) {
    std::string keyLower = ToLower(key);
    
    if (keyLower == "updatetimeout") {
        updateTimeout_ = std::stoi(value);
    }
    else if (keyLower == "explorerkilltimeout") {
        explorerKillTimeout_ = std::stoi(value);
    }
    else if (keyLower == "enablekillexplorer") {
        enableKillExplorer_ = (ToLower(value) == "true" || value == "1");
    }
    else if (keyLower == "enableidleswitching") {
        enableIdleSwitching_ = (ToLower(value) == "true" || value == "1");
    }
    else if (keyLower == "winblockkeys") {
        winBlockKeys_ = (ToLower(value) == "true" || value == "1");
    }
    else if (keyLower == "blocknogamingmonitor") {
        blockNoGamingMonitor_ = value;
    }
    else if (keyLower == "occupied_affinity_cores") {
        occupiedAffinityCores_ = ParseCoreList(value);
    }
    else if (keyLower == "occupied_ideal_processor_cores") {
        occupiedIdealProcessorCores_ = ParseCoreList(value);
    }
}

std::vector<int> ConfigParser::ParseCoreList(const std::string& value) {
    std::vector<int> cores;
    if (ToLower(value) == "auto" || value.empty()) {
        return cores;
    }
    
    std::stringstream ss(value);
    std::string item;
    while (std::getline(ss, item, ',')) {
        item = Trim(item);
        if (!item.empty()) {
            try {
                cores.push_back(std::stoi(item));
            } catch (...) {
                // Ignore invalid numbers
            }
        }
    }
    return cores;
}

void ConfigParser::ParseThreadRule(const std::string& processName, const std::string& line) {
    ThreadRule rule;
    
    std::stringstream ss(line);
    std::string token;
    std::vector<std::string> parts;
    
    // Split by comma
    while (std::getline(ss, token, ',')) {
        parts.push_back(Trim(token));
    }
    
    if (parts.empty()) return;
    
    // Parse first part (module or threaddesc)
    std::string firstPart = parts[0];
    if (firstPart.find("module=") == 0) {
        rule.moduleName = Trim(firstPart.substr(7));
        if (!rule.moduleName.empty() && rule.moduleName.back() == '*') {
            rule.isMainThread = true;
            rule.moduleName.pop_back();
        }
    }
    else if (firstPart.find("threaddesc=") == 0) {
        rule.threadDesc = Trim(firstPart.substr(11));
        if (!rule.threadDesc.empty() && rule.threadDesc.back() == '*') {
            rule.isMainThread = true;
            rule.threadDesc.pop_back();
        }
    }
    
    // Parse remaining parts
    for (size_t i = 1; i < parts.size(); i++) {
        std::string part = Trim(parts[i]);
        
        // Check for priority numbers
        if (part.length() > 0 && (part[0] == '-' || std::isdigit(part[0]))) {
            try {
                int num = std::stoi(part);
                if (num == 300) {
                    rule.suspend = true;
                }
                else if (num == 200) {
                    rule.terminate = true;
                }
                else if (num >= -15 && num <= 15) {
                    rule.priority = num;
                }
            } catch (...) {}
        }
        // Check for affinity mask [hex]
        else if (part[0] == '[' && part.back() == ']') {
            rule.affinityMask = part.substr(1, part.length() - 2);
        }
        // Check for ideal processor (number)
        else if (part[0] == '(' && part.back() == ')') {
            std::string idealStr = part.substr(1, part.length() - 2);
            if (ToLower(idealStr) == "auto") {
                rule.idealProcessor = -2;
            } else {
                try {
                    rule.idealProcessor = std::stoi(idealStr);
                } catch (...) {}
            }
        }
        // Check for flags
        else if (ToLower(part) == "disableboost") {
            rule.disableBoost = true;
        }
        else if (ToLower(part) == "disableclones") {
            rule.disableClones = true;
        }
        // Check for priority class
        else if (part.find("priority_class=") == 0) {
            rule.priorityClass = Trim(part.substr(15));
        }
    }
    
    processThreadRules_[processName].push_back(rule);
}