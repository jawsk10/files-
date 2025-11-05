#pragma once
#include <string>
#include <fstream>
#include <mutex>
#include <chrono>
#include <memory>
#include <queue>
#include <thread>
#include <atomic>

enum class LogLevel {
    Debug = 0,
    Info = 1,
    Warning = 2,
    Error = 3,
    Critical = 4
};

class Logger {
public:
    // Singleton pattern
    static Logger& GetInstance();
    
    // Delete copy constructor and assignment
    Logger(const Logger&) = delete;
    Logger& operator=(const Logger&) = delete;
    
    // Configuration
    void Initialize(const std::string& logFile = "RealtimeOptimizer.log", 
                   LogLevel minLevel = LogLevel::Info,
                   bool consoleOutput = true,
                   size_t maxFileSize = 10 * 1024 * 1024); // 10MB default
    
    // Logging methods
    void Log(LogLevel level, const std::string& message);
    void Debug(const std::string& message);
    void Info(const std::string& message);
    void Warning(const std::string& message);
    void Error(const std::string& message);
    void Critical(const std::string& message);
    
    // Log with formatting
    template<typename... Args>
    void LogF(LogLevel level, const std::string& format, Args... args);
    
    // Flush pending logs
    void Flush();
    
    // Shutdown logger
    void Shutdown();
    
    // Set minimum log level
    void SetMinLevel(LogLevel level) { m_minLevel = level; }
    LogLevel GetMinLevel() const { return m_minLevel; }
    
    // Enable/disable console output
    void SetConsoleOutput(bool enabled) { m_consoleOutput = enabled; }

private:
    Logger();
    ~Logger();
    
    // Async logging thread
    void LogThreadProc();
    
    // Rotate log file if too large
    void RotateLogFile();
    
    // Format log message
    std::string FormatLogMessage(LogLevel level, const std::string& message);
    
    // Get string representation of log level
    std::string GetLevelString(LogLevel level) const;
    
    // Get current timestamp
    std::string GetTimestamp() const;
    
    // Member variables
    std::string m_logFile;
    LogLevel m_minLevel;
    bool m_consoleOutput;
    size_t m_maxFileSize;
    
    std::ofstream m_fileStream;
    std::mutex m_fileMutex;
    std::mutex m_queueMutex;
    
    // Async logging
    std::queue<std::string> m_logQueue;
    std::unique_ptr<std::thread> m_logThread;
    std::atomic<bool> m_running;
    std::condition_variable m_cv;
};

// Convenience macros
#define LOG_DEBUG(msg) Logger::GetInstance().Debug(msg)
#define LOG_INFO(msg) Logger::GetInstance().Info(msg)
#define LOG_WARNING(msg) Logger::GetInstance().Warning(msg)
#define LOG_ERROR(msg) Logger::GetInstance().Error(msg)
#define LOG_CRITICAL(msg) Logger::GetInstance().Critical(msg)

// Template implementation
template<typename... Args>
void Logger::LogF(LogLevel level, const std::string& format, Args... args) {
    char buffer[4096];
    snprintf(buffer, sizeof(buffer), format.c_str(), args...);
    Log(level, std::string(buffer));
}
