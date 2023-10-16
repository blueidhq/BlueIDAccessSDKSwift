#include "core/oss/BlueOssSoMobile.h"
#include "core/oss/BlueOssSo.h"

#include "core/BlueUtils.h"

typedef struct OssSoMobileStorageContext
{
    const BlueOssSoMobile_t *pOssSoMobile;
    uint8_t *pOutput;
    uint16_t *pOutputSize;
    uint16_t maxOutputSize;
} OssSoMobileStorageContext_t;

static OssSoMobileStorageContext_t ossSoStorageContext =
    {
        .pOssSoMobile = NULL,
        .pOutput = NULL,
};

static BlueReturnCode_t ossSoStorage_getDefaultProvisioningConfiguration(BlueOssSoStorageContext_t *pContext, BlueOssSoProvisioningConfiguration_t *const pProvisioningConfig)
{
    const BlueOssSoProvisioningConfiguration_t defaultConfig = BLUEOSSSOMOBILEPROVISIONINGCONFIGURATION_INIT_DEFAULT;
    memcpy(pProvisioningConfig, &defaultConfig, sizeof(BlueOssSoProvisioningConfiguration_t));
    return BlueReturnCode_Ok;
}

static BlueReturnCode_t ossSoStorage_GetStorageProfile(BlueOssSoStorageContext_t *pContext, const BlueOssSoProvisioningConfiguration_t *const pProvisioningConfig, BlueOssSoStorageProfile_t *const pProfile)
{
    return BlueReturnCode_NotSupported;
}

