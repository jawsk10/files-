#include "Logger.h"
#include <iostream>
#include <iomanip>
#include <sstream>
#include <filesystem>
#include <windows.h>

// Console color constants
#ifndef FOREGROUND_BLUE
#define FOREGROUND_BLUE      0x0001
#define FOREGROUND_GREEN     0x0002
#define FOREGROUND_RED       0x0004
#define FOREGROUND_INTENSITY 0x0008
#endif

Logger& Logger::GetInstance() {
    static Logger instance;
    return instance;
}

Logger::Logger() 
    : m_minLevel(LogLevel::Info),
      m_consoleOutput(true),
      m_maxFileSize(10 * 1024 * 1024),
      m_running(false) {
}

Logger::~Logger() {
    Shutdown();
}

void Logger::Initialize(const std::string& logFile, LogLevel minLevel, 
                       bool consoleOutput, size_t maxFileSize) {
    std::lock_guard<std::mutex> lock(m_fileMutex);
    
    m_logFile = logFile;
    m_minLevel = minLevel;
    m_consoleOutput = consoleOutput;
    m_maxFileSize = maxFileSize;
    
    // Open log file
    m_fileStream.open(m_logFile, std::ios::app);
    if (!m_fileStream.is_open()) {
        std::cerr << "Failed to open log file: " << m_logFile << std::endl;
        return;
    }
    
    // Start async logging thread
    m_running = true;
    m_logThread = std::make_unique<std::thread>(&Logger::LogThreadProc, this);
    
    Info("=== RealtimeOptimizer Started ===");
}

void Logger::Log(LogLevel level, const std::string& message) {
    if (level < m_minLevel) {
        return;
    }
    
    std::string formattedMsg = FormatLogMessage(level, message);
    
    // Add to queue for async file writing
    {
        std::lock_guard<std::mutex> lock(m_queueMutex);
        m_logQueue.push(formattedMsg);
    }
    m_cv.notify_one();
    
    // Console output if enabled
    if (m_consoleOutput) {
        // Color coding for console (Windows)
        HANDLE hConsole = GetStdHandle(STD_OUTPUT_HANDLE);
        CONSOLE_SCREEN_BUFFER_INFO consoleInfo;
        WORD savedAttributes;
        GetConsoleScreenBufferInfo(hConsole, &consoleInfo);
        savedAttributes = consoleInfo.wAttributes;
        
        switch (level) {
            case LogLevel::Debug:
                SetConsoleTextAttribute(hConsole, FOREGROUND_GREEN | FOREGROUND_BLUE);
                break;
            case LogLevel::Info:
                SetConsoleTextAttribute(hConsole, FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_BLUE);
                break;
            case LogLevel::Warning:
                SetConsoleTextAttribute(hConsole, FOREGROUND_RED | FOREGROUND_GREEN | FOREGROUND_INTENSITY);
                break;
            case LogLevel::Error:
                SetConsoleTextAttribute(hConsole, FOREGROUND_RED | FOREGROUND_INTENSITY);
                break;
            case LogLevel::Critical:
                SetConsoleTextAttribute(hConsole, FOREGROUND_RED | FOREGROUND_BLUE | FOREGROUND_INTENSITY);
                break;
        }
        
        std::cout << formattedMsg << std::endl;
        SetConsoleTextAttribute(hConsole, savedAttributes);
    }
}

void Logger::Debug(const std::string& message) {
    Log(LogLevel::Debug, message);
}

void Logger::Info(const std::string& message) {
    Log(LogLevel::Info, message);
}

void Logger::Warning(const std::string& message) {
    Log(LogLevel::Warning, message);
}

void Logger::Error(const std::string& message) {
    Log(LogLevel::Error, message);
}

void Logger::Critical(const std::string& message) {
    Log(LogLevel::Critical, message);
}

void Logger::Flush() {
    std::unique_lock<std::mutex> lock(m_queueMutex);
    
    while (!m_logQueue.empty()) {
        lock.unlock();
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
        lock.lock();
    }
    
    if (m_fileStream.is_open()) {
        m_fileStream.flush();
    }
}

void Logger::Shutdown() {
    if (m_running) {
        Info("=== RealtimeOptimizer Shutting Down ===");
        
        m_running = false;
        m_cv.notify_all();
        
        if (m_logThread && m_logThread->joinable()) {
            m_logThread->join();
        }
        
        if (m_fileStream.is_open()) {
            m_fileStream.close();
        }
    }
}

void Logger::LogThreadProc() {
    while (m_running) {
        std::unique_lock<std::mutex> lock(m_queueMutex);
        m_cv.wait(lock, [this] { return !m_logQueue.empty() || !m_running; });
        
        while (!m_logQueue.empty()) {
            std::string msg = m_logQueue.front();
            m_logQueue.pop();
            lock.unlock();
            
            // Write to file
            {
                std::lock_guard<std::mutex> fileLock(m_fileMutex);
                if (m_fileStream.is_open()) {
                    m_fileStream << msg << std::endl;
                    m_fileStream.flush();
                    
                    // Check file size for rotation
                    m_fileStream.seekp(0, std::ios::end);
                    size_t fileSize = m_fileStream.tellp();
                    if (fileSize > m_maxFileSize) {
                        RotateLogFile();
                    }
                }
            }
            
            lock.lock();
        }
    }
    
    // Flush remaining messages
    std::lock_guard<std::mutex> lock(m_queueMutex);
    while (!m_logQueue.empty()) {
        std::string msg = m_logQueue.front();
        m_logQueue.pop();
        
        if (m_fileStream.is_open()) {
            m_fileStream << msg << std::endl;
        }
    }
}

void Logger::RotateLogFile() {
    m_fileStream.close();
    
    // Generate backup filename with timestamp
    auto now = std::chrono::system_clock::now();
    auto time_t = std::chrono::system_clock::to_time_t(now);
    std::tm timeInfo;
    localtime_s(&timeInfo, &time_t);
    
    std::stringstream ss;
    ss << m_logFile << ".";
    ss << std::put_time(&timeInfo, "%Y%m%d_%H%M%S");
    ss << ".bak";
    
    std::string backupFile = ss.str();
    
    // Rename current log file
    try {
        std::filesystem::rename(m_logFile, backupFile);
    } catch (...) {
        // Ignore rename errors
    }
    
    // Open new log file
    m_fileStream.open(m_logFile, std::ios::app);
}

std::string Logger::FormatLogMessage(LogLevel level, const std::string& message) {
    std::stringstream ss;
    ss << GetTimestamp() << " [" << GetLevelString(level) << "] " << message;
    return ss.str();
}

std::string Logger::GetLevelString(LogLevel level) const {
    switch (level) {
        case LogLevel::Debug:    return "DEBUG";
        case LogLevel::Info:     return "INFO ";
        case LogLevel::Warning:  return "WARN ";
        case LogLevel::Error:    return "ERROR";
        case LogLevel::Critical: return "CRIT ";
        default:                 return "UNKN ";
    }
}

std::string Logger::GetTimestamp() const {
    auto now = std::chrono::system_clock::now();
    auto time_t = std::chrono::system_clock::to_time_t(now);
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        now.time_since_epoch()) % 1000;
    
    std::tm timeInfo;
    localtime_s(&timeInfo, &time_t);
    
    std::stringstream ss;
    ss << std::put_time(&timeInfo, "%Y-%m-%d %H:%M:%S");
    ss << '.' << std::setfill('0') << std::setw(3) << ms.count();
    
    return ss.str();
}
