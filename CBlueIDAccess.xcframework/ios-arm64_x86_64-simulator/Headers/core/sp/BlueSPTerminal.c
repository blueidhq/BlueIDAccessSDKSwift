#include "core/BlueUtils.h"
#include "core/BlueLog.h"

#include "core/sp/BlueSPTerminal.h"

#include "wolfssl/wolfcrypt/asn.h"
#include "wolfssl/wolfcrypt/ecc.h"

typedef struct SPTerminalContext
{
    BlueSPTerminalHandler_t handler;
    ecc_key terminalPrivateKey;
    ecc_key signaturePublicKey;
    ecEncCtx *encContext;
} SPTerminalContext_t;

typedef enum SPTerminalSessionStatus
{
    SPTerminalStatusSession_Idle = 0,
    SPTerminalStatusSession_WaitForHandshake,
    SPTerminalStatusSession_WaitForData,
    SPTerminalStatusSession_SentResult,
} SPTerminalSessionStatus_t;

typedef struct SPTerminalSessionContext
{
    SPTerminalSessionStatus_t status;
    bool restartAwaitOnEnding;
    ecc_key transponderPublicKey;
    bool hasTransponderPublicKey;
    uint8_t transmitData[2048];
    uint16_t transmitDataSize;
    uint8_t receiveData[2048];
    uint16_t receiveDataSize;
    int16_t receiveStatusCode;
    uint8_t terminalSalt[EXCHANGE_SALT_SZ];
} SPTerminalSessionContext_t;

static bool terminalInitialized = false;
static SPTerminalContext_t terminalContext;
static SPTerminalSessionContext_t sessionContext;

static BlueReturnCode_t awaitRequest_Defer(const BlueSPConnection_t *const pConnection, bool restartAwaitOnEnding);
static BlueReturnCode_t awaitRequest(const BlueSPConnection_t *const pConnection, bool restartAwaitOnEnding);
static BlueReturnCode_t handleReceiveHandshake_Defer(const BlueSPConnection_t *const pConnection);
static BlueReturnCode_t handleReceiveHandshake(const BlueSPConnection_t *const pConnection);
static BlueReturnCode_t handleReceiveData_Defer(const BlueSPConnection_t *const pConnection);
static BlueReturnCode_t handleReceiveData(const BlueSPConnection_t *const pConnection);

static BlueReturnCode_t handleCommand(const BlueLocalTimestamp_t *const pTimestamp, const BlueSPTokenCommand_t *const pCommand, const uint8_t *const pSignature, uint16_t signatureLen, BlueSPResult_t *const pResult);
static BlueReturnCode_t handleOssSo(const BlueLocalTimestamp_t *const pTimestamp, const BlueOssSoMobile_t *const pOssSo, const uint8_t *const pSignature, uint16_t signatureLen, BlueSPResult_t *const pResult);
static BlueReturnCode_t handleOssSid(const BlueLocalTimestamp_t *const pTimestamp, const BlueOssSidMobile_t *const pOssSid, const uint8_t *const pSignature, uint16_t signatureLen, BlueSPResult_t *const pResult);

static BlueReturnCode_t resetSession(void);
static BlueReturnCode_t encryptData(uint8_t *pData, uint16_t dataSize, uint16_t maxDataSize, uint8_t *pBuffer, uint16_t *pBufferSize);
static BlueReturnCode_t decryptData(const uint8_t *pData, uint16_t dataSize, uint8_t *pBuffer, uint16_t *pBufferSize);

#define DEFER_SESSION_BODY(CONNECTION, EXPRESSION)                                        \
    const BlueReturnCode_t returnCode = EXPRESSION;                                       \
    if (returnCode < 0)                                                                   \
    {                                                                                     \
        if (sessionContext.restartAwaitOnEnding)                                          \
        {                                                                                 \
            blueSPTerminal_AwaitRequest(CONNECTION, sessionContext.restartAwaitOnEnding); \
        }                                                                                 \
        else                                                                              \
        {                                                                                 \
            resetSession();                                                               \
        }                                                                                 \
    }                                                                                     \
    return returnCode;

