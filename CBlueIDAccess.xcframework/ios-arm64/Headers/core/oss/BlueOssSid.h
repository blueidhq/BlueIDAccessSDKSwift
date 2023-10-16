#ifndef BLUE_OSS_SID_H
#define BLUE_OSS_SID_H

#include "core/oss/BlueOss.h"

extern const BlueOssSidVersion_t *const blueOssSidVersion;

typedef struct BlueOssSidStorage BlueOssSidStorage_t;

//
// Blue Oss Sid storage reading / writing
//

typedef BlueReturnCode_t (*BlueOssSidStorageProvisionWriteFunc_t)(const BlueOssSidProvisioningData_t *const pData, const BlueOssSidStorage_t *const pStorage);

typedef void BlueOssSidStorageContext_t;

typedef struct BlueOssSidStorageVTable_t
{
    BlueReturnCode_t (*getDefaultProvisioningConfiguration)(BlueOssSidStorageContext_t *pContext, BlueOssSidProvisioningConfiguration_t *const pProvisioningConfig);

    BlueReturnCode_t (*getStorageProfile)(BlueOssSidStorageContext_t *pContext, const BlueOssSidProvisioningConfiguration_t *const pProvisioningConfiguration, BlueOssSidStorageProfile_t *const pProfile);

    BlueReturnCode_t (*prepare)(BlueOssSidStorageContext_t *pContext, BlueOssPrepareMode_t prepareMode);

    BlueReturnCode_t (*provision)(BlueOssSidStorageContext_t *pContext, const BlueOssSidProvisioningData_t *const pData, BlueOssSidStorageProvisionWriteFunc_t write, const BlueOssSidStorage_t *const pStorage);

    BlueReturnCode_t (*unprovision)(BlueOssSidStorageContext_t *pContext);

    BlueReturnCode_t (*format)(BlueOssSidStorageContext_t *pContext, bool factoryReset);

    BlueReturnCode_t (*read)(BlueOssSidStorageContext_t *pContext, uint8_t *const pData, uint16_t dataSize);

    BlueReturnCode_t (*write)(BlueOssSidStorageContext_t *pContext, const uint8_t *const pData, uint16_t dataSize);
} BlueOssSidStorageVTable_t;

typedef struct BlueOssSidStorage
{
    const BlueOssSidStorageVTable_t *pFuncs;
    BlueOssSidStorageContext_t *pContext;
} BlueOssSidStorage_t;

typedef void BlueOssSidProcessContext_t;

//
// Blue Oss So handler for processing
//

typedef struct BlueOssSidProcessVTable_t
{
    BlueReturnCode_t (*validateProprietaryCredentialType)(BlueOssSidStorageContext_t *pContext, const BlueOssSidCredentialTypeProprietary_t *const pCredentialType, const BlueCredentialId_t *const pCredentialId, BlueOssAccessResult_t *const pAccessResult);
    BlueReturnCode_t (*validateOssCredentialType)(BlueOssSidStorageContext_t *pContext, const BlueOssSidCredentialTypeOss_t *const pCredentialType, const BlueCredentialId_t *const pCredentialId, BlueOssAccessResult_t *const pAccessResult);
    BlueOssGrantAccessFunc_t grantAccess;
    BlueOssDenyAccessFunc_t denyAccess;
} BlueOssSidProcessVTable_t;

typedef struct BlueOssSidProcess
{
    const BlueOssSidProcessVTable_t *pFuncs;
    BlueOssSidProcessContext_t *pContext;
} BlueOssSidProcess_t;

#ifdef __cplusplus
extern "C"
{
#endif

    //
    // -- Reading --
    //

    BlueReturnCode_t blueOssSid_ReadCredentialType(uint8_t credentialTypeEncoded, BlueOssSidCredentialType_t *const pCredentialType);

    BlueReturnCode_t blueOssSid_ReadInfoFile(const BlueOssSidStorage_t *const pStorage, BlueOssSidFileInfo_t *const pInfoFile);

    //
    // -- Writing --
    //

    BlueReturnCode_t blueOssSid_WriteCredentialType(uint8_t *const credentialTypeEncoded, const BlueOssSidCredentialType_t *const pCredentialType);

    BlueReturnCode_t blueOssSid_WriteInfoFile(const BlueOssSidStorage_t *const pStorage, const BlueOssSidFileInfo_t *const pInfoFile);

    //
    // -- Processing --
    //

    BlueReturnCode_t blueOssSid_GetStorage(BlueTransponderType_t transponderType, BlueOssSidStorage_t *const pStorage, const BlueOssSidSettings_t *const pSettings, uint8_t *const pOutput, uint16_t *const pOutputSize);
    BlueReturnCode_t blueOssSid_GetStorage_Ext(BlueTransponderType_t transponderType, BlueOssSidStorage_t *const pStorage, const uint8_t *const pSettingsBuffer, uint16_t settingsBufferSize, uint8_t *const pOutput, uint16_t *const pOutputSize);
    BlueReturnCode_t blueOssSid_GetStorageProfile(const BlueOssSidStorage_t *const pStorage, const BlueOssSidProvisioningConfiguration_t *const pProvisioningConfig, BlueOssSidStorageProfile_t *const pProfile);
    BlueReturnCode_t blueOssSid_GetStorageProfile_Ext(const BlueOssSidStorage_t *const pStorage, const uint8_t *const pConfigBuffer, uint16_t configBufferSize, uint8_t *const pProfileBuffer, uint16_t profileBufferSize);
    BlueReturnCode_t blueOssSid_IsProvisioned(const BlueOssSidStorage_t *const pStorage);
    BlueReturnCode_t blueOssSid_Provision(const BlueOssSidStorage_t *const pStorage, const BlueOssSidProvisioningData_t *const pData);
    BlueReturnCode_t blueOssSid_Provision_Ext(const BlueOssSidStorage_t *const pStorage, const uint8_t *const pDataBuffer, uint16_t dataBufferSize);
    BlueReturnCode_t blueOssSid_Unprovision(const BlueOssSidStorage_t *const pStorage);
    BlueReturnCode_t blueOssSid_Format(const BlueOssSidStorage_t *const pStorage, bool factoryReset);
    BlueReturnCode_t blueOssSid_ReadConfiguration(const BlueOssSidStorage_t *const pStorage, BlueOssSidConfiguration_t *const pConfiguration);
    BlueReturnCode_t blueOssSid_ReadConfiguration_Ext(const BlueOssSidStorage_t *const pStorage, uint8_t *const pConfigurationBuffer, uint16_t configurationBufferSize);
    BlueReturnCode_t blueOssSid_ProcessAccess(const BlueOssSidStorage_t *const pStorage, const BlueOssSidProcess_t *const pProcess, BlueOssAccessResult_t *const pAccessResult);

#ifdef __cplusplus
}
#endif

#endif
