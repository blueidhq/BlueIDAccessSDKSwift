#include "core/BlueLog.h"
#include "core/BlueUtils.h"

#include "core/oss/BlueOssSid.h"
#include "core/oss/BlueOssSidMobile.h"
#include "core/oss/BlueOssSidMifareDesfire.h"

//
// -- Reading --
//

BlueReturnCode_t blueOssSid_ReadCredentialType(uint8_t credentialTypeEncoded, BlueOssSidCredentialType_t *const pCredentialType)
{
    uint8_t bits[8];
    blueOss_DecodeBits(credentialTypeEncoded, bits);

    if (bits[7] == 0)
    {
        pCredentialType->typeSource = BlueOssCredentialTypeSource_Oss;
        pCredentialType->has_oss = true;

        return BlueReturnCode_Ok;
    }
    else if (bits[7] == 1)
    {
        pCredentialType->typeSource = BlueOssCredentialTypeSource_Proprietary;
        pCredentialType->has_proprietary = true;
        pCredentialType->proprietary = (BlueOssSidCredentialTypeProprietary_t){
            .mfgCode =
                {
                    bits[0],
                    bits[1],
                    bits[2],
                    bits[3],
                    bits[4],
                    bits[5],
                    bits[6],
                },
        };

        return BlueReturnCode_Ok;
    }

    return BlueReturnCode_OssSidInvalidCredentialType;
}

BlueReturnCode_t blueOssSid_ReadInfoFile(const BlueOssSidStorage_t *const pStorage, BlueOssSidFileInfo_t *const pInfoFile)
{
    uint8_t buffer[13];

    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->read(pStorage->pContext, buffer, sizeof(buffer)), "Read info file");

    pInfoFile->versionMajor = buffer[0];
    pInfoFile->versionMinor = buffer[1];

    BLUE_ERROR_CHECK_DEBUG(blueOssSid_ReadCredentialType(buffer[2], &pInfoFile->credentialType), "Read info file CredentialType");
    BLUE_ERROR_CHECK_DEBUG(blueOss_ReadCredentialId(&buffer[3], &pInfoFile->credentialId), "Read info file CredentialId");

    return BlueReturnCode_Ok;
}

//
// -- Writing --
//

BlueReturnCode_t blueOssSid_WriteCredentialType(uint8_t *const credentialTypeEncoded, const BlueOssSidCredentialType_t *const pCredentialType)
{
    uint8_t bits[8] =
        {
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
        };

    if (pCredentialType->typeSource == BlueOssCredentialTypeSource_Oss)
    {
        if (!pCredentialType->has_oss)
        {
            BLUE_LOG_DEBUG("No oss on credential type setup");
            return BlueReturnCode_OssSidInvalidCredentialType;
        }

        bits[7] = 0;

        *credentialTypeEncoded = blueOss_EncodeBits(bits);

        return BlueReturnCode_Ok;
    }
    else if (pCredentialType->typeSource == BlueOssCredentialTypeSource_Proprietary)
    {
        if (!pCredentialType->has_proprietary)
        {
            BLUE_LOG_DEBUG("No proprietary on credential type setup");
            return BlueReturnCode_OssSidInvalidCredentialType;
        }

        bits[7] = 1;

        const uint8_t *const mfgCode = &pCredentialType->proprietary.mfgCode[0];

        bits[0] = mfgCode[0];
        bits[1] = mfgCode[1];
        bits[2] = mfgCode[2];
        bits[3] = mfgCode[3];
        bits[4] = mfgCode[4];
        bits[5] = mfgCode[5];
        bits[6] = mfgCode[6];

        *credentialTypeEncoded = blueOss_EncodeBits(bits);

        return BlueReturnCode_Ok;
    }

    return BlueReturnCode_OssSidInvalidCredentialType;
}

BlueReturnCode_t blueOssSid_WriteInfoFile(const BlueOssSidStorage_t *const pStorage, const BlueOssSidFileInfo_t *const pInfoFile)
{
    uint8_t buffer[13];
    memset(buffer, 0, sizeof(buffer));

    buffer[0] = pInfoFile->versionMajor;
    buffer[1] = pInfoFile->versionMinor;

    BLUE_ERROR_CHECK_DEBUG(blueOssSid_WriteCredentialType(&buffer[2], &pInfoFile->credentialType), "Write info file CredentialType");
    BLUE_ERROR_CHECK_DEBUG(blueOss_WriteCredentialId(&buffer[3], &pInfoFile->credentialId), "Write info file CredentialId");

    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->write(pStorage->pContext, buffer, sizeof(buffer)), "Write info file");

    return BlueReturnCode_Ok;
}

//
// -- Processing --
//

