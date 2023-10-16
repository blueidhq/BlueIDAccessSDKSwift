#ifndef BLUE_LOG_H
#define BLUE_LOG_H

#include "core/BlueCore.h"

#include <stdio.h>
#include <stdarg.h>

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct BlueLogEvent
    {
        va_list ap;
        bool noArgs;
        const char *pFormat;
        const char *pFile;
        int line;
        int severity;
    } BlueLogEvent_t;

    typedef enum BlueLogSeverity
    {
        BlueLogSeverity_Error = 1,
        BlueLogSeverity_Warn = 2,
        BlueLogSeverity_Info = 3,
        BlueLogSeverity_Debug = 4,
    } BlueLogSeverity_t;

#if BLUE_LOG_LEVEL > 3
#define BLUE_LOG_DEBUG(...) blueLog_Log(BlueLogSeverity_Debug, __FILE__, __LINE__, __VA_ARGS__)
#define BLUE_LOG_HEXDUMP(...) blueLog_LogHexdump(BlueLogSeverity_Debug, __FILE__, __LINE__, __VA_ARGS__)
#else
#define BLUE_LOG_DEBUG(...)
#define BLUE_LOG_HEXDUMP(...)
#endif

#if BLUE_LOG_LEVEL > 2
#define BLUE_LOG_INFO(...) blueLog_Log(BlueLogSeverity_Info, __FILE__, __LINE__, __VA_ARGS__)
#else
#define BLUE_LOG_INFO(...)
#endif

#if BLUE_LOG_LEVEL > 1
#define BLUE_LOG_WARN(...) blueLog_Log(BlueLogSeverity_Warn, __FILE__, __LINE__, __VA_ARGS__)
#else
#define BLUE_LOG_WARN(...)
#endif

#if BLUE_LOG_LEVEL > 0
#define BLUE_LOG_ERROR(...) blueLog_Log(BlueLogSeverity_Error, __FILE__, __LINE__, __VA_ARGS__)
#else
#define BLUE_LOG_ERROR(...)
#endif

    void blueLog_FormatMessage(BlueLogEvent_t *const pEvent, char *pBuffer, uint32_t bufferSize);

    void blueLog_Log(int severity, const char *const pFile, int line, const char *const pFormat, ...);

    void blueLog_LogMsg(int severity, const char *const pFile, int line, const char *pMessage);

    void blueLog_LogHexdump(int severity, const char *const pFile, int line, const void *const pData, size_t size);

    // -- can be implemented by an installed driver
    void blueLog_PrintLog(BlueLogEvent_t *const pEvent);

    // -- can be implemented by any storage but must not be
    void blueLog_StoreLog(BlueLogEvent_t *const pEvent);

#ifdef __cplusplus
}
#endif

#endif
