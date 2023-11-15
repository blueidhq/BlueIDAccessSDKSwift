#include "core/BlueUtils.h"
#include "core/BlueLog.h"

#include "core/sp/BlueSPTransponder.h"

#include "wolfssl/wolfcrypt/asn.h"
#include "wolfssl/wolfcrypt/ecc.h"

typedef struct SPTransponderContext
{
    BlueSPTransponderHandler_t handler;
    ecEncCtx *encContext;
} SPTerminalContext_t;

typedef enum SPTransponderSessionStatus
{
    SPTransponderSessionStatus_Idle,
    SPTransponderSessionStatus_WaitForHandshakeReply,
    SPTransponderSessionStatus_WaitForResult,
} SPTransponderSessionStatus_t;

typedef struct SPTransponderSessionContext
{
    SPTransponderSessionStatus_t status;
    const BlueSPToken_t *pToken;
    BlueSPResult_t *pResult;
    int16_t *pStatusCode;
    BlueSPTransponderFinishedCallbackFunc_t callback;
    ecc_key transponderKey;
    bool hasTransponderKey;
    ecc_key terminalPublicKey;
    bool hasTerminalPublicKey;
    uint8_t transmitData[2048];
    uint16_t transmitDataSize;
    uint8_t receiveData[2048];
    uint16_t receiveDataSize;
    uint8_t transponderSalt[EXCHANGE_SALT_SZ];
} SPTransponderSessionContext_t;

static bool transponderInitialized = false;
static SPTerminalContext_t transponderContext;
static SPTransponderSessionContext_t sessionContext;

static BlueReturnCode_t handleSendRequest_Defer(const char *const pDeviceId, const BlueSPConnection_t *const pConnection, const BlueSPToken_t *const pToken, BlueSPResult_t *const pResult, int16_t *const pStatusCode, BlueSPTransponderFinishedCallbackFunc_t callback);
static BlueReturnCode_t handleSendRequest(const char *const pDeviceId, const BlueSPConnection_t *const pConnection, const BlueSPToken_t *const pToken, BlueSPResult_t *const pResult, int16_t *const pStatusCode, BlueSPTransponderFinishedCallbackFunc_t callback);
static BlueReturnCode_t handleReceiveHandshakeReply_Defer(const BlueSPConnection_t *const pConnection);
static BlueReturnCode_t handleReceiveHandshakeReply(const BlueSPConnection_t *const pConnection);
static BlueReturnCode_t handleReceiveResult_Defer(const BlueSPConnection_t *const pConnection);
static BlueReturnCode_t handleReceiveResult(const BlueSPConnection_t *const pConnection);

static BlueReturnCode_t resetSession(void);
static BlueReturnCode_t encryptData(uint8_t *pData, uint16_t dataSize, uint16_t maxDataSize, uint8_t *pBuffer, uint16_t *pBufferSize);
static BlueReturnCode_t decryptData(const uint8_t *pData, uint16_t dataSize, uint8_t *pBuffer, uint16_t *pBufferSize);

#define DEFER_SESSION_BODY(EXPRESSION)              \
    const BlueReturnCode_t returnCode = EXPRESSION; \
    if (returnCode < 0)                             \
    {                                               \
        if (sessionContext.callback)                \
        {                                           \
            sessionContext.callback(returnCode);    \
        }                                           \
        resetSession();                             \
    }                                               \
    return returnCode;

