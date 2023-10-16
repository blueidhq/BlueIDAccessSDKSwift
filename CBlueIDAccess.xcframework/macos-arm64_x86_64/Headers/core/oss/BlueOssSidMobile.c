#include "core/oss/BlueOssSidMobile.h"
#include "core/oss/BlueOssSid.h"

#include "core/BlueUtils.h"

typedef struct OssSidMobileStorageContext
{
    const BlueOssSidMobile_t *pOssSidMobile;
    uint8_t *pOutput;
    uint16_t *pOutputSize;
    uint16_t maxOutputSize;
} OssSidMobileStorageContext_t;

static OssSidMobileStorageContext_t ossSidStorageContext =
    {
        .pOssSidMobile = NULL,
        .pOutput = NULL,
};

static BlueReturnCode_t ossSidStorage_GetDefaultProvisioningConfiguration(BlueOssSidStorageContext_t *pContext, BlueOssSidProvisioningConfiguration_t *const pProvisioningConfig)
{
    const BlueOssSidProvisioningConfiguration_t defaultConfig = BLUEOSSSIDMOBILEPROVISIONINGCONFIGURATION_INIT_DEFAULT;
    memcpy(pProvisioningConfig, &defaultConfig, sizeof(BlueOssSidProvisioningConfiguration_t));
    return BlueReturnCode_Ok;
}

static BlueReturnCode_t ossSidStorage_GetStorageProfile(BlueOssSidStorageContext_t *pContext, const BlueOssSidProvisioningConfiguration_t *const pProvisioningConfiguration, BlueOssSidStorageProfile_t *const pProfile)
{
    return BlueReturnCode_NotSupported;
}

static BlueReturnCode_t ossSidStorage_Prepare(BlueOssSidStorageContext_t *pContext, BlueOssPrepareMode_t prepareMode)
{
    OssSidMobileStorageContext_t *const context = (OssSidMobileStorageContext_t *)pContext;

    if (!context->pOutput && !context->pOssSidMobile)
    {
        return BlueReturnCode_InvalidState;
    }

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t ossSidStorage_Provision(BlueOssSidStorageContext_t *pContext, const BlueOssSidProvisioningData_t *const pData, BlueOssSidStorageProvisionWriteFunc_t write, const BlueOssSidStorage_t *const pStorage)
{
    return write(pData, pStorage);
}

static BlueReturnCode_t ossSidStorage_Unprovision(BlueOssSidStorageContext_t *pContext)
{
    return BlueReturnCode_NotSupported;
}

static BlueReturnCode_t ossSidStorage_Format(BlueOssSidStorageContext_t *pContext, bool factoryReset)
{
    return BlueReturnCode_NotSupported;
}

static BlueReturnCode_t ossSidStorage_Read(BlueOssSidStorageContext_t *pContext, uint8_t *const pData, uint16_t dataSize)
{
    OssSidMobileStorageContext_t *const context = (OssSidMobileStorageContext_t *)pContext;

    const BlueOssSidMobile_t *pOssSidMobile = NULL;

    BlueOssSidMobile_t ossSidMobile;

    if (context->pOssSidMobile)
    {
        pOssSidMobile = context->pOssSidMobile;
    }
    else
    {
        BLUE_ERROR_CHECK(blueUtils_DecodeData((void *)&ossSidMobile, BLUEOSSSIDMOBILE_FIELDS, context->pOutput, *context->pOutputSize));
        pOssSidMobile = &ossSidMobile;
    }

    pb_size_t size = pOssSidMobile->infoFile.size;
    const pb_byte_t *bytes = &pOssSidMobile->infoFile.bytes[0];

    if (bytes == NULL)
    {
        return BlueReturnCode_NotSupported;
    }

    if (dataSize > size)
    {
        return BlueReturnCode_EOF;
    }

    memcpy(pData, &bytes[0], dataSize);

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t ossSidStorage_Write(BlueOssSidStorageContext_t *pContext, const uint8_t *const pData, uint16_t dataSize)
{
    OssSidMobileStorageContext_t *const context = (OssSidMobileStorageContext_t *)pContext;

    if (!context->pOutput)
    {
        return BlueReturnCode_InvalidState;
    }

    BlueOssSidMobile_t ossSidMobile = BLUEOSSSIDMOBILE_INIT_ZERO;

    // -- ignore result as it migth be a fresh instance
    blueUtils_DecodeData((void *)&ossSidMobile, BLUEOSSSIDMOBILE_FIELDS, context->pOutput, *context->pOutputSize);

    pb_size_t maxSize = sizeof(ossSidMobile.infoFile.bytes);
    pb_size_t *size = &ossSidMobile.infoFile.size;
    pb_byte_t *bytes = &ossSidMobile.infoFile.bytes[0];

    if (bytes == NULL || size == NULL)
    {
        return BlueReturnCode_NotSupported;
    }

    if (dataSize > maxSize)
    {
        return BlueReturnCode_Overflow;
    }

    memcpy(&bytes[0], pData, dataSize);
    *size = dataSize;

    int newOutputSize = blueUtils_EncodeData((void *)&ossSidMobile, BLUEOSSSIDMOBILE_FIELDS, context->pOutput, context->maxOutputSize);

    BLUE_ERROR_CHECK(newOutputSize);

    *context->pOutputSize = newOutputSize;

    return BlueReturnCode_Ok;
}

static BlueOssSidStorageVTable_t ossSidStorageVTable =
    {
        .getDefaultProvisioningConfiguration = &ossSidStorage_GetDefaultProvisioningConfiguration,
        .getStorageProfile = &ossSidStorage_GetStorageProfile,
        .prepare = &ossSidStorage_Prepare,
        .provision = &ossSidStorage_Provision,
        .unprovision = &ossSidStorage_Unprovision,
        .format = &ossSidStorage_Format,
        .read = &ossSidStorage_Read,
        .write = &ossSidStorage_Write,
};

BlueReturnCode_t blueOssSidMobile_GetStorage(BlueOssSidStorage_t *const pStorage, uint8_t *const pOutput, uint16_t *const pOutputSize)
{
    if (pOutput == NULL || !(*pOutputSize))
    {
        return BlueReturnCode_InvalidArguments;
    }

    ossSidStorageContext.pOssSidMobile = NULL;
    ossSidStorageContext.pOutput = pOutput;
    ossSidStorageContext.pOutputSize = pOutputSize;
    ossSidStorageContext.maxOutputSize = *pOutputSize;

    *pStorage = (BlueOssSidStorage_t){
        .pFuncs = &ossSidStorageVTable,
        .pContext = (BlueOssSidStorageContext_t *)&ossSidStorageContext,
    };

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSidMobile_GetStorage_Memory(BlueOssSidStorage_t *const pStorage, const BlueOssSidMobile_t *const pOssSidMobile)
{
    ossSidStorageContext.pOssSidMobile = pOssSidMobile;
    ossSidStorageContext.pOutput = NULL;

    *pStorage = (BlueOssSidStorage_t){
        .pFuncs = &ossSidStorageVTable,
        .pContext = (BlueOssSidStorageContext_t *)&ossSidStorageContext,
    };

    return BlueReturnCode_Ok;
}
