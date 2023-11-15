#ifndef BLUE_OSS_SO_H
#define BLUE_OSS_SO_H

#include "core/oss/BlueOss.h"

extern const BlueOssSoVersion_t *const blueOssSoVersion;

typedef struct BlueOssSoStorage BlueOssSoStorage_t;

//
// Blue Oss So storage reading / writing
//

typedef BlueReturnCode_t (*BlueOssSoStorageProvisionWriteFunc_t)(const BlueOssSoProvisioningData_t *const pData, const BlueOssSoStorage_t *const pStorage);

typedef void BlueOssSoStorageContext_t;

typedef struct BlueOssSoStorageVTable_t
{
    BlueReturnCode_t (*getDefaultProvisioningConfiguration)(BlueOssSoStorageContext_t *pContext, BlueOssSoProvisioningConfiguration_t *const pProvisioningConfig);

    BlueReturnCode_t (*getStorageProfile)(BlueOssSoStorageContext_t *pContext, const BlueOssSoProvisioningConfiguration_t *const pProvisioningConfig, BlueOssSoStorageProfile_t *const pProfile);

    BlueReturnCode_t (*prepare)(BlueOssSoStorageContext_t *pContext, BlueOssPrepareMode_t prepareMode);

    BlueReturnCode_t (*provision)(BlueOssSoStorageContext_t *pContext, const BlueOssSoProvisioningData_t *const pData, BlueOssSoStorageProvisionWriteFunc_t write, const BlueOssSoStorage_t *const pStorage);

    BlueReturnCode_t (*unprovision)(BlueOssSoStorageContext_t *pContext);

    BlueReturnCode_t (*format)(BlueOssSoStorageContext_t *pContext, bool factoryReset);

    BlueReturnCode_t (*read)(BlueOssSoStorageContext_t *pContext, BlueOssSoFileId_t fileId, uint16_t offset, uint8_t *const pData, uint16_t dataSize);

    BlueReturnCode_t (*write)(BlueOssSoStorageContext_t *pContext, BlueOssSoFileId_t fileId, uint16_t offset, const uint8_t *const pData, uint16_t dataSize);

    BlueReturnCode_t (*writeEvent)(BlueOssSoStorageContext_t *pContext, const uint8_t *const pEvent, uint16_t eventSize);
} BlueOssSoStorageVTable_t;

typedef struct BlueOssSoStorage
{
    const BlueOssSoStorageVTable_t *pFuncs;
    BlueOssSoStorageContext_t *pContext;
} BlueOssSoStorage_t;

typedef void BlueOssSoProcessContext_t;

//
// Blue Oss So handler for processing
//

typedef struct BlueOssSoProcessPendingEventQuery
{
    const BlueCredentialId_t *const pCredentialId;
    BlueOssSoEvent_t startEvent;
    const uint8_t *const pEventIds;
    uint16_t eventIdsCount;
    uint8_t maxEvents;
} BlueOssSoProcessPendingEventQuery_t;

typedef struct BlueOssSoProcessVTable_t
{
    BlueReturnCode_t (*processProprietaryCredentialType)(BlueOssSoProcessContext_t *pContext, const BlueOssSoCredentialTypeProprietary_t *const pCredentialType);
    BlueReturnCode_t (*verifyCredentialIdIsNotBlacklisted)(BlueOssSoProcessContext_t *pContext, const BlueCredentialId_t *const pCredentialId, bool *const pIsBlacklisted);
    BlueReturnCode_t (*updateBlacklist)(BlueOssSoProcessContext_t *pContext, const BlueBlacklistEntry_t *const pEntries, uint16_t entriesCount);
    BlueReturnCode_t (*queryPendingEvents)(BlueOssSoProcessContext_t *pContext, const BlueOssSoProcessPendingEventQuery_t *const eventQuery, BlueOssSoEvent_t *const pEvents, uint8_t *const pEventsCount);
    void (*storeEvent)(BlueOssSoProcessContext_t *pContext, const BlueOssSoEvent_t *const pEvent, const BlueCredentialId_t *const pCredentialId);
    BlueOssGrantAccessFunc_t grantAccess;
    BlueOssDenyAccessFunc_t denyAccess;
} BlueOssSoProcessVTable_t;

typedef BlueReturnCode_t (*BlueOssSoGetGroupSchedulesFunc_t)(uint8_t groupId, BlueLocalTimeSchedule_t *pSchedules, uint8_t *pSchedulesCount, uint8_t maxSchedulesCount);