BlueReturnCode_t blueOssSid_GetStorage(BlueTransponderType_t transponderType, BlueOssSidStorage_t *const pStorage, const BlueOssSidSettings_t *const pSettings, uint8_t *const pOutput, uint16_t *const pOutputSize)
{
    if (transponderType == BlueTransponderType_MobileTransponder)
    {
        BLUE_ERROR_CHECK_DEBUG(blueOssSidMobile_GetStorage(pStorage, pOutput, pOutputSize), "Get mobile Oss Sid storage");

        return BlueReturnCode_Ok;
    }
    else if (transponderType == BlueTransponderType_MifareDesfire)
    {
        BLUE_ERROR_CHECK_DEBUG(blueOssSidMifareDesfire_GetStorage(pStorage, pSettings), "Get mifare desfire Oss Sid storage");

        return BlueReturnCode_Ok;
    }

    return BlueReturnCode_InvalidArguments;
}

BlueReturnCode_t blueOssSid_GetStorage_Ext(BlueTransponderType_t transponderType, BlueOssSidStorage_t *const pStorage, const uint8_t *const pSettingsBuffer, uint16_t settingsBufferSize, uint8_t *const pOutput, uint16_t *const pOutputSize)
{
    BlueOssSidSettings_t settings = BLUEOSSSIDSETTINGS_INIT_ZERO;

    if (pSettingsBuffer != NULL)
    {
        BLUE_ERROR_CHECK_DEBUG(blueUtils_DecodeData(&settings, BLUEOSSSIDSETTINGS_FIELDS, pSettingsBuffer, settingsBufferSize), "Decode Oss Sid settings");
    }

    return blueOssSid_GetStorage(transponderType, pStorage, pSettingsBuffer != NULL ? &settings : NULL, pOutput, pOutputSize);
}

BlueReturnCode_t blueOssSid_GetStorageProfile(const BlueOssSidStorage_t *const pStorage, const BlueOssSidProvisioningConfiguration_t *const pProvisioningConfig, BlueOssSidStorageProfile_t *const pProfile)
{
    BlueOssSidProvisioningConfiguration_t provisioningConfig;

    if (!pProvisioningConfig)
    {
        BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->getDefaultProvisioningConfiguration(pStorage->pContext, &provisioningConfig), "Get default provisioning config");
    }
    else
    {
        memcpy(&provisioningConfig, pProvisioningConfig, sizeof(BlueOssSidProvisioningConfiguration_t));
    }

    return pStorage->pFuncs->getStorageProfile(pStorage->pContext, &provisioningConfig, pProfile);
}

BlueReturnCode_t blueOssSid_GetStorageProfile_Ext(const BlueOssSidStorage_t *const pStorage, const uint8_t *const pConfigBuffer, uint16_t configBufferSize, uint8_t *const pProfileBuffer, uint16_t profileBufferSize)
{
    BlueOssSidProvisioningConfiguration_t configuration = BLUEOSSSIDPROVISIONINGCONFIGURATION_INIT_ZERO;

    if (pConfigBuffer != NULL)
    {
        BLUE_ERROR_CHECK_DEBUG(blueUtils_DecodeData(&configuration, BLUEOSSSIDPROVISIONINGCONFIGURATION_FIELDS, pConfigBuffer, configBufferSize), "Decode Oss Sid provisioning configuration");
    }

    BlueOssSidStorageProfile_t profile = BLUEOSSSIDSTORAGEPROFILE_INIT_ZERO;

    BLUE_ERROR_CHECK(blueOssSid_GetStorageProfile(pStorage, pConfigBuffer != NULL ? &configuration : NULL, &profile));

    BLUE_ERROR_CHECK_DEBUG(blueUtils_EncodeData(&profile, BLUEOSSSIDSTORAGEPROFILE_FIELDS, pProfileBuffer, profileBufferSize), "Encode Oss Sid storage profile");

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSid_Format(const BlueOssSidStorage_t *const pStorage, bool factoryReset)
{
    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->prepare(pStorage->pContext, BlueOssPrepareMode_Format), "Prepare storage in format mode");
    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->format(pStorage->pContext, factoryReset), "Format storage");

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSid_IsProvisioned(const BlueOssSidStorage_t *const pStorage)
{
    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->prepare(pStorage->pContext, BlueOssPrepareMode_Read), "Prepare storage in read mode");

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t provisionWrite(const BlueOssSidProvisioningData_t *const pData, const BlueOssSidStorage_t *const pStorage)
{
    //
    // Write default configuration after provisioning
    //
    const BlueOssSidVersion_t ossSidVersion = BLUEOSSSIDVERSION_INIT_DEFAULT;

    BlueOssSidConfiguration_t configuration;
    memset(&configuration, 0, sizeof(BlueOssSidConfiguration_t));

    configuration.info.versionMajor = ossSidVersion.versionMajor;
    configuration.info.versionMinor = ossSidVersion.versionMinor;
    memcpy(&configuration.info.credentialType, &pData->credentialType, sizeof(BlueOssSidCredentialType_t));
    memcpy(&configuration.info.credentialId, &pData->credentialId, sizeof(BlueCredentialId_t));

    BLUE_ERROR_CHECK_DEBUG(blueOssSid_WriteInfoFile(pStorage, &configuration.info), "Write config info file");

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSid_Provision(const BlueOssSidStorage_t *const pStorage, const BlueOssSidProvisioningData_t *const pData)
{
    BlueOssSidProvisioningData_t data;
    memcpy(&data, pData, sizeof(BlueOssSidProvisioningData_t));

    if (!data.has_configuration)
    {
        BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->getDefaultProvisioningConfiguration(pStorage->pContext, &data.configuration), "Get default provisioning config");
        data.has_configuration = true;
    }

    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->prepare(pStorage->pContext, BlueOssPrepareMode_Provision), "Prepare storage in provision mode");
    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->provision(pStorage->pContext, &data, &provisionWrite, pStorage), "Provision Oss Sid with chosen storage");

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSid_Provision_Ext(const BlueOssSidStorage_t *const pStorage, const uint8_t *const pDataBuffer, uint16_t dataBufferSize)
{
    BlueOssSidProvisioningData_t data = BLUEOSSSIDPROVISIONINGDATA_INIT_ZERO;

    BLUE_ERROR_CHECK_DEBUG(blueUtils_DecodeData(&data, BLUEOSSSIDPROVISIONINGDATA_FIELDS, pDataBuffer, dataBufferSize), "Decode Oss Sid provisioning data");

    return blueOssSid_Provision(pStorage, &data);
}

