#include "core/BlueMifareDesfire.h"
#include "core/BlueLog.h"

#include "core/oss/BlueOssSid.h"
#include "core/oss/BlueOssSidMifareDesfire.h"

typedef struct OssSidMifareDesfireStorageContext
{
    bool hasConfiguration;
    BlueOssSidMifareDesfireConfiguration_t configuration;
    BlueMifareDesfireTag_t tag;
} OssSidMifareDesfireStorageContext_t;

static OssSidMifareDesfireStorageContext_t ossSidStorageContext =
    {
        .hasConfiguration = false,
};

#define AES_KEY_LENGTH 16

static BlueReturnCode_t ossSidStorage_GetDefaultProvisioningConfiguration(BlueOssSidStorageContext_t *pContext, BlueOssSidProvisioningConfiguration_t *const pProvisioningConfig)
{
    const BlueOssSidProvisioningConfiguration_t defaultConfig = BLUEOSSSIDMIFAREDESFIREPROVISIONINGCONFIGURATION_INIT_DEFAULT;
    memcpy(pProvisioningConfig, &defaultConfig, sizeof(BlueOssSidProvisioningConfiguration_t));
    return BlueReturnCode_Ok;
}

static BlueReturnCode_t ossSidStorage_GetStorageProfile(BlueOssSidStorageContext_t *pContext, const BlueOssSidProvisioningConfiguration_t *const pProvisioningConfiguration, BlueOssSidStorageProfile_t *const pProfile)
{
    pProfile->infoDataLength = 32;
    pProfile->infoFileSize = 32;

    pProfile->dataLength = pProfile->infoDataLength;
    pProfile->fileSize = pProfile->infoFileSize;

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t ossSidStorage_Prepare(BlueOssSidStorageContext_t *pContext, BlueOssPrepareMode_t prepareMode)
{
    OssSidMifareDesfireStorageContext_t *const context = (OssSidMifareDesfireStorageContext_t *)pContext;

    if (!context->hasConfiguration)
    {
        BLUE_LOG_DEBUG("Missing configuration");
        return BlueReturnCode_InvalidState;
    }

    BlueMifareDesfireTag_t tag;
    memset(&tag, 0, sizeof(BlueMifareDesfireTag_t));

    memset(&context->tag, 0, sizeof(BlueMifareDesfireTag_t));

    if (prepareMode == BlueOssPrepareMode_Read)
    {
        //
        // Try to select and authenticate to oss sid app via project key
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
            // to our context and leave here, ready to read
            //
            BLUE_LOG_DEBUG("Found and authenticated to Oss Sid aid %d", context->configuration.aid);

            memcpy(&context->tag, &tag, sizeof(BlueMifareDesfireTag_t));

            return BlueReturnCode_Ok;
        }

        BLUE_LOG_DEBUG("Failed to select and authenticate at Oss Sid aid %d with %d", context->configuration.aid, returnCode);

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
            BLUE_LOG_DEBUG("Authenticated to Oss Sid master app");

            memcpy(&context->tag, &tag, sizeof(BlueMifareDesfireTag_t));

            return BlueReturnCode_Ok;
        }

        BLUE_LOG_DEBUG("Failed to authenticate to Oss Sid master app with %d", returnCode);

        return returnCode;
    }
    else
    {
        BLUE_LOG_ERROR("Unsupported prepareMode %d", prepareMode);

        return BlueReturnCode_NotSupported;
    }
}