typedef struct BlueOssSoProcessConfig
{
    uint16_t siteId;
    uint16_t doorId;
    BlueOssSoGetGroupSchedulesFunc_t getGroupSchedules;
    bool writePendingEvents;
    bool updateFromBlacklist;
    bool timestampIsInvalid;
} BlueOssSoProcessConfig_t;

typedef struct BlueOssSoProcess
{
    BlueOssSoProcessConfig_t config;
    const BlueOssSoProcessVTable_t *pFuncs;
    BlueOssSoProcessContext_t *pContext;
} BlueOssSoProcess_t;

typedef enum BlueOssSoReadWriteFlags
{
    BlueOssSoReadWriteFlags_Info = 1 << BlueOssSoFileId_Info,
    BlueOssSoReadWriteFlags_Data = 1 << BlueOssSoFileId_Data,
    BlueOssSoReadWriteFlags_Event = 1 << BlueOssSoFileId_Event,
    BlueOssSoReadWriteFlags_Blacklist = 1 << BlueOssSoFileId_Blacklist,
    BlueOssSoReadWriteFlags_CustomerExtensions = 1 << BlueOssSoFileId_CustomerExtensions,
    // --
    BlueOssSoReadWriteFlags_DataBlacklist = BlueOssSoReadWriteFlags_Data | BlueOssSoReadWriteFlags_Blacklist,
    BlueOssSoReadWriteFlags_AllNoEvents = BlueOssSoReadWriteFlags_Info | BlueOssSoReadWriteFlags_Data | BlueOssSoReadWriteFlags_Blacklist | BlueOssSoReadWriteFlags_CustomerExtensions,
    BlueOssSoReadWriteFlags_All = BlueOssSoReadWriteFlags_Info | BlueOssSoReadWriteFlags_Data | BlueOssSoReadWriteFlags_Event | BlueOssSoReadWriteFlags_Blacklist | BlueOssSoReadWriteFlags_CustomerExtensions,
} BlueOssSoReadWriteFlags_t;

#define BLUE_OSSSO_EXTFEATURE_VALIDITY_START_TAG 0x01