BlueReturnCode_t blueOssSid_Unprovision(const BlueOssSidStorage_t *const pStorage)
{
    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->prepare(pStorage->pContext, BlueOssPrepareMode_Unprovision), "Prepare storage in unprovision mode");
    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->unprovision(pStorage->pContext), "Unprovision Oss Sid on storage");

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSid_ReadConfiguration(const BlueOssSidStorage_t *const pStorage, BlueOssSidConfiguration_t *const pConfiguration)
{
    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->prepare(pStorage->pContext, BlueOssPrepareMode_Read), "Prepare storage in read mode");
    BLUE_ERROR_CHECK_DEBUG(blueOssSid_ReadInfoFile(pStorage, &pConfiguration->info), "Read config info file");

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSid_ReadConfiguration_Ext(const BlueOssSidStorage_t *const pStorage, uint8_t *const pConfigurationBuffer, uint16_t configurationBufferSize)
{
    BlueOssSidConfiguration_t configuration = BLUEOSSSIDCONFIGURATION_INIT_ZERO;

    BLUE_ERROR_CHECK(blueOssSid_ReadConfiguration(pStorage, &configuration));

    BLUE_ERROR_CHECK_DEBUG(blueUtils_EncodeData(&configuration, BLUEOSSSIDCONFIGURATION_FIELDS, pConfigurationBuffer, configurationBufferSize), "Encode Oss Sid configuration");

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSid_ProcessAccess(const BlueOssSidStorage_t *const pStorage, const BlueOssSidProcess_t *const pProcess, BlueOssAccessResult_t *const pAccessResult)
{
    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->prepare(pStorage->pContext, BlueOssPrepareMode_Read), "Prepare storage in read mode");

    BlueOssSidFileInfo_t info;

    BLUE_ERROR_CHECK(blueOssSid_ReadInfoFile(pStorage, &info));

    const BlueOssSidVersion_t ossSidVersion = BLUEOSSSIDVERSION_INIT_DEFAULT;
    if (info.versionMajor > ossSidVersion.versionMajor)
    {
        BLUE_LOG_DEBUG("Invalid Oss Sid version, received %d.%d but only supports %d.%d", info.versionMajor, info.versionMinor, ossSidVersion.versionMajor, ossSidVersion.versionMinor);
        return BlueReturnCode_OssSidIncompatibleMajorVersion;
    }

    BlueOssAccessResult_t accessResult = BlueOssAccessResult_Default;

    if (info.credentialType.typeSource == BlueOssCredentialTypeSource_Proprietary)
    {
        BLUE_ERROR_CHECK_DEBUG(pProcess->pFuncs->validateProprietaryCredentialType(pProcess->pContext, &info.credentialType.proprietary, &info.credentialId, &accessResult), "Validate via validateProprietaryCredentialType");
    }
    else if (info.credentialType.typeSource == BlueOssCredentialTypeSource_Oss)
    {
        BLUE_ERROR_CHECK_DEBUG(pProcess->pFuncs->validateOssCredentialType(pProcess->pContext, &info.credentialType.oss, &info.credentialId, &accessResult), "Validate via validateOssCredentialType");
    }
    else
    {
        return BlueReturnCode_InvalidState;
    }

    if (pAccessResult != NULL)
    {
        memcpy(pAccessResult, &accessResult, sizeof(BlueOssAccessResult_t));
    }

    if (accessResult.accessGranted)
    {
        return pProcess->pFuncs->grantAccess((void *)pProcess->pContext, accessResult.accessType, &accessResult.scheduleEndTime);
    }

    return pProcess->pFuncs->denyAccess((void *)pProcess->pContext, BlueAccessType_NoAccess);
}