static BlueReturnCode_t ossSidStorage_Provision(BlueOssSidStorageContext_t *pContext, const BlueOssSidProvisioningData_t *const pData, BlueOssSidStorageProvisionWriteFunc_t write, const BlueOssSidStorage_t *const pStorage)
{
    OssSidMifareDesfireStorageContext_t *const context = (OssSidMifareDesfireStorageContext_t *)pContext;

    // Validate if we have everything setup properly
    if (!context->tag.hasAid || context->tag.aid != 0)
    {
        BLUE_LOG_DEBUG("Not authenticated on picc master app");
        return BlueReturnCode_InvalidState;
    }

    if (context->configuration.appMasterKey.size != AES_KEY_LENGTH)
    {
        BLUE_LOG_DEBUG("Missing app master key");
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
    BlueOssSidStorageProfile_t profile = BLUEOSSSIDSTORAGEPROFILE_INIT_ZERO;
    BLUE_ERROR_CHECK_DEBUG(ossSidStorage_GetStorageProfile(pContext, &pData->configuration, &profile), "Get mifare desfire storage profile");

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
    BLUE_ERROR_CHECK_DEBUG(blueMifareDesfire_CreateApplication(&context->tag, context->configuration.aid, 0x0B, BlueMifareDesfireKeyType_Aes, 2), "Create mifare desfire Oss Sid application");

    //
    // Auth with default app master key on the application and assign our new app keys
    //

    // Login using default app master key
    const uint8_t defaultKey[AES_KEY_LENGTH] = {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
    BLUE_ERROR_CHECK_DEBUG(blueMifareDesfire_SelectApplication(&context->tag, context->configuration.aid, BlueMifareDesfireKeyType_Aes, defaultKey, 0), "Authenticate on Oss So application with default app master key");

// Helper macro that will try to delete the Oss So application if anything fails
#define MF_APP_ERROR_CHECK(EXPRESSION, DEBUG_MESSAGE)                                                                                                                                                 \
    {                                                                                                                                                                                                 \
        BlueReturnCode_t returnCode = EXPRESSION;                                                                                                                                                     \
        if (returnCode < 0)                                                                                                                                                                           \
        {                                                                                                                                                                                             \
            BLUE_ERROR_LOG_DEBUG(returnCode, DEBUG_MESSAGE);                                                                                                                                          \
            BLUE_ERROR_LOG_DEBUG(blueMifareDesfire_SelectApplication(&context->tag, 0, BlueMifareDesfireKeyType_Aes, context->configuration.piccMasterKey.bytes, 0), "Authenticate PICC Master key"); \
            BLUE_ERROR_LOG_DEBUG(blueMifareDesfire_DeleteApplication(&context->tag, context->configuration.aid), "Delete Oss Sid application");                                                       \
            return returnCode;                                                                                                                                                                        \
        }                                                                                                                                                                                             \
    }

    // Create Oss So info file
    MF_APP_ERROR_CHECK(blueMifareDesfire_CreateFile(&context->tag, 0, profile.infoFileSize, 3, 0x1F00), "Create Oss Sid info file");

    // Let our handler do its job now to write the initial provisioning data
    MF_APP_ERROR_CHECK(write(pData, pStorage), "Call provision writer");

    // Change file settings of info file to 0x1FF0
    MF_APP_ERROR_CHECK(blueMifareDesfire_ChangeFileSettings(&context->tag, 0, 3, 0x1FF0), "Change Oss Sid info file access settings");

    // Set Oss Sid project read key
    MF_APP_ERROR_CHECK(blueMifareDesfire_ChangeApplicationKey(&context->tag, BlueMifareDesfireKeyType_Aes, context->configuration.projectKey.bytes, defaultKey, 1), "Set Oss Sid project key");

    // Set Oss So app master key
    MF_APP_ERROR_CHECK(blueMifareDesfire_ChangeApplicationKey(&context->tag, BlueMifareDesfireKeyType_Aes, context->configuration.appMasterKey.bytes, defaultKey, 0), "Set Oss Sid app master key");

    // Authenticate with project key to support further reading
    memset(&context->tag, 0, sizeof(BlueMifareDesfireTag_t));
    MF_APP_ERROR_CHECK(blueMifareDesfire_SelectApplication(&context->tag, context->configuration.aid, BlueMifareDesfireKeyType_Aes, context->configuration.projectKey.bytes, 1), "Authenticate on Oss Sid application with new app project key");

    // Set context tag to our authenticated app tag now for further operations
    // memcpy(&context->tag, &appTag, sizeof(BlueMifareDesfireTag_t));

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t ossSidStorage_Unprovision(BlueOssSidStorageContext_t *pContext)
{
    OssSidMifareDesfireStorageContext_t *const context = (OssSidMifareDesfireStorageContext_t *)pContext;

    if (!context->tag.hasAid || context->tag.aid != 0)
    {
        BLUE_LOG_DEBUG("Not authenticated on picc master app");
        return BlueReturnCode_InvalidState;
    }

    // Simply delete the oss sid application now
    BLUE_ERROR_LOG_DEBUG(blueMifareDesfire_DeleteApplication(&context->tag, context->configuration.aid), "Delete Oss Sid application");

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t ossSidStorage_Format(BlueOssSidStorageContext_t *pContext, bool factoryReset)
{
    OssSidMifareDesfireStorageContext_t *const context = (OssSidMifareDesfireStorageContext_t *)pContext;

    // If we're not yet authenticated on picc master key then do so first
    if (!context->tag.hasAid || context->tag.aid != 0)
    {
        if (context->configuration.piccMasterKey.size != AES_KEY_LENGTH)
        {
            BLUE_LOG_DEBUG("Missing picc master key to authenticate for formatting");
            return BlueReturnCode_InvalidState;
        }

        memset(&context->tag, 0, sizeof(BlueMifareDesfireTag_t));

        BLUE_ERROR_CHECK_DEBUG(blueMifareDesfire_SelectMaster(&context->tag, BlueMifareDesfireKeyType_Aes, context->configuration.piccMasterKey.bytes), "Authenticate via picc master key");
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

static BlueReturnCode_t ossSidStorage_Read(BlueOssSidStorageContext_t *pContext, uint8_t *const pData, uint16_t dataSize)
{
    OssSidMifareDesfireStorageContext_t *const context = (OssSidMifareDesfireStorageContext_t *)pContext;

    if (!context->tag.hasAid || context->tag.aid != context->configuration.aid)
    {
        BLUE_LOG_DEBUG("Oss Sid application is not selected");
        return BlueReturnCode_InvalidState;
    }

    return blueMifareDesfire_ReadFile(&context->tag, 0, 0, pData, dataSize, 3);
}

static BlueReturnCode_t ossSidStorage_Write(BlueOssSidStorageContext_t *pContext, const uint8_t *const pData, uint16_t dataSize)
{

    OssSidMifareDesfireStorageContext_t *const context = (OssSidMifareDesfireStorageContext_t *)pContext;

    if (!context->tag.hasAid || context->tag.aid != context->configuration.aid)
    {
        BLUE_LOG_DEBUG("Oss Sid application is not selected");
        return BlueReturnCode_InvalidState;
    }

    return blueMifareDesfire_WriteFile(&context->tag, 0, 0, pData, dataSize, 3);
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

BlueReturnCode_t blueOssSidMifareDesfire_GetStorage(BlueOssSidStorage_t *const pStorage, const BlueOssSidSettings_t *const pSettings)
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

        memcpy(&ossSidStorageContext.configuration, &pSettings->mifareDesfireConfig, sizeof(BlueOssSidMifareDesfireConfiguration_t));
    }

    ossSidStorageContext.hasConfiguration = pSettings != NULL;

    *pStorage = (BlueOssSidStorage_t){
        .pFuncs = &ossSidStorageVTable,
        .pContext = (BlueOssSidStorageContext_t *)&ossSidStorageContext,
    };

    return BlueReturnCode_Ok;
}