#ifdef __cplusplus
extern "C"
{
#endif

    //
    // -- Utils --
    //

    void blueOssSo_GetDataFileSizes(const BlueOssSoFileData_t *const pDataFile, uint8_t *const doorInfoSize, uint8_t *const dtScheduleSize, uint16_t *const doorInfoTotalSize, uint16_t *const dtScheduleTotalSize);
    void blueOssSo_GetEventFileSizes(const BlueOssSoFileEvent_t *const pEventFile, uint8_t *const eventSize, uint16_t *const eventTotalSize);
    void blueOssSo_GetBlacklistFileSizes(const BlueOssSoFileBlacklist_t *const pBlacklistFile, uint8_t *const entrySize, uint16_t *const entryTotalSize);

    //
    // -- Validating --
    //

    BlueReturnCode_t blueOssSo_ValidateTimestamp(const BlueLocalTimestamp_t *const pTimestamp);
    BlueReturnCode_t blueOssSo_ValidateTimeperiod(const BlueLocalTimeperiod_t *const pTimeperiod);
    BlueReturnCode_t blueOssSo_ValidateDoorInfo(const BlueOssSoDoorInfo_t *const pDoorInfo, uint8_t timeOffsetPeriodsCount);
    BlueReturnCode_t blueOssSo_ValidateDataFile(const BlueOssSoFileData_t *const pDataFile);

    //
    // -- Reading --
    //

    BlueReturnCode_t blueOssSo_ReadTimestamp(const uint8_t *const pData, BlueLocalTimestamp_t *const pTimestamp);
    BlueReturnCode_t blueOssSo_ReadTimeperiod(const uint8_t *const pData, BlueLocalTimeperiod_t *const pTimeperiod);
    BlueReturnCode_t blueOssSo_ReadCredentialType(uint8_t credentialTypeEncoded, BlueOssSoCredentialType_t *const pCredentialType);
    BlueReturnCode_t blueOssSo_ReadDoorInfo(const uint8_t *const pData, BlueOssSoDoorInfo_t *const pDoorInfo, uint8_t timeOffsetPeriodsCount);
    BlueReturnCode_t blueOssSo_ReadDTSchedule(const uint8_t *const pData, BlueOssSoDTSchedule_t *const pDTSchedule, uint8_t dayIdsCount, uint8_t timePeriodsCount);
    BlueReturnCode_t blueOssSo_ReadEvent(const uint8_t *const pData, BlueOssSoEvent_t *const pEvent);
    BlueReturnCode_t blueOssSo_ReadBlacklistEntry(const uint8_t *const pData, BlueBlacklistEntry_t *const pBlacklistEntry);
    BlueReturnCode_t blueOssSo_ReadExtFeature(const uint8_t *const pData, BlueOssSoExtFeature_t *const pExtFeature, uint16_t pDataSize, uint16_t *const pBytesRead);

    BlueReturnCode_t blueOssSo_ReadInfoFile(const BlueOssSoStorage_t *const pStorage, BlueOssSoFileInfo_t *const pInfoFile);
    BlueReturnCode_t blueOssSo_ReadDataFile(const BlueOssSoStorage_t *const pStorage, BlueOssSoFileData_t *const pDataFile);
    BlueReturnCode_t blueOssSo_ReadEventFile(const BlueOssSoStorage_t *const pStorage, BlueOssSoFileEvent_t *const pEventFile, bool readEvents, uint8_t maxEventEntries);
    BlueReturnCode_t blueOssSo_ReadBlacklistFile(const BlueOssSoStorage_t *const pStorage, BlueOssSoFileBlacklist_t *const pBlacklistFile, uint8_t maxBlacklistEntries);
    BlueReturnCode_t blueOssSo_ReadCustomerExtensionsFile(const BlueOssSoStorage_t *const pStorage, BlueOssSoFileCustomerExtensions_t *const pCustomerExtensionsFile);

    //
    // -- Writing --
    //

    BlueReturnCode_t blueOssSo_WriteTimestamp(uint8_t *const pData, const BlueLocalTimestamp_t *const pTimestamp);
    BlueReturnCode_t blueOssSo_WriteTimeperiod(uint8_t *const pData, const BlueLocalTimeperiod_t *const pTimeperiod);
    BlueReturnCode_t blueOssSo_WriteCredentialType(uint8_t *const credentialTypeEncoded, const BlueOssSoCredentialType_t *const pCredentialType);
    BlueReturnCode_t blueOssSo_WriteDoorInfo(uint8_t *const pData, const BlueOssSoDoorInfo_t *const pDoorInfo, uint8_t timeOffsetPeriodsCount);
    BlueReturnCode_t blueOssSo_WriteDTSchedule(uint8_t *const pData, const BlueOssSoDTSchedule_t *const pDTSchedule, uint8_t dayIdsCount, uint8_t timePeriodsCount);
    BlueReturnCode_t blueOssSo_WriteEvent(uint8_t *const pData, const BlueOssSoEvent_t *const pEvent);
    BlueReturnCode_t blueOssSo_WriteBlacklistEntry(uint8_t *const pData, const BlueBlacklistEntry_t *const pBlacklistEntry);
    BlueReturnCode_t blueOssSo_WriteExtFeature(uint8_t *const pData, const BlueOssSoExtFeature_t *const pExtFeature, uint16_t *const pBytesWritten);

    BlueReturnCode_t blueOssSo_WriteInfoFile(const BlueOssSoStorage_t *const pStorage, const BlueOssSoFileInfo_t *const pInfoFile);
    BlueReturnCode_t blueOssSo_WriteDataFile(const BlueOssSoStorage_t *const pStorage, const BlueOssSoFileData_t *const pDataFile);
    BlueReturnCode_t blueOssSo_WriteEventFile(const BlueOssSoStorage_t *const pStorage, const BlueOssSoFileEvent_t *const pEventFile, uint8_t maxEventEntries);
    BlueReturnCode_t blueOssSo_WriteBlacklistFile(const BlueOssSoStorage_t *const pStorage, const BlueOssSoFileBlacklist_t *const pBlacklistFile, uint8_t maxBlacklistEntries);
    BlueReturnCode_t blueOssSo_WriteCustomerExtensionsFile(const BlueOssSoStorage_t *const pStorage, const BlueOssSoFileCustomerExtensions_t *const pCustomerExtensionsFile);

    //
    // -- Processing --
    //

    bool blueOssSo_HasDTScheduleAccess(const BlueLocalTimestamp_t *const pTimestamp, const BlueOssSoDTSchedule_t *const pDTSchedule, BlueLocalTimestamp_t *const pScheduleEndTime);
    BlueReturnCode_t blueOssSo_EvaluateAccess(const BlueLocalTimestamp_t *const pTimestamp, const BlueOssSoProcessConfig_t *const pConfig, const BlueOssSoFileData_t *const pDataFile, BlueOssAccessResult_t *const pResult);

    BlueReturnCode_t blueOssSo_WritePendingEvents(const BlueOssSoStorage_t *const pStorage, const BlueOssSoProcess_t *const pProcess, const BlueOssSoFileInfo_t *const pInfoFile);
    BlueReturnCode_t blueOssSo_UpdateFromBlacklist(const BlueOssSoStorage_t *const pStorage, const BlueOssSoProcess_t *const pProcess, const BlueOssSoFileInfo_t *const pInfoFile);

    BlueReturnCode_t blueOssSo_GetStorage(BlueTransponderType_t transponderType, BlueOssSoStorage_t *const pStorage, const BlueOssSoSettings_t *const pSettings, uint8_t *const pOutput, uint16_t *const pOutputSize);
    BlueReturnCode_t blueOssSo_GetStorage_Ext(BlueTransponderType_t transponderType, BlueOssSoStorage_t *const pStorage, const uint8_t *const pSettingsBuffer, uint16_t settingsBufferSize, uint8_t *const pOutput, uint16_t *const pOutputSize);
    BlueReturnCode_t blueOssSo_GetStorageProfile(const BlueOssSoStorage_t *const pStorage, const BlueOssSoProvisioningConfiguration_t *const pProvisioningConfig, BlueOssSoStorageProfile_t *const pProfile);
    BlueReturnCode_t blueOssSo_GetStorageProfile_Ext(const BlueOssSoStorage_t *const pStorage, const uint8_t *const pConfigBuffer, uint16_t configBufferSize, uint8_t *const pProfileBuffer, uint16_t profileBufferSize);
    BlueReturnCode_t blueOssSo_Format(const BlueOssSoStorage_t *const pStorage, bool factoryReset);
    BlueReturnCode_t blueOssSo_IsProvisioned(const BlueOssSoStorage_t *const pStorage);
    BlueReturnCode_t blueOssSo_Provision(const BlueOssSoStorage_t *const pStorage, const BlueOssSoProvisioningData_t *const pData);
    BlueReturnCode_t blueOssSo_Provision_Ext(const BlueOssSoStorage_t *const pStorage, const uint8_t *const pDataBuffer, uint16_t dataBufferSize);
    BlueReturnCode_t blueOssSo_Unprovision(const BlueOssSoStorage_t *const pStorage);
    BlueReturnCode_t blueOssSo_ReadConfiguration(const BlueOssSoStorage_t *const pStorage, BlueOssSoConfiguration_t *const pConfiguration, BlueOssSoReadWriteFlags_t readFlags);
    BlueReturnCode_t blueOssSo_ReadConfiguration_Ext(const BlueOssSoStorage_t *const pStorage, uint8_t *const pConfigurationBuffer, uint16_t configurationBufferSize, BlueOssSoReadWriteFlags_t readFlags);
    BlueReturnCode_t blueOssSo_WriteConfiguration(const BlueOssSoStorage_t *const pStorage, const BlueOssSoConfiguration_t *const pConfiguration, BlueOssSoReadWriteFlags_t writeFlags);
    BlueReturnCode_t blueOssSo_WriteConfiguration_Ext(const BlueOssSoStorage_t *const pStorage, const uint8_t *const pConfigurationBuffer, uint16_t configurationBufferSize, BlueOssSoReadWriteFlags_t writeFlags);
    BlueReturnCode_t blueOssSo_UpdateConfiguration(const BlueOssSoStorage_t *const pStorage, const BlueOssSoConfiguration_t *const pConfiguration, bool clearEvents);
    BlueReturnCode_t blueOssSo_UpdateConfiguration_Ext(const BlueOssSoStorage_t *const pStorage, const uint8_t *const pConfigurationBuffer, uint16_t configurationBufferSize, bool clearEvents);

    BlueReturnCode_t blueOssSo_ProcessAccess(const BlueLocalTimestamp_t *const pTimestamp, const BlueOssSoStorage_t *const pStorage, const BlueOssSoProcess_t *const pProcess, BlueOssAccessResult_t *const pAccessResult);

#ifdef __cplusplus
}
#endif

#endif
