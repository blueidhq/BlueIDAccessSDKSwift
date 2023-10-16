#include <string.h>

#include "core/BlueLog.h"

#ifndef BLUE_LOG_LEVEL
#error "BLUE_LOG_LEVEL must be defined"
#endif

__attribute__((weak)) void blueLog_PrintLog(BlueLogEvent_t *const pEvent)
{
    // NOOP
}

__attribute__((weak)) void blueLog_StoreLog(BlueLogEvent_t *const pEvent)
{
    // NOOP
}

void blueLog_FormatMessage(BlueLogEvent_t *const pEvent, char *pBuffer, uint32_t bufferSize)
{
    if (pEvent->noArgs)
    {
        snprintf(pBuffer, bufferSize, "%s", pEvent->pFormat);
    }
    else
    {
        vsnprintf(pBuffer, bufferSize, pEvent->pFormat, pEvent->ap);
    }
}

void blueLog_Log(int severity, const char *const pFile, int line, const char *const pFormat, ...)
{
    if (severity > BLUE_LOG_LEVEL)
    {
        return;
    }

    BlueLogEvent_t event =
        {
            .noArgs = false,
            .pFormat = pFormat,
            .pFile = strrchr(pFile, '/') ? strrchr(pFile, '/') + 1 : pFile,
            .line = line,
            .severity = severity,
        };

    va_start(event.ap, pFormat);

    blueLog_PrintLog(&event);
    blueLog_StoreLog(&event);

    va_end(event.ap);
}

void blueLog_LogMsg(int severity, const char *const pFile, int line, const char *pMessage)
{
    if (severity > BLUE_LOG_LEVEL)
    {
        return;
    }

    BlueLogEvent_t ev =
        {
            .noArgs = true,
            .pFormat = pMessage,
            .pFile = strrchr(pFile, '/') ? strrchr(pFile, '/') + 1 : pFile,
            .line = line,
            .severity = severity,
        };

    blueLog_PrintLog(&ev);
}

void blueLog_LogHexdump(int severity, const char *const pFile, int line, const void *const pData, size_t size)
{
    char output[4096] =
        {
            0,
        };

    size_t i;
    size_t written = 0;
    size_t outputSize = sizeof(output);

    for (i = 0; i < size; i++)
    {
        written += snprintf(output + written, outputSize - written, "0x%02X, ", ((uint8_t *)pData)[i] & 0xFF);
    }

    output[written] = '\0';

    blueLog_Log(severity, pFile, line, "hex (%d bytes): %s", size, output);
}
