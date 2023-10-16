#include "core/BlueLog.h"
#include "core/BlueMifareDesfire.h"

#include "core/oss/BlueOssSo.h"
#include "core/oss/BlueOssSoMifareDesfire.h"

typedef struct OssSoMifareDesfireStorageContext
{
    bool hasConfiguration;
    BlueOssSoMifareDesfireConfiguration_t configuration;
    BlueMifareDesfireTag_t tag;
} OssSoMifareDesfireStorageContext_t;

static OssSoMifareDesfireStorageContext_t ossSoStorageContext =
    {
        .hasConfiguration = false,
};

#define AES_KEY_LENGTH 16

static inline uint16_t roundMifareFileSize(int numToRound)
{
    // Mifare file size should be multiple of 32
    return (numToRound + 32 - 1) & -32;
}

static BlueReturnCode_t ossSoStorage_getDefaultProvisioningConfiguration(BlueOssSoStorageContext_t *pContext, BlueOssSoProvisioningConfiguration_t *const pProvisioningConfig)
{
    const BlueOssSoProvisioningConfiguration_t defaultConfig = BLUEOSSSOMIFAREDESFIREPROVISIONINGCONFIGURATION_INIT_DEFAULT;
    memcpy(pProvisioningConfig, &defaultConfig, sizeof(BlueOssSoProvisioningConfiguration_t));
    return BlueReturnCode_Ok;
}

