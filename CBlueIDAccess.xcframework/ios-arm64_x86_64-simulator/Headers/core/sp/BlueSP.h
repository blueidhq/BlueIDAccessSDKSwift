#ifndef BLUE_SP_H
#define BLUE_SP_H

#include "core/BlueCore.h"

typedef struct ecc_key ecc_key;

typedef struct BlueSPConnection BlueSPConnection_t;

typedef void BlueSPConnectionContext_t;

typedef BlueReturnCode_t (*BlueSPDataAvailableFunc_t)(const BlueSPConnection_t *const pConnection);
typedef BlueReturnCode_t (*BlueSPReceivedFunc_t)(void);
typedef BlueReturnCode_t (*BlueSPReceiveFinishFunc_t)(void);

typedef struct BlueSPConnectionVtable
{
    uint16_t (*getMaxFrameSize)(BlueSPConnectionContext_t *pContext);

    // If set, the finishCallback on receive and must be called manually to let the connection advance
    bool (*hasFinishCallback)(BlueSPConnectionContext_t *pContext);

    BlueReturnCode_t (*transmit)(BlueSPConnectionContext_t *pContext, const uint8_t *const pTxBuffer, uint16_t txBufferSize);

    BlueReturnCode_t (*receive)(BlueSPConnectionContext_t *pContext, uint8_t *const pRxBuffer, uint16_t rxBufferSize, uint16_t *const pRxReturnedSize, BlueSPReceivedFunc_t receivedCallback, BlueSPReceiveFinishFunc_t finishedCallback);
} BlueSPConnectionVtable_t;

typedef struct BlueSPConnection
{
    BlueSPConnectionVtable_t const *pFuncs;
    BlueSPConnectionContext_t *pContext;
} BlueSPConnection_t;

typedef struct ecc_key ecc_key;

#ifdef __cplusplus
extern "C"
{
#endif

    BlueReturnCode_t blueSP_Transmit(const BlueSPConnection_t *const pConnection, int16_t statusCode, const uint8_t *const pData, uint16_t dataSize);

    // If returns BlueReturnCode_Pending then callback is called, otherwise if returns BlueReturnCode_Ok the callback is never called and the data is available after the return
    BlueReturnCode_t blueSP_Receive(const BlueSPConnection_t *const pConnection, uint8_t *const pData, uint16_t availableDataSize, uint16_t *const pReturnedDataSize, int16_t *const pStatusCode, BlueSPDataAvailableFunc_t availableCallback);

    BlueReturnCode_t blueSP_SignData(BlueSPData_t *const pData, const uint8_t *const pPrivateKeyBuffer, uint16_t privateKeyBufferSize);

    BlueReturnCode_t blueSP_SignData_Ext(const uint8_t *const pSpData, uint16_t spDataSize, uint8_t *const pSignedSpData, uint16_t signedSpDataSize, const uint8_t *const pPrivateKeyBuffer, uint16_t privateKeyBufferSize);

#ifdef BLUE_TEST
    void blueSP_SwapTemporaryReceiveContext(void);
#endif

#ifdef __cplusplus
}
#endif

#endif
