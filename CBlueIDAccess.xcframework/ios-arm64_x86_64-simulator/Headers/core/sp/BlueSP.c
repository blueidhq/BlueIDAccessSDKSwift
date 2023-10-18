#include "core/BlueUtils.h"
#include "core/BlueLog.h"

#include "core/sp/BlueSP.h"

#define SP_HEADER_SIZE 6 // SIZE | CRC | STATUS

typedef struct SPReceiveContext
{
    uint8_t *pData;
    uint16_t availableDataSize;
    BlueSPDataAvailableFunc_t availableCallback;
    BlueSPReceiveFinishFunc_t finishCallback;
    const BlueSPConnection_t *pConnection;
    // --
    uint8_t pFrameData[512];
    uint16_t frameDataSize;
    uint16_t frameDataTotalSize;
    //--
    uint16_t *pReceivedDataSize;
    int16_t *pStatusCode;
    uint16_t dataCrc;
    uint16_t dataSize;
} SPReceiveContext_t;

static SPReceiveContext_t receiveContext;

#ifdef BLUE_TEST
// -- Ugly but required for testing sp bi-directional communication
static SPReceiveContext_t temporaryReceiveContext;
#endif

static BlueReturnCode_t handleReceiveFrameData(void);
static BlueReturnCode_t handleReceiveFinish(void);