static BlueReturnCode_t ossSoStorage_GetStorageProfile(BlueOssSoStorageContext_t *pContext, const BlueOssSoProvisioningConfiguration_t *const pProvisioningConfig, BlueOssSoStorageProfile_t *const pProfile)
{
    pProfile->infoDataLength = 32;
    pProfile->infoFileSize = 32;

    pProfile->dataDataLength = 16 + (pProvisioningConfig->numberOfDoors * 3) + (pProvisioningConfig->numberOfDTSchedules * ((4 * pProvisioningConfig->numberOfTimePeriodsPerDayId + 1) * pProvisioningConfig->numberOfDayIdsPerDTSchedule));
    pProfile->dataFileSize = roundMifareFileSize(pProfile->dataDataLength);

    pProfile->eventDataLength = 0;
    pProfile->eventFileSize = 0;

    if (pProvisioningConfig->numberOfEvents > 0)
    {
        pProfile->eventDataLength = 5 + (pProvisioningConfig->numberOfEvents * 10);
        pProfile->eventFileSize = roundMifareFileSize(pProfile->eventDataLength);
    }

    pProfile->blacklistDataLength = 0;
    pProfile->blacklistFileSize = 0;
    if (pProvisioningConfig->numberOfBlacklistEntries > 0)
    {
        pProfile->blacklistDataLength = 1 + (pProvisioningConfig->numberOfBlacklistEntries * 16);
        pProfile->blacklistFileSize = roundMifareFileSize(pProfile->blacklistDataLength);
    }

    pProfile->customerExtensionsDataLength = 0;
    pProfile->customerExtensionsFileSize = 0;
    if (pProvisioningConfig->customerExtensionsSize > 0)
    {
        pProfile->customerExtensionsDataLength = 2 + pProvisioningConfig->customerExtensionsSize;
        pProfile->customerExtensionsFileSize = roundMifareFileSize(pProvisioningConfig->customerExtensionsSize);
    }

    pProfile->dataLength = pProfile->infoDataLength + pProfile->dataDataLength + pProfile->eventDataLength + pProfile->blacklistDataLength + pProfile->customerExtensionsDataLength;
    pProfile->fileSize = pProfile->infoFileSize + pProfile->dataFileSize + pProfile->eventFileSize + pProfile->blacklistFileSize + pProfile->customerExtensionsFileSize;

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t ossSoStorage_Prepare(BlueOssSoStorageContext_t *pContext, BlueOssPrepareMode_t prepareMode)
{
    OssSoMifareDesfireStorageContext_t *const context = (OssSoMifareDesfireStorageContext_t *)pContext;

    if (!context->hasConfiguration)
    {
        BLUE_LOG_DEBUG("Missing configuration");
        return BlueReturnCode_InvalidState;
    }

    BlueMifareDesfireTag_t tag;
    memset(&tag, 0, sizeof(BlueMifareDesfireTag_t));

    memset(&context->tag, 0, sizeof(BlueMifareDesfireTag_t));

    if (prepareMode == BlueOssPrepareMode_Read || prepareMode == BlueOssPrepareMode_ReadWrite || prepareMode == BlueOssPrepareMode_Write)
    {
        //
        // Try to select and authenticate to oss so app via project key
        //
        if (context->configuration.projectKey.size != AES_KEY_LENGTH)
        {
            BLUE_LOG_DEBUG("No project aes key was provided");
            return BlueReturnCode_InvalidState;
        }

        BlueReturnCode_t returnCode = blueMifareDesfire_SelectApplication(&tag, context->configuration.aid, BlueMifareDesfireKeyType_Aes, context->configuration.projectKey.bytes, 1);

        if (returnCode == BlueReturnCode_Ok)
        {
            //
            // We where able to select and auth to the desired app so we assignt the selected app tag
            // to our context and leave here, ready to read and/or write
            //
            BLUE_LOG_DEBUG("Found and authenticated to Oss So aid %d", context->configuration.aid);

            memcpy(&context->tag, &tag, sizeof(BlueMifareDesfireTag_t));

            return BlueReturnCode_Ok;
        }

        BLUE_LOG_DEBUG("Failed to select and authenticate at Oss So aid %d with %d", context->configuration.aid, returnCode);

        return returnCode;
    }
    else if (prepareMode == BlueOssPrepareMode_Provision || prepareMode == BlueOssPrepareMode_Unprovision || prepareMode == BlueOssPrepareMode_Format)
    {
        //
        // Try to login via the picc master key now if there's any
        //
        if (context->configuration.piccMasterKey.size != AES_KEY_LENGTH)
        {
            BLUE_LOG_DEBUG("No project aes picc master key was provided");
            return BlueReturnCode_InvalidState;
        }

        memset(&tag, 0, sizeof(BlueMifareDesfireTag_t));

        BlueReturnCode_t returnCode = blueMifareDesfire_SelectMasterAutoProvision(&tag, BlueMifareDesfireKeyType_Aes, context->configuration.piccMasterKey.bytes);

        if (returnCode == BlueReturnCode_Ok)
        {
            //
            // We where able to select and auth to the picc master app s we assign the master tag
            // to our context and leave here, ready take any master action
            //
            BLUE_LOG_DEBUG("Authenticated to Oss So master app");

            memcpy(&context->tag, &tag, sizeof(BlueMifareDesfireTag_t));

            return BlueReturnCode_Ok;
        }

        BLUE_LOG_DEBUG("Failed to authenticate to Oss So master app with %d", returnCode);

        return returnCode;
    }
    else
    {
        BLUE_LOG_ERROR("Unsupported prepareMode %d", prepareMode);

        return BlueReturnCode_NotSupported;
    }
}

static BlueReturnCode_t ossSoStorage_Provision(BlueOssSoStorageContext_t *pContext, const BlueOssSoProvisioningData_t *const pData, BlueOssSoStorageProvisionWriteFunc_t write, const BlueOssSoStorage_t *const pStorage)
{
    OssSoMifareDesfireStorageContext_t *const context = (OssSoMifareDesfireStorageContext_t *)pContext;

    // Validate if we have everything setup properly
    if (!context->tag.hasAid || context->tag.aid != 0)
    {
        BLUE_LOG_DEBUG("Not authenticated on picc master app");
        return BlueReturnCode_InvalidState;
    }

    if (context->configuration.projectKey.size != AES_KEY_LENGTH)
    {
        BLUE_LOG_DEBUG("Missing project key");
        return BlueReturnCode_InvalidState;
    }

    // Get free memory of mifare desfire card
    uint32_t freeMemory = 0;

    BLUE_ERROR_CHECK_DEBUG(blueMifareDesfire_ReadFreeMemory(&context->tag, &freeMemory), "Read free memory of mifare desfire");

    // Calculate size of provisioning data
    BlueOssSoStorageProfile_t profile = BLUEOSSSOSTORAGEPROFILE_INIT_ZERO;
    BLUE_ERROR_CHECK_DEBUG(ossSoStorage_GetStorageProfile(pContext, &pData->configuration, &profile), "Get mifare desfire storage profile");

    if (profile.fileSize == 0)
    {
        BLUE_LOG_DEBUG("Nothing to provision, provision data size is 0 bytes");
        return BlueReturnCode_InvalidArguments;
    }

    if (profile.fileSize >= freeMemory)
    {
        BLUE_LOG_DEBUG("Provisioning data of %d bytes is larger than available memory of %d bytes", profile.fileSize, freeMemory);
        return BlueReturnCode_NfcTransponderStorageFull;
    }

    if (!context->tag.hasAid || context->tag.aid != 0)
    {
        BLUE_LOG_DEBUG("No authenticated app or authenticated app is not picc master app");
        return BlueReturnCode_InvalidState;
    }

    //
    // Provision now by creating the application and all required files with their desired sizes
    // and write their default contents
    //

    //
    // Create Oss So application and assign the keys
    //
    // TODO : Check settings value of 0x0B for correctness
    BLUE_ERROR_CHECK_DEBUG(blueMifareDesfire_CreateApplication(&context->tag, context->configuration.aid, 0x0B, BlueMifareDesfireKeyType_Aes, 2), "Create mifare desfire Oss So application");

    //
    // Auth with default app master key on the application and assign our new app keys
    //
    // BlueMifareDesfireTag_t appTag;
    // memset(&appTag, 0, sizeof(BlueMifareDesfireTag_t));

    // Login using default app master key
    const uint8_t defaultKey[AES_KEY_LENGTH] = {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
    BLUE_ERROR_CHECK_DEBUG(blueMifareDesfire_SelectApplication(&context->tag, context->configuration.aid, BlueMifareDesfireKeyType_Aes, defaultKey, 0), "Authenticate on Oss So application with default app master key");

// Helper macro that will try to delete the Oss So application if anything fails
#define MF_APP_ERROR_CHECK(EXPRESSION, DEBUG_MESSAGE)                                                                                                                                               \
    {                                                                                                                                                                                               \
        BlueReturnCode_t returnCode = EXPRESSION;                                                                                                                                                   \
        if (returnCode < 0)                                                                                                                                                                         \
        {                                                                                                                                                                                           \
            BLUE_ERROR_LOG_DEBUG(returnCode, DEBUG_MESSAGE);                                                                                                                                        \
            BLUE_ERROR_LOG_DEBUG(blueMifareDesfire_SelectApplication(&context->tag, 0, BlueMifareDesfireKeyType_Aes, context->configuration.piccMasterKey.bytes, 0), "Authenticate on master app"); \
            BLUE_ERROR_LOG_DEBUG(blueMifareDesfire_DeleteApplication(&context->tag, context->configuration.aid), "Delete Oss So application");                                                      \
            return returnCode;                                                                                                                                                                      \
        }                                                                                                                                                                                           \
    }

    // Create Oss So info file
    MF_APP_ERROR_CHECK(blueMifareDesfire_CreateFile(&context->tag, BlueOssSoFileId_Info, profile.infoFileSize, 3, 0x1110), "Create Oss So info file");

    // Create Oss So data file
    MF_APP_ERROR_CHECK(blueMifareDesfire_CreateFile(&context->tag, BlueOssSoFileId_Data, profile.dataFileSize, 3, 0x1110), "Create Oss So data file");

    // Create Oss So event file
    if (profile.eventFileSize > 0)
    {
        MF_APP_ERROR_CHECK(blueMifareDesfire_CreateFile(&context->tag, BlueOssSoFileId_Event, profile.eventFileSize, 3, 0x1110), "Create Oss So event file");
    }

    // Create Oss So blacklist file if desired
    if (profile.blacklistFileSize > 0)
    {
        MF_APP_ERROR_CHECK(blueMifareDesfire_CreateFile(&context->tag, BlueOssSoFileId_Blacklist, profile.blacklistFileSize, 3, 0x1110), "Create Oss So blacklist file");
    }

    // Create Oss So customer extensions file if desired
    if (profile.customerExtensionsFileSize > 0)
    {
        MF_APP_ERROR_CHECK(blueMifareDesfire_CreateFile(&context->tag, BlueOssSoFileId_CustomerExtensions, profile.customerExtensionsFileSize, 3, 0x1110), "Create Oss So customer extensions file");
    }

    // Set Oss So project read/write key
    MF_APP_ERROR_CHECK(blueMifareDesfire_ChangeApplicationKey(&context->tag, BlueMifareDesfireKeyType_Aes, context->configuration.projectKey.bytes, defaultKey, 1), "Set Oss So project key");

    // Set Oss So app master key
    MF_APP_ERROR_CHECK(blueMifareDesfire_ChangeApplicationKey(&context->tag, BlueMifareDesfireKeyType_Aes, context->configuration.appMasterKey.bytes, defaultKey, 0), "Set Oss So app master key");

    // Authenticate with project key to support further read/write operations
    memset(&context->tag, 0, sizeof(BlueMifareDesfireTag_t));
    MF_APP_ERROR_CHECK(blueMifareDesfire_SelectApplication(&context->tag, context->configuration.aid, BlueMifareDesfireKeyType_Aes, context->configuration.projectKey.bytes, 1), "Authenticate on Oss So application with new app project key");

    // Let our handler do its job now to write the initial provisioning data
    MF_APP_ERROR_CHECK(write(pData, pStorage), "Call provision writer");

    // Set context tag to our authenticated app tag now for further operations
    // memcpy(&context->tag, &appTag, sizeof(BlueMifareDesfireTag_t));

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t ossSoStorage_Unprovision(BlueOssSoStorageContext_t *pContext)
{
    OssSoMifareDesfireStorageContext_t *const context = (OssSoMifareDesfireStorageContext_t *)pContext;

    if (!context->tag.hasAid || context->tag.aid != 0)
    {
        BLUE_LOG_DEBUG("Not authenticated on picc master app");
        return BlueReturnCode_InvalidState;
    }

    // Simply delete the oss so application now
    BLUE_ERROR_LOG_DEBUG(blueMifareDesfire_DeleteApplication(&context->tag, context->configuration.aid), "Delete Oss So application");

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t ossSoStorage_Format(BlueOssSoStorageContext_t *pContext, bool factoryReset)
{
    OssSoMifareDesfireStorageContext_t *const context = (OssSoMifareDesfireStorageContext_t *)pContext;

    if (!context->tag.hasAid || context->tag.aid != 0)
    {
        BLUE_LOG_DEBUG("Not authenticated on picc master app");
        return BlueReturnCode_InvalidState;
    }

    // Format the card now
    BLUE_ERROR_CHECK_DEBUG(blueMifareDesfire_Format(&context->tag), "Format mifare desfire card");

    // If we're supposed to do a factory reset we'll reset the picc master key to the default factory des key
    if (factoryReset)
    {
        const uint8_t desDefaultKey[AES_KEY_LENGTH] = {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
        BLUE_ERROR_CHECK_DEBUG(blueMifareDesfire_ChangeApplicationKey(&context->tag, BlueMifareDesfireKeyType_Des, desDefaultKey, context->configuration.piccMasterKey.bytes, 0), "Change to factory des picc master key");
    }

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t ossSoStorage_Read(BlueOssSoStorageContext_t *pContext, BlueOssSoFileId_t fileId, uint16_t offset, uint8_t *const pData, uint16_t dataSize)
{
    OssSoMifareDesfireStorageContext_t *const context = (OssSoMifareDesfireStorageContext_t *)pContext;

    if (!context->tag.hasAid || context->tag.aid != context->configuration.aid)
    {
        BLUE_LOG_DEBUG("Oss So application is not selected");
        return BlueReturnCode_InvalidState;
    }

    return blueMifareDesfire_ReadFile(&context->tag, fileId, offset, pData, dataSize, 3);
}

static BlueReturnCode_t ossSoStorage_Write(BlueOssSoStorageContext_t *pContext, BlueOssSoFileId_t fileId, uint16_t offset, const uint8_t *const pData, uint16_t dataSize)
{

    OssSoMifareDesfireStorageContext_t *const context = (OssSoMifareDesfireStorageContext_t *)pContext;

    if (!context->tag.hasAid || context->tag.aid != context->configuration.aid)
    {
        BLUE_LOG_DEBUG("Oss So application is not selected");
        return BlueReturnCode_InvalidState;
    }

    return blueMifareDesfire_WriteFile(&context->tag, fileId, offset, pData, dataSize, 3);
}

static BlueReturnCode_t ossSoStorage_WriteEvent(BlueOssSoStorageContext_t *pContext, const uint8_t *const pEvent, uint16_t eventSize)
{
    // This is not supposed to be called for mifare
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

BlueReturnCode_t blueOssSoMifareDesfire_GetStorage(BlueOssSoStorage_t *const pStorage, const BlueOssSoSettings_t *const pSettings)
{
    if (pSettings != NULL)
    {
        if (!pSettings->has_mifareDesfireConfig)
        {
            return BlueReturnCode_InvalidArguments;
        }

        if (!pSettings->mifareDesfireConfig.aid)
        {
            BLUE_LOG_DEBUG("Invalid oss aid %d", pSettings->mifareDesfireConfig.aid);
            return BlueReturnCode_InvalidArguments;
        }

        memcpy(&ossSoStorageContext.configuration, &pSettings->mifareDesfireConfig, sizeof(BlueOssSoMifareDesfireConfiguration_t));
    }

    ossSoStorageContext.hasConfiguration = pSettings != NULL;

    *pStorage = (BlueOssSoStorage_t){
        .pFuncs = &ossSoStorageVTable,
        .pContext = (BlueOssSoStorageContext_t *)&ossSoStorageContext,
    };

    return BlueReturnCode_Ok;
}
