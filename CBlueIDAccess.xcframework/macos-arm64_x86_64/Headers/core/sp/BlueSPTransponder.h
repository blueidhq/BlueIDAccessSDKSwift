#ifndef BLUE_SP_TRANSPONDER_H
#define BLUE_SP_TRANSPONDER_H

#include "core/sp/BlueSP.h"

typedef void BlueSPTransponderHandlerContext_t;

typedef struct BlueSPTransponderHandlerVtable
{
    BlueReturnCode_t (*getTerminalPublicKey)(BlueSPTransponderHandlerContext_t *pContext, const char *const pDeviceId, uint8_t *const pTerminalPublicKey, uint16_t *const pTerminalPublicKeySize);
} BlueSPTransponderHandlerVtable_t;

typedef struct BlueSPTransponderHandler
{
    BlueSPTransponderHandlerVtable_t const *pFuncs;
    BlueSPTransponderHandlerContext_t *pContext;
} BlueSPTransponderHandler_t;

typedef struct BlueSPTransponderConfiguration
{
    const BlueSPTransponderHandler_t *pHandler;
} BlueSPTransponderConfiguration_t;

typedef void (*BlueSPTransponderFinishedCallbackFunc_t)(BlueReturnCode_t returnCode);

#ifdef __cplusplus
extern "C"
{
#endif

    BlueReturnCode_t blueSPTransponder_Init(const BlueSPTransponderConfiguration_t *const pConfiguration);
    BlueReturnCode_t blueSPTransponder_Release(void);

    BlueReturnCode_t blueSPTransponder_SendRequest(const char *const pDeviceId, const BlueSPConnection_t *const pConnection, const BlueSPData_t *const pData, BlueSPResult_t *const pResult, int16_t *const pStatusCode, BlueSPTransponderFinishedCallbackFunc_t callback);
    BlueReturnCode_t blueSPTransponder_SendRequest_Ext(const char *const pDeviceId, const BlueSPConnection_t *const pConnection, const uint8_t *const pDataBuffer, uint16_t dataBufferSize, uint8_t *const pResultBuffer, uint16_t resultBufferSize, int16_t *const pStatusCode, BlueSPTransponderFinishedCallbackFunc_t callback);

#ifdef BLUE_TEST
    void blueSPTransponder_GetSessionSalt(uint8_t *const pTransponderSalt);
#endif

#ifdef __cplusplus
}
#endif

#endif