BlueReturnCode_t blueSPTransponder_Init(const BlueSPTransponderConfiguration_t *const pConfiguration)
{
    if (transponderInitialized)
    {
        return BlueReturnCode_InvalidState;
    }

    if (pConfiguration->pHandler == NULL)
    {
        BLUE_LOG_DEBUG("Missing transponder handler");
        return BlueReturnCode_InvalidArguments;
    }

    memset(&transponderContext, 0, sizeof(transponderContext));
    memset(&sessionContext, 0, sizeof(sessionContext));

    // Assign the transponder handler
    memcpy(&transponderContext.handler, pConfiguration->pHandler, sizeof(BlueSPTransponderHandler_t));

    //
    // Initialize our ecc enc context in client mode
    //
    transponderContext.encContext = wc_ecc_ctx_new(REQ_RESP_CLIENT, pRNG);
    if (transponderContext.encContext == NULL)
    {
        BLUE_LOG_ERROR("Failed to create ecc enc context");
        return BlueReturnCode_InvalidState;
    }

    transponderInitialized = true;

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueSPTransponder_Release(void)
{
    if (!transponderInitialized)
    {
        return BlueReturnCode_InvalidState;
    }

    //
    // Terminal
    //

    wc_ecc_ctx_free(transponderContext.encContext);

    transponderInitialized = false;

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueSPTransponder_SendRequest(const char *const pDeviceId, const BlueSPConnection_t *const pConnection, const BlueSPToken_t *const pToken, BlueSPResult_t *const pResult, int16_t *const pStatusCode, BlueSPTransponderFinishedCallbackFunc_t callback)
{
    return handleSendRequest_Defer(pDeviceId, pConnection, pToken, pResult, pStatusCode, callback);
}

BlueReturnCode_t blueSPTransponder_SendRequest_Ext(const char *const pDeviceId, const BlueSPConnection_t *const pConnection, const uint8_t *const pTokenBuffer, uint16_t tokenBufferSize, uint8_t *const pResultBuffer, uint16_t resultBufferSize, int16_t *const pStatusCode, BlueSPTransponderFinishedCallbackFunc_t callback)
{
    BlueSPToken_t token = BLUESPTOKEN_INIT_ZERO;

    BLUE_ERROR_CHECK_DEBUG(blueUtils_DecodeData(&token, BLUESPTOKEN_FIELDS, pTokenBuffer, tokenBufferSize), "Decode SP token buffer");

    BlueSPResult_t result = BLUESPRESULT_INIT_ZERO;

    BLUE_ERROR_CHECK(blueSPTransponder_SendRequest(pDeviceId, pConnection, &token, &result, pStatusCode, callback));

    BLUE_ERROR_CHECK_DEBUG(blueUtils_EncodeData(&result, BLUESPRESULT_FIELDS, pResultBuffer, resultBufferSize), "Encode SP result buffer");

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t handleSendRequest_Defer(const char *const pDeviceId, const BlueSPConnection_t *const pConnection, const BlueSPToken_t *const pToken, BlueSPResult_t *const pResult, int16_t *const pStatusCode, BlueSPTransponderFinishedCallbackFunc_t callback)
{
    DEFER_SESSION_BODY(handleSendRequest(pDeviceId, pConnection, pToken, pResult, pStatusCode, callback));
}

static BlueReturnCode_t handleSendRequest(const char *const pDeviceId, const BlueSPConnection_t *const pConnection, const BlueSPToken_t *const pToken, BlueSPResult_t *const pResult, int16_t *const pStatusCode, BlueSPTransponderFinishedCallbackFunc_t callback)
{
    //
    // Reset session first to leave any previous status
    //

    BLUE_ERROR_CHECK_DEBUG(resetSession(), "Reset session");

    //
    // Assign our data for sending later in the process
    //

    sessionContext.pToken = pToken;
    sessionContext.pResult = pResult;
    sessionContext.pStatusCode = pStatusCode;
    sessionContext.callback = callback;

    *pStatusCode = BlueReturnCode_Pending;

    //
    // Get public key for terminal and fail if not valid
    //

    uint8_t terminalPublicKey[128];
    uint16_t terminalPublicKeySize = sizeof(terminalPublicKey);

    BLUE_ERROR_CHECK_DEBUG(transponderContext.handler.pFuncs->getTerminalPublicKey(transponderContext.handler.pContext, pDeviceId, terminalPublicKey, &terminalPublicKeySize), "Get terminal public key");

    WC_ERROR_CHECK_LOG(wc_ecc_init(&sessionContext.terminalPublicKey), "Init terminal public key");

    sessionContext.hasTerminalPublicKey = true;
    word32 key_dummy_index = 0;

    WC_ERROR_CHECK_LOG(wc_EccPublicKeyDecode(terminalPublicKey, &key_dummy_index, &sessionContext.terminalPublicKey, terminalPublicKeySize), "Decode terminal public key");

    //
    // Setup cypher to be used for the session
    //

    WC_ERROR_CHECK_LOG(wc_ecc_ctx_set_algo(transponderContext.encContext, ecAES_128_CBC, ecHKDF_SHA256, ecHMAC_SHA256), "Set enc context cipher algo");

    //
    // Create a transponder key for the session
    //
    WC_ERROR_CHECK_LOG(wc_ecc_init(&sessionContext.transponderKey), "Init transponder key");

    sessionContext.hasTransponderKey = true;

    WC_ERROR_CHECK_LOG(wc_ecc_make_key_ex(pRNG, DEFAULT_ECC_KEY_CURVE_SIZE, &sessionContext.transponderKey, DEFAULT_ECC_KEY_CURVE), "Create transponder key");

    //
    // Create and assign a transponder salt for this session
    //

    const byte *transponderSalt = wc_ecc_ctx_get_own_salt(transponderContext.encContext);
    if (transponderSalt == NULL)
    {
        BLUE_LOG_ERROR("Failed to get salt for transponder");
        return BlueReturnCode_CryptLibraryFailed;
    }

    memcpy(sessionContext.transponderSalt, transponderSalt, sizeof(sessionContext.transponderSalt));

    //
    // Prepare and send our handshake now to the terminal
    //

    BlueSPHandshake_t handshake = BLUESPHANDSHAKE_INIT_ZERO;
    memcpy(handshake.transponderSalt, sessionContext.transponderSalt, sizeof(sessionContext.transponderSalt));

    int encodedDataSize = blueUtils_EncodeData(&handshake, BLUESPHANDSHAKE_FIELDS, sessionContext.transmitData, sizeof(sessionContext.transmitData));
    if (encodedDataSize < 0)
    {
        BLUE_ERROR_CHECK_DEBUG(encodedDataSize, "Serialize handshake data");
    }

    sessionContext.transmitDataSize = encodedDataSize;

    BLUE_ERROR_CHECK_DEBUG(blueSP_Transmit(pConnection, BlueReturnCode_Ok, sessionContext.transmitData, sessionContext.transmitDataSize), "Transmit handshake data");

    //
    // Await handshake reply from terminal now
    //

    sessionContext.status = SPTransponderSessionStatus_WaitForHandshakeReply;

    BlueReturnCode_t receiveReturnCode = blueSP_Receive(pConnection, sessionContext.receiveData, sizeof(sessionContext.receiveData), &sessionContext.receiveDataSize, sessionContext.pStatusCode, handleReceiveHandshakeReply_Defer);

    switch (receiveReturnCode)
    {
    case BlueReturnCode_Pending:
        BLUE_LOG_DEBUG("Wait for pending handshake reply");
        return receiveReturnCode;
    case BlueReturnCode_Ok:
        return handleReceiveHandshakeReply_Defer(pConnection);
    default:
        BLUE_LOG_DEBUG("Handshake reply receive failed with %d", receiveReturnCode);
        return receiveReturnCode;
    }
}

static BlueReturnCode_t handleReceiveHandshakeReply_Defer(const BlueSPConnection_t *const pConnection)
{
    DEFER_SESSION_BODY(handleReceiveHandshakeReply(pConnection));
}

static BlueReturnCode_t handleReceiveHandshakeReply(const BlueSPConnection_t *const pConnection)
{
    if (sessionContext.status != SPTransponderSessionStatus_WaitForHandshakeReply)
    {
        BLUE_LOG_DEBUG("Invalid session status %d for receiving handshake reply");
        return BlueReturnCode_InvalidState;
    }

    if (*sessionContext.pStatusCode != BlueReturnCode_Ok)
    {
        BLUE_LOG_DEBUG("Received error status code %d", *sessionContext.pStatusCode);
        return BlueReturnCode_SPErrorStatusCode;
    }

    BLUE_LOG_DEBUG("Received handshake reply");

    BlueSPHandshakeReply_t handshakeReply = BLUESPHANDSHAKEREPLY_INIT_ZERO;

    BLUE_ERROR_CHECK_DEBUG(blueUtils_DecodeData(&handshakeReply, BLUESPHANDSHAKEREPLY_FIELDS, sessionContext.receiveData, sessionContext.receiveDataSize), "Decode handshake reply");

    //
    // Validate terminal's signature first which is our signed transponder salt
    //

    BlueReturnCode_t returnCode = blueUtils_VerifySignature(sessionContext.transponderSalt, sizeof(sessionContext.transponderSalt), handshakeReply.terminalSignature.bytes, handshakeReply.terminalSignature.size, &sessionContext.terminalPublicKey);
    if (returnCode != BlueReturnCode_Ok)
    {
        BLUE_LOG_DEBUG("Verifying terminal signature failed with %d", returnCode);
        return BlueReturnCode_InvalidSignature;
    }

    //
    // Verify validity of provided terminal salt
    //

    if (blueUtils_UniqueByteCount(handshakeReply.terminalSalt, sizeof(handshakeReply.terminalSalt)) < EXCHANGE_SALT_SZ / 2)
    {
        BLUE_LOG_DEBUG("Terminal salt does not include enough unique bytes");
        return BlueReturnCode_SPInvalidSalt;
    }

    //
    // Assign the terminal's salt to our context
    //

    WC_ERROR_CHECK_LOG(wc_ecc_ctx_set_peer_salt(transponderContext.encContext, handshakeReply.terminalSalt), "Set terminal salt");

    //
    // At this point we have established a secured connection with the terminal. Due the salt
    // its not possible to replay the session either. All further data sent will need to be
    // sent as aes-encrpted data using the exchanged keys and salt.
    //

    BLUE_LOG_DEBUG("Secure connection established, sending command now.");

    //
    // Encode our token, then encrypt and transmit it
    //

    uint8_t dataBuffer[sizeof(sessionContext.transmitData)];
    int encodedDataSize = blueUtils_EncodeData(sessionContext.pToken, BLUESPTOKEN_FIELDS, dataBuffer, sizeof(dataBuffer));
    if (encodedDataSize < 0)
    {
        BLUE_ERROR_CHECK_DEBUG(encodedDataSize, "Serialize command");
    }
    sessionContext.transmitDataSize = sizeof(sessionContext.transmitData);

    BLUE_ERROR_CHECK(encryptData(dataBuffer, encodedDataSize, sizeof(dataBuffer), sessionContext.transmitData, &sessionContext.transmitDataSize));

    BLUE_ERROR_CHECK_DEBUG(blueSP_Transmit(pConnection, BlueReturnCode_Ok, sessionContext.transmitData, sessionContext.transmitDataSize), "Transmit data");

    //
    // Await for our result
    //

    sessionContext.status = SPTransponderSessionStatus_WaitForResult;

    BlueReturnCode_t receiveReturnCode = blueSP_Receive(pConnection, sessionContext.receiveData, sizeof(sessionContext.receiveData), &sessionContext.receiveDataSize, sessionContext.pStatusCode, handleReceiveResult_Defer);

    switch (receiveReturnCode)
    {
    case BlueReturnCode_Pending:
        BLUE_LOG_DEBUG("Wait for pending result");
        return receiveReturnCode;
    case BlueReturnCode_Ok:
        return handleReceiveResult_Defer(pConnection);
    default:
        BLUE_LOG_DEBUG("Result receive failed with %d", receiveReturnCode);
        return receiveReturnCode;
    }
}

static BlueReturnCode_t handleReceiveResult_Defer(const BlueSPConnection_t *const pConnection)
{
    DEFER_SESSION_BODY(handleReceiveResult(pConnection));
}

static BlueReturnCode_t handleReceiveResult(const BlueSPConnection_t *const pConnection)
{
    if (sessionContext.status != SPTransponderSessionStatus_WaitForResult)
    {
        BLUE_LOG_DEBUG("Invalid session status %d for receiving result");
        return BlueReturnCode_InvalidState;
    }

    if (*sessionContext.pStatusCode != BlueReturnCode_Ok)
    {
        BLUE_LOG_DEBUG("Received error status code %d", *sessionContext.pStatusCode);
        return BlueReturnCode_SPErrorStatusCode;
    }

    //
    // Decrypt and decode result
    //

    uint8_t dataBuffer[sizeof(sessionContext.receiveData)];
    uint16_t dataSize = sizeof(dataBuffer);

    BLUE_ERROR_CHECK(decryptData(sessionContext.receiveData, sessionContext.receiveDataSize, dataBuffer, &dataSize));

    memset(sessionContext.pResult, 0, sizeof(BlueSPResult_t));

    BLUE_ERROR_CHECK(blueUtils_DecodeData(sessionContext.pResult, BLUESPRESULT_FIELDS, dataBuffer, dataSize));

    // We are finally done here
    if (sessionContext.callback)
    {
        sessionContext.callback(BlueReturnCode_Ok);
    }

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t resetSession(void)
{
    if (sessionContext.hasTransponderKey)
    {
        WC_ERROR_CHECK_LOG(wc_ecc_free(&sessionContext.transponderKey), "Release session transponder key");
    }

    if (sessionContext.hasTerminalPublicKey)
    {
        WC_ERROR_CHECK_LOG(wc_ecc_free(&sessionContext.terminalPublicKey), "Release session terminal key");
    }

    if (transponderContext.encContext != NULL)
    {
        WC_ERROR_CHECK_LOG(wc_ecc_ctx_reset(transponderContext.encContext, pRNG), "Reset ecc enc context");
    }

    memset(&sessionContext, 0, sizeof(sessionContext));

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t encryptData(uint8_t *pData, uint16_t dataSize, uint16_t maxDataSize, uint8_t *pBuffer, uint16_t *pBufferSize)
{

    if (dataSize == 0)
    {
        return BlueReturnCode_InvalidArguments;
    }

    // We use AES which require 16bytes blocks so pad our pData pBuffer here if required.
    uint32_t finalDataSize = dataSize;
    BLUE_ERROR_CHECK_DEBUG(blueUtils_Pad(pData, &finalDataSize, 16, maxDataSize), "Pad data for encryption");

    // Encrypt our pBuffer now with the current client context
    word32 outLength = *pBufferSize;

    WC_ERROR_CHECK_LOG(wc_ecc_encrypt(&sessionContext.transponderKey, &sessionContext.terminalPublicKey, pData, finalDataSize, pBuffer, &outLength, transponderContext.encContext), "Encrypt data");

    *pBufferSize = outLength;

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t decryptData(const uint8_t *pData, uint16_t dataSize, uint8_t *pBuffer, uint16_t *pBufferSize)
{
    if (dataSize == 0)
    {
        return BlueReturnCode_InvalidArguments;
    }

    word32 newBufferSize = *pBufferSize;

    WC_ERROR_CHECK_LOG(wc_ecc_decrypt(&sessionContext.transponderKey, NULL, pData, dataSize, pBuffer, &newBufferSize, transponderContext.encContext), "Decrypt data");

    *pBufferSize = newBufferSize;

    return BlueReturnCode_Ok;
}

#ifdef BLUE_TEST
void blueSPTransponder_GetSessionSalt(uint8_t *const pTransponderSalt)
{
    memcpy(pTransponderSalt, sessionContext.transponderSalt, sizeof(sessionContext.transponderSalt));
}
#endif
