#ifndef BLUE_SP_TERMINAL_H
#define BLUE_SP_TERMINAL_H

#include "core/sp/BlueSP.h"

typedef void BlueSPTerminalHandlerContext_t;

typedef struct BlueSPTerminalHandlerVtable
{
    BlueReturnCode_t (*getCurrentTime)(BlueSPTerminalHandlerContext_t *pContext, BlueLocalTimestamp_t *const pTime);
    BlueReturnCode_t (*getCommandGroup)(BlueSPTerminalHandlerContext_t *pContext, const char *const pCommand, char *const pCommandGroup);
    BlueReturnCode_t (*handleCommand)(BlueSPTerminalHandlerContext_t *pContext, const BlueSPTokenCommand_t *const pCommand, BlueSPResult_t *const pResult);
    BlueReturnCode_t (*handleOssSo)(BlueSPTerminalHandlerContext_t *pContext, const BlueLocalTimestamp_t *const pTimestamp, const BlueOssSoMobile_t *const pOssSo, BlueSPResult_t *const pResult);
    BlueReturnCode_t (*handleOssSid)(BlueSPTerminalHandlerContext_t *pContext, const BlueLocalTimestamp_t *const pTimestamp, const BlueOssSidMobile_t *const pOssSid, BlueSPResult_t *const pResult);
    BlueReturnCode_t (*storeEvent)(BlueSPTerminalHandlerContext_t *pContext, const BlueEvent_t *const pEvent);
} BlueSPTerminalHandlerVtable_t;

typedef struct BlueSPTerminalHandler
{
    BlueSPTerminalHandlerVtable_t const *pFuncs;
    BlueSPTerminalHandlerContext_t *pContext;
} BlueSPTerminalHandler_t;

typedef struct BlueSPTerminalConfiguration
{
    const BlueSPTerminalHandler_t *const pHandler;
    const uint8_t *pTerminalPrivateKey;
    uint16_t terminalPrivateKeySize;
    const uint8_t *pSignaturePublicKey;
    uint16_t signaturePublicKeySize;
} BlueSPTerminalConfiguration_t;

#define BLUE_SP_TERMINAL_RETURN_DATA(DATA, FIELDS)                                                          \
    {                                                                                                       \
        int __ret__ = blueUtils_EncodeData(DATA, FIELDS, pResult->data.bytes, sizeof(pResult->data.bytes)); \
        if (__ret__ < 0)                                                                                    \
        {                                                                                                   \
            return __ret__;                                                                                 \
        }                                                                                                   \
        pResult->data.size = __ret__;                                                                       \
        return BlueReturnCode_Ok;                                                                           \
    }

#ifdef __cplusplus
extern "C"
{
#endif

    BlueReturnCode_t blueSPTerminal_Init(const BlueSPTerminalConfiguration_t *const pConfiguration);
    BlueReturnCode_t blueSPTerminal_Release(void);

    BlueReturnCode_t blueSPTerminal_AwaitRequest(const BlueSPConnection_t *const pConnection, bool restartAwaitOnEnding);
    BlueReturnCode_t blueSPTerminal_Clear(void);

#ifdef BLUE_TEST
    void blueSPTerminal_GetSessionSalt(uint8_t *const pTerminalSalt);
#endif

#ifdef __cplusplus
}
#endif

#endif