BlueReturnCode_t blueSP_Transmit(const BlueSPConnection_t *const pConnection, int16_t statusCode, const uint8_t *const pData, uint16_t dataSize)
{
    const uint16_t frameSize = pConnection->pFuncs->getMaxFrameSize(pConnection->pContext);

    if (frameSize < SP_HEADER_SIZE)
    {
        return BlueReturnCode_InvalidState;
    }

    uint8_t frameData[frameSize];

    uint16_t transmittedSize = 0;
    bool hasTransmitted = false;

    while (!hasTransmitted || transmittedSize < dataSize)
    {
        uint16_t frameDataOffset = 0;
        uint16_t availableFrameSize = frameSize;

        // If this is the first frame we'll prepend our header which defines the size of the data and the crc marker
        if (!hasTransmitted)
        {
            frameDataOffset = SP_HEADER_SIZE;
            availableFrameSize -= frameDataOffset;

            BLUE_UINT16_WRITE_BE(&frameData[0], (uint16_t)dataSize);
            BLUE_UINT16_WRITE_BE(&frameData[2], dataSize ? blueUtils_Crc16(0XFFFF, pData, dataSize) : 0);
            BLUE_UINT16_WRITE_BE(&frameData[4], (uint16_t)statusCode);

            hasTransmitted = true;
        }

        const uint16_t transmitSize = BLUE_MIN(availableFrameSize, dataSize - transmittedSize);

        if (transmitSize > 0)
        {
            memcpy(&frameData[frameDataOffset], &pData[transmittedSize], transmitSize);
        }

        // Send our single frame over now
        BLUE_ERROR_CHECK_DEBUG(pConnection->pFuncs->transmit(pConnection->pContext, frameData, transmitSize + frameDataOffset), "Transmit sp data frame");

        // Increase our so-far transmitted data size
        transmittedSize += transmitSize;
        hasTransmitted = true;
    }

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueSP_Receive(const BlueSPConnection_t *const pConnection, uint8_t *const pData, uint16_t availableDataSize, uint16_t *const pReturnedDataSize, int16_t *const pStatusCode, BlueSPDataAvailableFunc_t availableCallback)
{
    *pReturnedDataSize = 0;
    *pStatusCode = 0;

    memset(&receiveContext, 0, sizeof(SPReceiveContext_t));

    receiveContext.pData = pData;
    receiveContext.availableDataSize = availableDataSize;
    receiveContext.pReceivedDataSize = pReturnedDataSize;
    receiveContext.pStatusCode = pStatusCode;
    receiveContext.availableCallback = availableCallback;
    receiveContext.pConnection = pConnection;

    if (pConnection->pFuncs->hasFinishCallback(pConnection->pContext))
    {
        receiveContext.finishCallback = handleReceiveFinish;
    }

    BlueReturnCode_t returnCode = pConnection->pFuncs->receive(pConnection->pContext, receiveContext.pFrameData, sizeof(receiveContext.pFrameData), &receiveContext.frameDataSize, handleReceiveFrameData, receiveContext.finishCallback);

    if (returnCode == BlueReturnCode_Pending)
    {
        // Just return and let our callback do the work
        if (availableCallback == NULL)
        {
            BLUE_LOG_DEBUG("Receive function is async but no callback provided");
            return BlueReturnCode_InvalidState;
        }

        return returnCode;
    }

    if (returnCode != BlueReturnCode_Ok)
    {
        BLUE_ERROR_CHECK_DEBUG(returnCode, "Receive data from connection");
        return returnCode;
    }

    // Reset callback function from context as we don't want it to be called due blocking call
    receiveContext.availableCallback = NULL;

    //
    // Do blocking read here as we have not received pending
    //
    for (;;)
    {
        returnCode = handleReceiveFrameData();

        if (returnCode != BlueReturnCode_Pending)
        {
            return returnCode;
        }
    }

    return returnCode;
}

BlueReturnCode_t blueSP_SignData(BlueSPData_t *const pData, const uint8_t *const pPrivateKeyBuffer, uint16_t privateKeyBufferSize)
{
    if (pData->which_payload == BLUESPDATA_COMMAND_TAG)
    {
        const BlueSPDataCommand_t *const command = &pData->payload.command;

        char commandSignatureTemplate[64];

        int signatureTemplateLen = snprintf(commandSignatureTemplate, sizeof(commandSignatureTemplate), "%.10s:%.8s:%d%d%d%d%d:%d%d%d%d%d", command->credentialId.id, command->command,
                                            (int)command->validityStart.year, (int)command->validityStart.month, (int)command->validityStart.date, (int)command->validityStart.hours, (int)command->validityStart.minutes,
                                            (int)command->validityEnd.year, (int)command->validityEnd.month, (int)command->validityEnd.date, (int)command->validityEnd.hours, (int)command->validityEnd.minutes);

        uint16_t signatureSize = 0;
        BLUE_ERROR_CHECK(blueUtils_CreateSignature_Ext((uint8_t *)commandSignatureTemplate, signatureTemplateLen, pData->signature.bytes, sizeof(pData->signature.bytes), &signatureSize, pPrivateKeyBuffer, privateKeyBufferSize));
        pData->signature.size = signatureSize;

        return BlueReturnCode_Ok;
    }
    else if (pData->which_payload == BLUESPDATA_OSSSO_TAG)
    {
        const BlueOssSoMobile_t *const ossSo = &pData->payload.ossSo;

        const uint16_t bufferMaxSize = sizeof(ossSo->infoFile.bytes) + sizeof(ossSo->dataFile.bytes) + sizeof(ossSo->blacklistFile.bytes);
        uint8_t buffer[bufferMaxSize];
        uint16_t bufferSize = 0;

        memcpy(&buffer[bufferSize], ossSo->infoFile.bytes, ossSo->infoFile.size);
        bufferSize += ossSo->infoFile.size;

        memcpy(&buffer[bufferSize], ossSo->dataFile.bytes, ossSo->dataFile.size);
        bufferSize += ossSo->dataFile.size;

        memcpy(&buffer[bufferSize], ossSo->blacklistFile.bytes, ossSo->blacklistFile.size);
        bufferSize += ossSo->blacklistFile.size;

        uint16_t signatureSize = 0;
        BLUE_ERROR_CHECK(blueUtils_CreateSignature_Ext((uint8_t *)buffer, bufferSize, pData->signature.bytes, sizeof(pData->signature.bytes), &signatureSize, pPrivateKeyBuffer, privateKeyBufferSize));
        pData->signature.size = signatureSize;

        return BlueReturnCode_Ok;
    }
    else if (pData->which_payload == BLUESPDATA_OSSSID_TAG)
    {
        const BlueOssSidMobile_t *const ossSid = &pData->payload.ossSid;

        uint16_t signatureSize = 0;
        BLUE_ERROR_CHECK(blueUtils_CreateSignature_Ext((uint8_t *)ossSid->infoFile.bytes, ossSid->infoFile.size, pData->signature.bytes, sizeof(pData->signature.bytes), &signatureSize, pPrivateKeyBuffer, privateKeyBufferSize));
        pData->signature.size = signatureSize;

        return BlueReturnCode_Ok;
    }

    return BlueReturnCode_NotSupported;
}

BlueReturnCode_t blueSP_SignData_Ext(const uint8_t *const pSpData, uint16_t spDataSize, uint8_t *const pSignedSpData, uint16_t signedSpDataSize, const uint8_t *const pPrivateKeyBuffer, uint16_t privateKeyBufferSize)
{
    BlueSPData_t spData = BLUESPDATA_INIT_ZERO;

    BLUE_ERROR_CHECK_DEBUG(blueUtils_DecodeData((void *)&spData, BLUESPDATA_FIELDS, pSpData, spDataSize), "Decode unsigned sp data");

    BLUE_ERROR_CHECK_DEBUG(blueSP_SignData(&spData, pPrivateKeyBuffer, privateKeyBufferSize), "Sign sp data");

    BLUE_ERROR_CHECK_DEBUG(blueUtils_EncodeData((void *)&spData, BLUESPDATA_FIELDS, pSignedSpData, signedSpDataSize), "Encode signed sp data");

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t handleReceiveFrameData(void)
{
    if (receiveContext.frameDataSize == 0)
    {
        BLUE_LOG_DEBUG("Receive callback called but last received frame data size was zero");
        memset(&receiveContext, 0, sizeof(SPReceiveContext_t));
        return BlueReturnCode_InvalidState;
    }

    // If first call then extract crc and data size from header
    uint16_t frameReadOffset = 0;

    if (receiveContext.frameDataTotalSize == 0)
    {
        frameReadOffset = SP_HEADER_SIZE;

        if (receiveContext.frameDataSize < frameReadOffset)
        {
            return BlueReturnCode_InvalidState;
        }

        receiveContext.dataSize = BLUE_UINT16_READ_BE(&receiveContext.pFrameData[0]);
        receiveContext.dataCrc = BLUE_UINT16_READ_BE(&receiveContext.pFrameData[2]);
        *receiveContext.pStatusCode = (int16_t)BLUE_UINT16_READ_BE(&receiveContext.pFrameData[4]);
    }

    receiveContext.frameDataTotalSize += receiveContext.frameDataSize;

    uint16_t receivedDataSize = *receiveContext.pReceivedDataSize;

    const uint16_t frameReadSize = frameReadOffset < receiveContext.frameDataSize ? receiveContext.frameDataSize - frameReadOffset : 0;
    if (frameReadSize > 0)
    {
        if (receivedDataSize + frameReadSize > receiveContext.availableDataSize)
        {
            memset(&receiveContext, 0, sizeof(SPReceiveContext_t));
            return BlueReturnCode_Overflow;
        }

        memcpy(&receiveContext.pData[receivedDataSize], &receiveContext.pFrameData[frameReadOffset], frameReadSize);

        receivedDataSize += frameReadSize;
        *receiveContext.pReceivedDataSize = receivedDataSize;
    }

    if (receivedDataSize >= receiveContext.dataSize)
    {
        // We're received all data so verify its integrity now and return in case we have any data at all
        if (receiveContext.dataSize > 0 && receiveContext.dataCrc != blueUtils_Crc16(0xFFFF, receiveContext.pData, receivedDataSize))
        {
            memset(&receiveContext, 0, sizeof(SPReceiveContext_t));
            return BlueReturnCode_InvalidCrc;
        }

        // If we have no finish callback then we call finish right here,
        // otherwise our finish handler will be called from outside
        if (!receiveContext.finishCallback)
        {
            return handleReceiveFinish();
        }

        return BlueReturnCode_Ok;
    }

    // We're not done yet so request one more frame
    receiveContext.frameDataSize = 0;

    const BlueSPConnection_t *const pConnection = receiveContext.pConnection;

    const BlueReturnCode_t returnCode = pConnection->pFuncs->receive(pConnection->pContext, receiveContext.pFrameData, sizeof(receiveContext.pFrameData), &receiveContext.frameDataSize, handleReceiveFrameData, receiveContext.finishCallback);

    if (returnCode == BlueReturnCode_Ok)
    {
        // Not pending so call handler ourself
        return handleReceiveFrameData();
    }

    if (returnCode != BlueReturnCode_Pending)
    {
        BLUE_ERROR_CHECK_DEBUG(returnCode, "Receive data from connection");
    }

    return returnCode;
}

static BlueReturnCode_t handleReceiveFinish(void)
{
    //
    // We're done here so call our callback if any and return
    //
    const BlueSPConnection_t *const pConnection = receiveContext.pConnection;
    BlueSPDataAvailableFunc_t availableCallback = receiveContext.availableCallback;

    // Clear first
    memset(&receiveContext, 0, sizeof(SPReceiveContext_t));

    // Call callback if any
    if (availableCallback != NULL)
    {
        return availableCallback(pConnection);
    }

    return BlueReturnCode_Ok;
}

#ifdef BLUE_TEST

void blueSP_SwapTemporaryReceiveContext(void)
{
    SPReceiveContext_t contextCopy;
    memcpy(&contextCopy, &receiveContext, sizeof(SPReceiveContext_t));
    memcpy(&receiveContext, &temporaryReceiveContext, sizeof(SPReceiveContext_t));
    memcpy(&temporaryReceiveContext, &contextCopy, sizeof(SPReceiveContext_t));
}

#endif