#define TRANSMIT_RETURN_ERROR(CONNECTION, STATUSCODE)                                                   \
    {                                                                                                   \
        BLUE_ERROR_LOG_DEBUG(blueSP_Transmit(CONNECTION, STATUSCODE, NULL, 0), "Transmit status code"); \
        return STATUSCODE;                                                                              \
    }

BlueReturnCode_t blueSPTerminal_Init(const BlueSPTerminalConfiguration_t *const pConfiguration)
{
    if (terminalInitialized)
    {
        return BlueReturnCode_InvalidState;
    }

    if (pConfiguration->pHandler == NULL)
    {
        BLUE_LOG_DEBUG("Missing transponder handler");
        return BlueReturnCode_InvalidArguments;
    }

    memset(&terminalContext, 0, sizeof(terminalContext));
    memset(&sessionContext, 0, sizeof(sessionContext));

    // Assign the terminal handler
    memcpy(&terminalContext.handler, pConfiguration->pHandler, sizeof(BlueSPTerminalHandler_t));

    //
    // Load private and public signature keys
    //

    WC_ERROR_CHECK_LOG(wc_ecc_init(&terminalContext.terminalPrivateKey), "Init terminal private key");
    word32 key_dummy_index = 0;
    WC_ERROR_CHECK_LOG(wc_EccPrivateKeyDecode(pConfiguration->pTerminalPrivateKey, &key_dummy_index, &terminalContext.terminalPrivateKey, pConfiguration->terminalPrivateKeySize), "Decode terminal private key");

    WC_ERROR_CHECK_LOG(wc_ecc_init(&terminalContext.signaturePublicKey), "Init data public key");
    key_dummy_index = 0;
    WC_ERROR_CHECK_LOG(wc_EccPublicKeyDecode(pConfiguration->pSignaturePublicKey, &key_dummy_index, &terminalContext.signaturePublicKey, pConfiguration->signaturePublicKeySize), "Decode data public key");

    //
    // Initialize our ecc enc context in server mode
    //

    terminalContext.encContext = wc_ecc_ctx_new(REQ_RESP_SERVER, pRNG);
    if (terminalContext.encContext == NULL)
    {
        BLUE_LOG_ERROR("Failed to create ecc enc context");
        return BlueReturnCode_InvalidState;
    }

    terminalInitialized = true;

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueSPTerminal_Release(void)
{
    if (!terminalInitialized)
    {
        return BlueReturnCode_InvalidState;
    }

    //
    // Terminal
    //

    WC_ERROR_CHECK_LOG(wc_ecc_free(&terminalContext.signaturePublicKey), "Release data public key");

    WC_ERROR_CHECK_LOG(wc_ecc_free(&terminalContext.terminalPrivateKey), "Release terminal private key");

    wc_ecc_ctx_free(terminalContext.encContext);

    terminalInitialized = false;

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueSPTerminal_AwaitRequest(const BlueSPConnection_t *const pConnection, bool restartAwaitOnEnding)
{
    return awaitRequest_Defer(pConnection, restartAwaitOnEnding);
}

BlueReturnCode_t blueSPTerminal_Clear(void)
{
    BLUE_ERROR_CHECK_DEBUG(resetSession(), "Reset session");
    return BlueReturnCode_Ok;
}

BlueReturnCode_t awaitRequest_Defer(const BlueSPConnection_t *const pConnection, bool restartAwaitOnEnding)
{
    DEFER_SESSION_BODY(pConnection, awaitRequest(pConnection, restartAwaitOnEnding));
}

BlueReturnCode_t awaitRequest(const BlueSPConnection_t *const pConnection, bool restartAwaitOnEnding)
{
    // Reset session first to leave any previous status
    BLUE_ERROR_CHECK_DEBUG(resetSession(), "Reset session");

    // Initialize session key
    WC_ERROR_CHECK_LOG(wc_ecc_init(&sessionContext.transponderPublicKey), "Init session key");
    sessionContext.hasTransponderPublicKey = true;

    //
    // Wait for handshake of transponder
    //

    sessionContext.status = SPTerminalStatusSession_WaitForHandshake;
    sessionContext.restartAwaitOnEnding = restartAwaitOnEnding;

    BlueReturnCode_t receiveReturnCode = blueSP_Receive(pConnection, sessionContext.receiveData, sizeof(sessionContext.receiveData), &sessionContext.receiveDataSize, &sessionContext.receiveStatusCode, handleReceiveHandshake_Defer);

    switch (receiveReturnCode)
    {
    case BlueReturnCode_Pending:
        BLUE_LOG_DEBUG("Wait for pending handshake request");
        return receiveReturnCode;
    case BlueReturnCode_Ok:
        return handleReceiveHandshake_Defer(pConnection);
    default:
        BLUE_LOG_DEBUG("Receive handshake request failed with %d", receiveReturnCode);
        return receiveReturnCode;
    }
}

BlueReturnCode_t handleReceiveHandshake_Defer(const BlueSPConnection_t *const pConnection)
{
    DEFER_SESSION_BODY(pConnection, handleReceiveHandshake(pConnection));
}

static BlueReturnCode_t handleReceiveHandshake(const BlueSPConnection_t *const pConnection)
{
    if (sessionContext.status != SPTerminalStatusSession_WaitForHandshake)
    {
        BLUE_LOG_DEBUG("Invalid session status %d for receiving handshake", sessionContext.status);
        return BlueReturnCode_InvalidState;
    }

    if (sessionContext.receiveStatusCode != BlueReturnCode_Ok)
    {
        BLUE_LOG_DEBUG("Received error status code %d", sessionContext.receiveStatusCode);
        return BlueReturnCode_SPErrorStatusCode;
    }

    BLUE_LOG_DEBUG("Received handshake");

    BlueSPHandshake_t handshake = BLUESPHANDSHAKE_INIT_ZERO;

    BLUE_ERROR_CHECK_DEBUG(blueUtils_DecodeData(&handshake, BLUESPHANDSHAKE_FIELDS, sessionContext.receiveData, sessionContext.receiveDataSize), "Decode handshake");

    BlueSPHandshakeReply_t handshakeReply = BLUESPHANDSHAKEREPLY_INIT_ZERO;

    //
    // Verify validity of provided transponder salt
    //

    if (blueUtils_UniqueByteCount(handshake.transponderSalt, sizeof(handshake.transponderSalt)) < EXCHANGE_SALT_SZ / 2)
    {
        BLUE_LOG_DEBUG("Transponder salt does not include enough unique bytes");
        TRANSMIT_RETURN_ERROR(pConnection, BlueReturnCode_SPInvalidSalt);
    }

    //
    // Create terminal signature for transpondern salt into the reply
    //

    BlueReturnCode_t returnCode = blueUtils_CreateSignature(handshake.transponderSalt, sizeof(handshake.transponderSalt), handshakeReply.terminalSignature.bytes,
                                                            sizeof(handshakeReply.terminalSignature.bytes), &handshakeReply.terminalSignature.size, &terminalContext.terminalPrivateKey);
    if (returnCode != BlueReturnCode_Ok)
    {
        TRANSMIT_RETURN_ERROR(pConnection, BlueReturnCode_SPFailedSigning);
    }

    //
    // Get our terminal salt
    //

    const byte *serverSaltBytes = wc_ecc_ctx_get_own_salt(terminalContext.encContext);
    if (serverSaltBytes == NULL)
    {
        BLUE_LOG_DEBUG("Failed to get terminal salt");
        TRANSMIT_RETURN_ERROR(pConnection, BlueReturnCode_SPFailedGetOwnSalt);
    }

    memcpy(sessionContext.terminalSalt, serverSaltBytes, sizeof(sessionContext.terminalSalt));
    memcpy(handshakeReply.terminalSalt, sessionContext.terminalSalt, sizeof(handshakeReply.terminalSalt));

    //
    // Set transponder salt
    //

    int ret = wc_ecc_ctx_set_peer_salt(terminalContext.encContext, handshake.transponderSalt);
    if (ret != 0)
    {
        BLUE_LOG_DEBUG("Failed to set transponder salt with %d", ret);
        TRANSMIT_RETURN_ERROR(pConnection, BlueReturnCode_SPFailedSetPeerSalt);
    }

    //
    // Send our handshake reply back now
    //

    int encodedDataSize = blueUtils_EncodeData(&handshakeReply, BLUESPHANDSHAKEREPLY_FIELDS, sessionContext.transmitData, sizeof(sessionContext.transmitData));
    if (encodedDataSize < 0)
    {
        TRANSMIT_RETURN_ERROR(pConnection, encodedDataSize);
        return encodedDataSize;
    }

    sessionContext.transmitDataSize = encodedDataSize;

    BLUE_ERROR_CHECK_DEBUG(blueSP_Transmit(pConnection, BlueReturnCode_Ok, sessionContext.transmitData, sessionContext.transmitDataSize), "Transmit handshake reply");

    //
    // Await data from transponder now
    //

    sessionContext.status = SPTerminalStatusSession_WaitForData;

    BlueReturnCode_t receiveReturnCode = blueSP_Receive(pConnection, sessionContext.receiveData, sizeof(sessionContext.receiveData), &sessionContext.receiveDataSize, &sessionContext.receiveStatusCode, handleReceiveData_Defer);

    switch (receiveReturnCode)
    {
    //
    // At this point we have established a secured connection with the transponder. Due the salt
    // its not possible to replay the session either. All further data sent will need to be
    // sent as aes-encrpted data using the exchanged keys and salt.
    //
    case BlueReturnCode_Pending:
        BLUE_LOG_DEBUG("Secure connection established, waiting for data");
        return receiveReturnCode;
    case BlueReturnCode_Ok:
        BLUE_LOG_DEBUG("Secure connection established");
        return handleReceiveData_Defer(pConnection);
    default:
        BLUE_LOG_DEBUG("Data receive request failed with %d", receiveReturnCode);
        return receiveReturnCode;
    }
}

BlueReturnCode_t handleReceiveData_Defer(const BlueSPConnection_t *const pConnection)
{
    DEFER_SESSION_BODY(pConnection, handleReceiveData(pConnection));
}

static BlueReturnCode_t handleReceiveData(const BlueSPConnection_t *const pConnection)
{
    if (sessionContext.status != SPTerminalStatusSession_WaitForData)
    {
        BLUE_LOG_DEBUG("Invalid session status %d for receiving data");
        return BlueReturnCode_InvalidState;
    }

    if (sessionContext.receiveStatusCode != BlueReturnCode_Ok)
    {
        BLUE_LOG_DEBUG("Received error status code %d", sessionContext.receiveStatusCode);
        return BlueReturnCode_SPErrorStatusCode;
    }

    BLUE_LOG_DEBUG("Received data");

    uint8_t buffer[sizeof(sessionContext.receiveData)];

    //
    // Decrypt and decode token
    //

    uint16_t dataSize = sizeof(buffer);
    BlueReturnCode_t returnCode = decryptData(sessionContext.receiveData, sessionContext.receiveDataSize, buffer, &dataSize);
    if (returnCode != BlueReturnCode_Ok)
    {
        TRANSMIT_RETURN_ERROR(pConnection, BlueReturnCode_SPFailedDecrypt);
    }

    BlueSPToken_t token = BLUESPTOKEN_INIT_ZERO;
    returnCode = blueUtils_DecodeData(&token, BLUESPTOKEN_FIELDS, buffer, dataSize);
    if (returnCode != BlueReturnCode_Ok)
    {
        TRANSMIT_RETURN_ERROR(pConnection, returnCode);
    }

    //
    // Get current time
    //

    BlueLocalTimestamp_t currentTime;
    returnCode = terminalContext.handler.pFuncs->getCurrentTime(terminalContext.handler.pContext, &currentTime);
    if (returnCode != BlueReturnCode_Ok)
    {
        return BlueReturnCode_SPFailedGetCurrentTime;
    }

    //
    // Execute proper handler now
    //

    returnCode = BlueReturnCode_InvalidArguments;

    BlueSPResult_t result = BLUESPRESULT_INIT_ZERO;

    switch (token.which_payload)
    {
    case BLUESPTOKEN_COMMAND_TAG:
        returnCode = handleCommand(&currentTime, &token.payload.command, token.signature.bytes, token.signature.size, &result);
        break;
    case BLUESPTOKEN_OSSSO_TAG:
        returnCode = handleOssSo(&currentTime, &token.payload.ossSo, token.signature.bytes, token.signature.size, &result);
        break;
    case BLUESPTOKEN_OSSSID_TAG:
        returnCode = handleOssSid(&currentTime, &token.payload.ossSid, token.signature.bytes, token.signature.size, &result);
        break;
    default:
        returnCode = BlueReturnCode_NotSupported;
        break;
    }

    if (returnCode != BlueReturnCode_Ok)
    {
        TRANSMIT_RETURN_ERROR(pConnection, returnCode);
    }

    //
    // Encode the result, encrypt it and transmit it
    //

    int encodedDataSize = blueUtils_EncodeData(&result, BLUESPRESULT_FIELDS, buffer, sizeof(buffer));
    if (encodedDataSize < 0)
    {
        TRANSMIT_RETURN_ERROR(pConnection, encodedDataSize);
    }

    sessionContext.transmitDataSize = sizeof(sessionContext.transmitData);

    BLUE_ERROR_CHECK(encryptData(buffer, encodedDataSize, sizeof(buffer), sessionContext.transmitData, &sessionContext.transmitDataSize));

    BLUE_ERROR_CHECK_DEBUG(blueSP_Transmit(pConnection, BlueReturnCode_Ok, sessionContext.transmitData, sessionContext.transmitDataSize), "Transmit result");

    //
    // We're finally done here
    //

    sessionContext.status = SPTerminalStatusSession_SentResult;

    //
    // If we shall restart awaiting then handle it now
    //

    if (sessionContext.restartAwaitOnEnding)
    {
        return blueSPTerminal_AwaitRequest(pConnection, sessionContext.restartAwaitOnEnding);
    }

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t createCommandSignatureMessage(const BlueSPTokenCommand_t *const pCommand, const char *const pCommandGroup, uint8_t *const pMessage, int *const pMessageLength)
{
    *pMessageLength = snprintf((char *const)pMessage, *pMessageLength, "%.10s:%.8s:%d%d%d%d%d:%d%d%d%d%d", pCommand->credentialId.id, pCommandGroup != NULL ? pCommandGroup : pCommand->command,
                               (int)pCommand->validityStart.year, (int)pCommand->validityStart.month, (int)pCommand->validityStart.date, (int)pCommand->validityStart.hours, (int)pCommand->validityStart.minutes,
                               (int)pCommand->validityEnd.year, (int)pCommand->validityEnd.month, (int)pCommand->validityEnd.date, (int)pCommand->validityEnd.hours, (int)pCommand->validityEnd.minutes);

    if (*pMessageLength <= 0 || (unsigned int)*pMessageLength >= 64)
    {
        return BlueReturnCode_SPFailedSignature;
    }

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t handleCommand(const BlueLocalTimestamp_t *const pTimestamp, const BlueSPTokenCommand_t *const pCommand, const uint8_t *const pSignature, uint16_t signatureLen, BlueSPResult_t *const pResult)
{
#define STORE_COMMAND_EVENT(EVENT_INFO)                                                          \
    {                                                                                            \
        BlueEvent_t event = BLUEEVENT_INIT_ZERO;                                                 \
        event.eventTime = *pTimestamp;                                                           \
        event.eventId = BlueEventId_TerminalCommand;                                             \
        event.eventInfo = EVENT_INFO;                                                            \
        event.has_credentialId = true;                                                           \
        event.has_command = true;                                                                \
        memcpy(event.credentialId.id, pCommand->credentialId.id, sizeof(event.credentialId.id)); \
        memcpy(event.command, pCommand->command, sizeof(pCommand->command));                     \
                                                                                                 \
        terminalContext.handler.pFuncs->storeEvent(terminalContext.handler.pContext, &event);    \
    }

    //
    // Check Signature of command, first
    //

    uint8_t signatureMessage[64];
    int signatureMessageLength = sizeof(signatureMessage);

    BLUE_ERROR_CHECK(createCommandSignatureMessage(pCommand, NULL, signatureMessage, &signatureMessageLength));

    BlueReturnCode_t returnCode = blueUtils_VerifySignature(signatureMessage, signatureMessageLength, pSignature, signatureLen, &terminalContext.signaturePublicKey);
    if (returnCode != BlueReturnCode_Ok)
    {
        // If verification of signature has failed it might be a signature for a command group so try to gather a command
        // group if any and try to verify the signature again with the group, otherwise fail.
        char commandGroup[10];

        if (terminalContext.handler.pFuncs->getCommandGroup(terminalContext.handler.pContext, pCommand->command, commandGroup) == BlueReturnCode_Ok)
        {
            signatureMessageLength = sizeof(signatureMessage);
            BLUE_ERROR_CHECK(createCommandSignatureMessage(pCommand, commandGroup, signatureMessage, &signatureMessageLength));
            returnCode = blueUtils_VerifySignature(signatureMessage, signatureMessageLength, pSignature, signatureLen, &terminalContext.signaturePublicKey);
        }

        if (returnCode != BlueReturnCode_Ok)
        {
            BLUE_LOG_DEBUG("Invalid signature for command %s", signatureMessage);
            STORE_COMMAND_EVENT(BlueReturnCode_InvalidSignature);
            return returnCode;
        }
    }

    //
    // Check validity dates of commmand
    //

    if (blueUtils_TimestampCompare(&pCommand->validityStart, pTimestamp) > 0 || blueUtils_TimestampCompare(&pCommand->validityEnd, pTimestamp) < 0)
    {
        BLUE_LOG_DEBUG("Command is out of validity");
        STORE_COMMAND_EVENT(BlueReturnCode_InvalidValidity);
        return BlueReturnCode_InvalidValidity;
    }

    //
    // Let our command handler handle it now and get our result
    //

    BLUE_LOG_DEBUG("Handle terminal command %.8s with command data size %d", pCommand->command, pCommand->data.size);

    returnCode = terminalContext.handler.pFuncs->handleCommand(terminalContext.handler.pContext, pCommand, pResult);

    STORE_COMMAND_EVENT(returnCode);

    return returnCode;
}

static BlueReturnCode_t handleOssSo(const BlueLocalTimestamp_t *const pTimestamp, const BlueOssSoMobile_t *const pOssSo, const uint8_t *const pSignature, uint16_t signatureLen, BlueSPResult_t *const pResult)
{
#define STORE_OSSSO_EVENT(EVENT_INFO)                                                         \
    {                                                                                         \
        BlueEvent_t event = BLUEEVENT_INIT_ZERO;                                              \
        event.eventTime = *pTimestamp;                                                        \
        event.eventId = BlueEventId_TerminalOss;                                              \
        event.eventInfo = EVENT_INFO;                                                         \
                                                                                              \
        terminalContext.handler.pFuncs->storeEvent(terminalContext.handler.pContext, &event); \
    }

    //
    // Check Signature of oss so data, first
    //

    const uint16_t bufferMaxSize = sizeof(pOssSo->infoFile.bytes) + sizeof(pOssSo->dataFile.bytes) + sizeof(pOssSo->blacklistFile.bytes);
    uint8_t buffer[bufferMaxSize];
    uint16_t bufferSize = 0;

    memcpy(&buffer[bufferSize], pOssSo->infoFile.bytes, pOssSo->infoFile.size);
    bufferSize += pOssSo->infoFile.size;

    memcpy(&buffer[bufferSize], pOssSo->dataFile.bytes, pOssSo->dataFile.size);
    bufferSize += pOssSo->dataFile.size;

    memcpy(&buffer[bufferSize], pOssSo->blacklistFile.bytes, pOssSo->blacklistFile.size);
    bufferSize += pOssSo->blacklistFile.size;

    BlueReturnCode_t returnCode = blueUtils_VerifySignature(buffer, bufferSize, pSignature, signatureLen, &terminalContext.signaturePublicKey);
    if (returnCode != BlueReturnCode_Ok)
    {
        BLUE_LOG_DEBUG("Invalid signature for OssSo mobile data");
        STORE_OSSSO_EVENT(BlueReturnCode_InvalidSignature);
        return returnCode;
    }

    BLUE_LOG_DEBUG("Handle OssSo mobile with infoFileSize=%d, dataFileSize=%d, blacklistFileSize=%d, customerExtensionsFileSize=%d", pOssSo->infoFile.size, pOssSo->dataFile.size, pOssSo->blacklistFile.size, pOssSo->customerExtensionsFile.size);

    returnCode = terminalContext.handler.pFuncs->handleOssSo(terminalContext.handler.pContext, pTimestamp, pOssSo, pResult);

    if (returnCode != BlueReturnCode_Ok)
    {
        STORE_OSSSO_EVENT(returnCode);
    }

    return returnCode;
}

static BlueReturnCode_t handleOssSid(const BlueLocalTimestamp_t *const pTimestamp, const BlueOssSidMobile_t *const pOssSid, const uint8_t *const pSignature, uint16_t signatureLen, BlueSPResult_t *const pResult)
{
#define STORE_OSSSID_EVENT(EVENT_INFO)                                                        \
    {                                                                                         \
        BlueEvent_t event = BLUEEVENT_INIT_ZERO;                                              \
        event.eventTime = *pTimestamp;                                                        \
        event.eventId = BlueEventId_TerminalOss;                                              \
        event.eventInfo = EVENT_INFO;                                                         \
                                                                                              \
        terminalContext.handler.pFuncs->storeEvent(terminalContext.handler.pContext, &event); \
    }

    //
    // Check Signature of oss sid data, first
    //

    BlueReturnCode_t returnCode = blueUtils_VerifySignature(pOssSid->infoFile.bytes, pOssSid->infoFile.size, pSignature, signatureLen, &terminalContext.signaturePublicKey);
    if (returnCode != BlueReturnCode_Ok)
    {
        BLUE_LOG_DEBUG("Invalid signature for OssSid mobile data");
        STORE_OSSSO_EVENT(BlueReturnCode_InvalidSignature);
        return returnCode;
    }

    BLUE_LOG_DEBUG("Handle OssSid mobile with infoFileSize=%d", pOssSid->infoFile.size);

    returnCode = terminalContext.handler.pFuncs->handleOssSid(terminalContext.handler.pContext, pTimestamp, pOssSid, pResult);

    if (returnCode != BlueReturnCode_Ok)
    {
        STORE_OSSSID_EVENT(returnCode);
    }

    return returnCode;
}

static BlueReturnCode_t resetSession(void)
{
    if (sessionContext.hasTransponderPublicKey)
    {
        WC_ERROR_CHECK_LOG(wc_ecc_free(&sessionContext.transponderPublicKey), "Release session transponder key");
    }

    if (terminalContext.encContext != NULL)
    {
        WC_ERROR_CHECK_LOG(wc_ecc_ctx_reset(terminalContext.encContext, pRNG), "Reset ecc enc context");
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

    WC_ERROR_CHECK_LOG(wc_ecc_encrypt(&terminalContext.terminalPrivateKey, &sessionContext.transponderPublicKey, pData, finalDataSize, pBuffer, &outLength, terminalContext.encContext), "Encrypt data");

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

    WC_ERROR_CHECK_LOG(wc_ecc_decrypt(&terminalContext.terminalPrivateKey, &sessionContext.transponderPublicKey, pData, dataSize, pBuffer, &newBufferSize, terminalContext.encContext), "Decrypt data");

    *pBufferSize = newBufferSize;

    return BlueReturnCode_Ok;
}

#ifdef BLUE_TEST
void blueSPTerminal_GetSessionSalt(uint8_t *const pTerminalSalt)
{
    memcpy(pTerminalSalt, sessionContext.terminalSalt, sizeof(sessionContext.terminalSalt));
}
#endif