static BlueReturnCode_t ossSoStorage_Prepare(BlueOssSoStorageContext_t *pContext, BlueOssPrepareMode_t prepareMode)
{
    OssSoMobileStorageContext_t *const context = (OssSoMobileStorageContext_t *)pContext;

    if (!context->pOutput && !context->pOssSoMobile)
    {
        return BlueReturnCode_InvalidState;
    }

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t ossSoStorage_Provision(BlueOssSoStorageContext_t *pContext, const BlueOssSoProvisioningData_t *const pData, BlueOssSoStorageProvisionWriteFunc_t write, const BlueOssSoStorage_t *const pStorage)
{
    return write(pData, pStorage);
}

static BlueReturnCode_t ossSoStorage_Unprovision(BlueOssSoStorageContext_t *pContext)
{
    return BlueReturnCode_NotSupported;
}

static BlueReturnCode_t ossSoStorage_Format(BlueOssSoStorageContext_t *pContext, bool factoryReset)
{
    return BlueReturnCode_NotSupported;
}

static BlueReturnCode_t ossSoStorage_Read(BlueOssSoStorageContext_t *pContext, BlueOssSoFileId_t fileId, uint16_t offset, uint8_t *const pData, uint16_t dataSize)
{
    OssSoMobileStorageContext_t *const context = (OssSoMobileStorageContext_t *)pContext;

    const BlueOssSoMobile_t *pOssSoMobile = NULL;

    BlueOssSoMobile_t ossSoMobile;

    if (context->pOssSoMobile)
    {
        pOssSoMobile = context->pOssSoMobile;
    }
    else
    {
        BLUE_ERROR_CHECK(blueUtils_DecodeData((void *)&ossSoMobile, BLUEOSSSOMOBILE_FIELDS, context->pOutput, *context->pOutputSize));
        pOssSoMobile = &ossSoMobile;
    }

    pb_size_t size = 0;
    const pb_byte_t *bytes = NULL;

    switch (fileId)
    {
    case BlueOssSoFileId_Info:
        size = pOssSoMobile->infoFile.size;
        bytes = &pOssSoMobile->infoFile.bytes[0];
        break;
    case BlueOssSoFileId_Data:
        size = pOssSoMobile->dataFile.size;
        bytes = &pOssSoMobile->dataFile.bytes[0];
        break;
    case BlueOssSoFileId_Blacklist:
        size = pOssSoMobile->blacklistFile.size;
        bytes = &pOssSoMobile->blacklistFile.bytes[0];
        break;
    case BlueOssSoFileId_CustomerExtensions:
        size = pOssSoMobile->customerExtensionsFile.size;
        bytes = &pOssSoMobile->customerExtensionsFile.bytes[0];
        break;
    default:
        break;
    }

    if (bytes == NULL)
    {
        return BlueReturnCode_NotSupported;
    }

    if (offset + dataSize > size)
    {
        return BlueReturnCode_EOF;
    }

    memcpy(pData, &bytes[offset], dataSize);

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t ossSoStorage_Write(BlueOssSoStorageContext_t *pContext, BlueOssSoFileId_t fileId, uint16_t offset, const uint8_t *const pData, uint16_t dataSize)
{
    OssSoMobileStorageContext_t *const context = (OssSoMobileStorageContext_t *)pContext;

    if (!context->pOutput)
    {
        return BlueReturnCode_InvalidState;
    }

    BlueOssSoMobile_t ossSoMobile = BLUEOSSSOMOBILE_INIT_ZERO;

    // -- ignore result as it migth be a fresh instance
    blueUtils_DecodeData((void *)&ossSoMobile, BLUEOSSSOMOBILE_FIELDS, context->pOutput, *context->pOutputSize);

    pb_size_t maxSize = 0;
    pb_size_t *size = NULL;
    pb_byte_t *bytes = NULL;

    switch (fileId)
    {
    case BlueOssSoFileId_Info:
        maxSize = sizeof(ossSoMobile.infoFile.bytes);
        size = &ossSoMobile.infoFile.size;
        bytes = &ossSoMobile.infoFile.bytes[0];
        break;
    case BlueOssSoFileId_Data:
        maxSize = sizeof(ossSoMobile.dataFile.bytes);
        size = &ossSoMobile.dataFile.size;
        bytes = &ossSoMobile.dataFile.bytes[0];
        break;
    case BlueOssSoFileId_Blacklist:
        maxSize = sizeof(ossSoMobile.blacklistFile.bytes);
        size = &ossSoMobile.blacklistFile.size;
        bytes = &ossSoMobile.blacklistFile.bytes[0];
        break;
    case BlueOssSoFileId_CustomerExtensions:
        maxSize = sizeof(ossSoMobile.customerExtensionsFile.bytes);
        size = &ossSoMobile.customerExtensionsFile.size;
        bytes = &ossSoMobile.customerExtensionsFile.bytes[0];
        break;
    default:
        break;
    }

    if (bytes == NULL || size == NULL)
    {
        return BlueReturnCode_NotSupported;
    }

    if (offset + dataSize > maxSize)
    {
        return BlueReturnCode_Overflow;
    }

    memcpy(&bytes[offset], pData, dataSize);
    *size = dataSize;

    int newOutputSize = blueUtils_EncodeData((void *)&ossSoMobile, BLUEOSSSOMOBILE_FIELDS, context->pOutput, context->maxOutputSize);

    BLUE_ERROR_CHECK(newOutputSize);

    *context->pOutputSize = newOutputSize;

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t ossSoStorage_WriteEvent(BlueOssSoStorageContext_t *pContext, const uint8_t *const pEvent, uint16_t eventSize)
{
    return BlueReturnCode_NotSupported;
}

static BlueOssSoStorageVTable_t ossSoStorageVTable =
    {
        .getDefaultProvisioningConfiguration = &ossSoStorage_getDefaultProvisioningConfiguration,
        .getStorageProfile = &ossSoStorage_GetStorageProfile,
        .prepare = &ossSoStorage_Prepare,
        .provision = &ossSoStorage_Provision,
        .unprovision = &ossSoStorage_Unprovision,
        .format = &ossSoStorage_Format,
        .read = &ossSoStorage_Read,
        .write = &ossSoStorage_Write,
        .writeEvent = &ossSoStorage_WriteEvent,
};

BlueReturnCode_t blueOssSoMobile_GetStorage(BlueOssSoStorage_t *const pStorage, uint8_t *const pOutput, uint16_t *const pOutputSize)
{
    if (pOutput == NULL || !(*pOutputSize))
    {
        return BlueReturnCode_InvalidArguments;
    }

    ossSoStorageContext.pOutput = pOutput;
    ossSoStorageContext.pOutputSize = pOutputSize;
    ossSoStorageContext.maxOutputSize = *pOutputSize;

    *pStorage = (BlueOssSoStorage_t){
        .pFuncs = &ossSoStorageVTable,
        .pContext = (BlueOssSoStorageContext_t *)&ossSoStorageContext,
    };

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSoMobile_GetStorage_Memory(BlueOssSoStorage_t *const pStorage, const BlueOssSoMobile_t *const pOssSoMobile)
{
    ossSoStorageContext.pOssSoMobile = pOssSoMobile;
    ossSoStorageContext.pOutput = NULL;

    *pStorage = (BlueOssSoStorage_t){
        .pFuncs = &ossSoStorageVTable,
        .pContext = (BlueOssSoStorageContext_t *)&ossSoStorageContext,
    };

    return BlueReturnCode_Ok;
}
