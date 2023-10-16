#include "core/BlueLog.h"
#include "core/BlueUtils.h"

#include "core/oss/BlueOssSo.h"
#include "core/oss/BlueOssSoMobile.h"
#include "core/oss/BlueOssSoMifareDesfire.h"

static BlueReturnCode_t provisionWrite(const BlueOssSoProvisioningData_t *const pData, const BlueOssSoStorage_t *const pStorage);
static BlueReturnCode_t writeConfiguration(const BlueOssSoStorage_t *const pStorage, const BlueOssSoConfiguration_t *const pConfiguration, BlueOssSoReadWriteFlags_t writeFlags);

//
// -- Utils --
//

void blueOssSo_GetDataFileSizes(const BlueOssSoFileData_t *const pDataFile, uint8_t *const doorInfoSize, uint8_t *const dtScheduleSize, uint16_t *const doorInfoTotalSize, uint16_t *const dtScheduleTotalSize)
{
    *doorInfoSize = 3;
    *dtScheduleSize = ((4 * pDataFile->numberOfTimePeriodsPerDayId + 1) * pDataFile->numberOfDayIdsPerDTSchedule);
    *doorInfoTotalSize = pDataFile->doorInfoEntries_count * (*doorInfoSize);
    *dtScheduleTotalSize = pDataFile->dtSchedules_count * (*dtScheduleSize);
}

void blueOssSo_GetEventFileSizes(const BlueOssSoFileEvent_t *const pEventFile, uint8_t *const eventSize, uint16_t *const eventTotalSize)
{
    *eventSize = 10;
    *eventTotalSize = pEventFile->events_count * (*eventSize);
}

void blueOssSo_GetBlacklistFileSizes(const BlueOssSoFileBlacklist_t *const pBlacklistFile, uint8_t *const entrySize, uint16_t *const entryTotalSize)
{
    *entrySize = 16;
    *entryTotalSize = pBlacklistFile->entries_count * (*entrySize);
}

//
// -- Validating --
//

BlueReturnCode_t blueOssSo_ValidateTimestamp(const BlueLocalTimestamp_t *const pTimestamp)
{
    // 0'd timestamp is taken as "valid" and must handled seperately
    if (pTimestamp->year == 0 && pTimestamp->month == 0 && pTimestamp->date == 0 && pTimestamp->hours == 0 && pTimestamp->minutes == 0)
    {
        return BlueReturnCode_Ok;
    }

    if (pTimestamp->month < 1 || pTimestamp->month > 12)
    {
        return BlueReturnCode_OssSoInvalidTimestamp;
    }

    if (pTimestamp->hours > 23)
    {
        return BlueReturnCode_OssSoInvalidTimestamp;
    }

    if (pTimestamp->minutes > 59)
    {
        return BlueReturnCode_OssSoInvalidTimestamp;
    }

    if (pTimestamp->seconds > 59)
    {
        return BlueReturnCode_OssSoInvalidTimestamp;
    }

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_ValidateTimeperiod(const BlueLocalTimeperiod_t *const pTimeperiod)
{
    // 0'd timeperiod is taken as "valid" and must handled seperately
    if (pTimeperiod->hoursFrom == 0 && pTimeperiod->minutesFrom == 0 &&
        pTimeperiod->hoursTo == 0 && pTimeperiod->minutesTo == 0)
    {
        return BlueReturnCode_Ok;
    }

    if (pTimeperiod->hoursFrom >= 24 || pTimeperiod->minutesFrom >= 59)
    {
        return BlueReturnCode_OssSoInvalidTimeperiod;
    }

    if (pTimeperiod->hoursTo == 0 || pTimeperiod->hoursTo > 24 || pTimeperiod->minutesTo >= 59)
    {
        return BlueReturnCode_OssSoInvalidTimeperiod;
    }

    if (pTimeperiod->hoursTo == 24 && pTimeperiod->minutesTo > 0)
    {
        return BlueReturnCode_OssSoInvalidTimeperiod;
    }

    const uint16_t timeFrom = pTimeperiod->hoursFrom * 60 + pTimeperiod->minutesFrom;
    const uint16_t timeTo = pTimeperiod->hoursTo * 60 + pTimeperiod->minutesTo;

    if (timeTo < timeFrom || timeTo == timeFrom)
    {
        return BlueReturnCode_OssSoInvalidTimeperiod;
    }

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_ValidateDoorInfo(const BlueOssSoDoorInfo_t *const pDoorInfo, uint8_t dtSchedulesCount)
{
    if (pDoorInfo->accessBy != BlueOssSoDoorInfoAccessBy_DoorGroupId && pDoorInfo->accessBy != BlueOssSoDoorInfoAccessBy_DoorId)
    {
        return BlueReturnCode_OssSoInvalidDoorAccessBy;
    }

    if (pDoorInfo->dtScheduleNumber > dtSchedulesCount)
    {
        return BlueReturnCode_OssSoInvalidDoorDTScheduleNumber;
    }

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_ValidateDataFile(const BlueOssSoFileData_t *const pDataFile)
{
    if (pDataFile->siteId < 1)
    {
        BLUE_LOG_DEBUG("Invalid siteId %d", pDataFile->siteId);
        return BlueReturnCode_OssSoInvalidSiteId;
    }

    for (uint8_t doorIndex = 0; doorIndex < pDataFile->doorInfoEntries_count; doorIndex += 1)
    {
        const uint8_t dtScheduleNumber = (uint8_t)pDataFile->doorInfoEntries[doorIndex].dtScheduleNumber;
        if (dtScheduleNumber > 0 && dtScheduleNumber > pDataFile->dtSchedules_count)
        {
            return BlueReturnCode_OssSoInvalidDTScheduleNumber;
        }
    }

    return BlueReturnCode_Ok;
}

//
// -- Reading --
//

BlueReturnCode_t blueOssSo_ReadTimestamp(const uint8_t *const pData, BlueLocalTimestamp_t *const pTimestamp)
{
    pTimestamp->year = blueOss_DecodePackedBCD(&pData[0], sizeof(uint16_t));
    pTimestamp->month = blueOss_DecodePackedBCD(&pData[2], sizeof(uint8_t));
    pTimestamp->date = blueOss_DecodePackedBCD(&pData[3], sizeof(uint8_t));
    pTimestamp->hours = blueOss_DecodePackedBCD(&pData[4], sizeof(uint8_t));
    pTimestamp->minutes = blueOss_DecodePackedBCD(&pData[5], sizeof(uint8_t));
    pTimestamp->seconds = 0;

    return blueOssSo_ValidateTimestamp(pTimestamp);
}

BlueReturnCode_t blueOssSo_ReadTimeperiod(const uint8_t *const pData, BlueLocalTimeperiod_t *const pTimeperiod)
{
    pTimeperiod->hoursFrom = blueOss_DecodePackedBCD(&pData[0], sizeof(uint8_t));
    pTimeperiod->minutesFrom = blueOss_DecodePackedBCD(&pData[1], sizeof(uint8_t));
    pTimeperiod->hoursTo = blueOss_DecodePackedBCD(&pData[2], sizeof(uint8_t));
    pTimeperiod->minutesTo = blueOss_DecodePackedBCD(&pData[3], sizeof(uint8_t));

    return blueOssSo_ValidateTimeperiod(pTimeperiod);
}

BlueReturnCode_t blueOssSo_ReadCredentialType(uint8_t credentialTypeEncoded, BlueOssSoCredentialType_t *const pCredentialType)
{
    uint8_t bits[8];
    blueOss_DecodeBits(credentialTypeEncoded, bits);

    if (bits[7] == 0)
    {
        pCredentialType->typeSource = BlueOssCredentialTypeSource_Oss;
        pCredentialType->has_oss = true;
        pCredentialType->oss = (BlueOssSoCredentialTypeOss_t){
            .credential = (BlueOssSoCredentialTypeOssCredential_t)bits[0],
        };

        return BlueReturnCode_Ok;
    }
    else if (bits[7] == 1)
    {
        pCredentialType->typeSource = BlueOssCredentialTypeSource_Proprietary;
        pCredentialType->has_proprietary = true;
        pCredentialType->proprietary = (BlueOssSoCredentialTypeProprietary_t){
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

    return BlueReturnCode_OssSoInvalidCredentialType;
}

BlueReturnCode_t blueOssSo_ReadDoorInfo(const uint8_t *const pData, BlueOssSoDoorInfo_t *const pDoorInfo, uint8_t dtSchedulesCount)
{
    pDoorInfo->id = BLUE_UINT16_READ_BE(&pData[0]);

    uint8_t settingBits[8];
    blueOss_DecodeBits(pData[2], settingBits);

    pDoorInfo->dtScheduleNumber = blueOss_DecodeBinaryNumber(settingBits, 7, 4);

    pDoorInfo->accessBy = settingBits[3];

    if (settingBits[2] == 1)
    {
        pDoorInfo->accessType = BlueAccessType_Toggle;
    }
    else if (settingBits[1] == 1)
    {
        pDoorInfo->accessType = BlueAccessType_ExtendedTime;
    }
    else
    {
        pDoorInfo->accessType = BlueAccessType_DefaultTime;
    }

    return blueOssSo_ValidateDoorInfo(pDoorInfo, dtSchedulesCount);
}

BlueReturnCode_t blueOssSo_ReadDTSchedule(const uint8_t *const pData, BlueOssSoDTSchedule_t *const pDTSchedule, uint8_t dayIdsCount, uint8_t timePeriodsCount)
{
    const BlueLocalTimeperiod_t zeroTimePeriod = BLUELOCALTIMEPERIOD_INIT_ZERO;

    pDTSchedule->days_count = dayIdsCount;

    uint8_t offset = 0;

    for (uint8_t dayIndex = 0; dayIndex < dayIdsCount; dayIndex += 1)
    {
        BlueOssSoDTScheduleDay_t *const day = &pDTSchedule->days[dayIndex];

        // Read weekdays, our BlueWeekday_t is compatible with the bitset so we can simply assign it
        uint8_t weekdaysBits[8];
        blueOss_DecodeBits(pData[offset], weekdaysBits);

        for (uint8_t weekday = BlueWeekday_Monday; weekday <= BlueWeekday_Sunday; weekday += 1)
        {
            day->weekdays[weekday] = weekdaysBits[weekday] == 1 ? true : false;
        }

        offset += 1;

        bool foundZeroTime = false;

        // Read time period(s)
        day->timePeriods_count = 0;

        for (uint8_t timePeriodIndex = 0; timePeriodIndex < timePeriodsCount; timePeriodIndex += 1)
        {
            BlueLocalTimeperiod_t timePeriod = BLUELOCALTIMEPERIOD_INIT_ZERO;

            if (!foundZeroTime)
            {
                BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadTimeperiod(&pData[offset], &timePeriod), "Read DTSchedule Timeperiod");

                if (memcmp(&timePeriod, &zeroTimePeriod, sizeof(BlueLocalTimeperiod_t)) == 0)
                {
                    // Spec says we shall stop parsing on first occurance of a zero timestamp per day
                    foundZeroTime = true;
                }
                else
                {
                    memcpy(&day->timePeriods[timePeriodIndex], &timePeriod, sizeof(BlueLocalTimeperiod_t));
                    day->timePeriods_count += 1;
                }
            }

            offset += 4;
        }
    }

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_ReadEvent(const uint8_t *const pData, BlueOssSoEvent_t *const pEvent)
{
    BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadTimestamp(&pData[0], &pEvent->eventTime), "Read event time");

    pEvent->doorId = BLUE_UINT16_READ_BE(&pData[6]);
    pEvent->eventId = pData[8];
    pEvent->eventInfo = pData[9];

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_ReadBlacklistEntry(const uint8_t *const pData, BlueBlacklistEntry_t *const pBlacklistEntry)
{
    BLUE_ERROR_CHECK_DEBUG(blueOss_ReadCredentialId(&pData[0], &pBlacklistEntry->credentialId), "Read blacklist entry credential");
    BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadTimestamp(&pData[10], &pBlacklistEntry->expiresAt), "Read blacklist entry expiry time");

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_ReadExtFeature(const uint8_t *const pData, BlueOssSoExtFeature_t *const pExtFeature, uint16_t dataSize, uint16_t *const pBytesRead)
{
    const uint8_t *dataPtr = pData;

    uint8_t tagSize = 0;

    if (dataPtr[0] == 0x82)
    {
        if (dataSize < 3)
        {
            return BlueReturnCode_Overflow;
        }

        pExtFeature->tag = BLUE_UINT16_READ_BE(&pData[1]);
        tagSize = 3;
    }
    else if (dataPtr[0] == 0x81)
    {
        if (dataSize < 2)
        {
            return BlueReturnCode_Overflow;
        }

        pExtFeature->tag = dataPtr[1];
        tagSize = 2;
    }
    else if (dataPtr[0] <= 0x7F)
    {
        pExtFeature->tag = dataPtr[0];
        tagSize = 1;
    }

    if (tagSize == 0 || pExtFeature->tag == 0)
    {
        return BlueReturnCode_OssSoInvalidExtensionTag;
    }

    dataPtr += tagSize;
    *pBytesRead += tagSize;
    dataSize -= tagSize;

    if (dataSize < 1)
    {
        return BlueReturnCode_Overflow;
    }

    uint8_t lengthSize = 0;
    uint16_t length = 0;

    if (dataPtr[0] == 0x82)
    {
        if (dataSize < 3)
        {
            return BlueReturnCode_Overflow;
        }

        length = BLUE_UINT16_READ_BE(&dataPtr[1]);
        lengthSize = 3;
    }
    else if (dataPtr[0] == 0x81)
    {
        if (dataSize < 2)
        {
            return BlueReturnCode_Overflow;
        }

        length = dataPtr[1];
        lengthSize = 2;
    }
    else if (dataPtr[0] <= 0x7F)
    {
        length = dataPtr[0];
        lengthSize = 1;
    }

    if (lengthSize == 0)
    {
        return BlueReturnCode_OssSoInvalidExtensionLength;
    }

    dataPtr += lengthSize;
    *pBytesRead += lengthSize;
    dataSize -= lengthSize;

    if (length > 0)
    {
        if (length > sizeof(pExtFeature->value.bytes))
        {
            return BlueReturnCode_OssSoExtensionValueTooLarge;
        }

        if (length > dataSize)
        {
            return BlueReturnCode_Overflow;
        }
    }

    memcpy(pExtFeature->value.bytes, dataPtr, length);
    pExtFeature->value.size = length;

    *pBytesRead += length;

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_ReadInfoFile(const BlueOssSoStorage_t *const pStorage, BlueOssSoFileInfo_t *const pInfoFile)
{
    uint8_t buffer[15];

    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->read(pStorage->pContext, BlueOssSoFileId_Info, 0, buffer, sizeof(buffer)), "Read info file");

    pInfoFile->versionMajor = buffer[0];
    pInfoFile->versionMinor = buffer[1];

    BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadCredentialType(buffer[2], &pInfoFile->credentialType), "Read info file CredentialType");
    BLUE_ERROR_CHECK_DEBUG(blueOss_ReadCredentialId(&buffer[3], &pInfoFile->credentialId), "Read info file CredentialId");

    pInfoFile->maxEventEntries = buffer[13];
    pInfoFile->maxBlacklistEntries = buffer[14];

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_ReadDataFile(const BlueOssSoStorage_t *const pStorage, BlueOssSoFileData_t *const pDataFile)
{
    const uint8_t headerSize = 16;
    uint8_t headerBuffer[headerSize]; // timestamp + siteId + dataFileHeader

    //
    // Read regular header
    //

    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->read(pStorage->pContext, BlueOssSoFileId_Data, 0, headerBuffer, sizeof(headerBuffer)), "Read header of data file");

    BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadTimestamp(&headerBuffer[0], &pDataFile->validity), "Read data file validity");

    pDataFile->siteId = BLUE_UINT16_READ_BE(&headerBuffer[6]);

    //
    // Read the DataFileHeader from header
    //

    uint8_t dtsBits[8];
    blueOss_DecodeBits(headerBuffer[9], dtsBits);
    pDataFile->dtSchedules_count = blueOss_DecodeBinaryNumber(dtsBits, 7, 4);
    pDataFile->numberOfDayIdsPerDTSchedule = blueOss_DecodeBinaryNumber(dtsBits, 3, 2) + 1;
    pDataFile->numberOfTimePeriodsPerDayId = blueOss_DecodeBinaryNumber(dtsBits, 1, 0) + 1;

    // Number of door entries
    pDataFile->doorInfoEntries_count = headerBuffer[10];

    // ExtensionsInfo
    uint8_t extensionsInfoBits[8];
    blueOss_DecodeBits(headerBuffer[11], extensionsInfoBits);
    pDataFile->hasExtensions = extensionsInfoBits[0] == 1;

    //
    // Get the DoorInfo and DTSchedule sizes and load them if any
    //

    uint8_t doorInfoSize = 0;
    uint8_t dtScheduleSize = 0;
    uint16_t doorInfoTotalSize = 0;
    uint16_t dtScheduleTotalSize = 0;

    blueOssSo_GetDataFileSizes(pDataFile, &doorInfoSize, &dtScheduleSize, &doorInfoTotalSize, &dtScheduleTotalSize);

    if (doorInfoTotalSize > 0 || dtScheduleTotalSize > 0)
    {
        uint8_t payloadBuffer[BLUE_MAX(doorInfoTotalSize, dtScheduleTotalSize)];

        //
        // Read door infos if any
        //
        if (doorInfoTotalSize > 0)
        {
            BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->read(pStorage->pContext, BlueOssSoFileId_Data, headerSize, payloadBuffer, doorInfoTotalSize), "Read data file payload for DoorInfos");

            for (uint8_t doorIndex = 0; doorIndex < pDataFile->doorInfoEntries_count; doorIndex += 1)
            {
                const uint16_t offset = doorIndex * doorInfoSize;
                BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadDoorInfo(&payloadBuffer[offset], &pDataFile->doorInfoEntries[doorIndex], pDataFile->dtSchedules_count), "Read data file DoorInfo");
            }
        }

        //
        // Read DTSchedules if any
        //
        if (dtScheduleTotalSize > 0)
        {
            BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->read(pStorage->pContext, BlueOssSoFileId_Data, headerSize + doorInfoTotalSize, payloadBuffer, dtScheduleTotalSize), "Read data file payload for DTSchedules");

            for (uint8_t dtScheduleIndex = 0; dtScheduleIndex < pDataFile->dtSchedules_count; dtScheduleIndex += 1)
            {
                const uint16_t offset = dtScheduleIndex * dtScheduleSize;
                BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadDTSchedule(&payloadBuffer[offset], &pDataFile->dtSchedules[dtScheduleIndex], pDataFile->numberOfDayIdsPerDTSchedule, pDataFile->numberOfTimePeriodsPerDayId), "Read data file DTSchedule");
            }
        }
    }

    return blueOssSo_ValidateDataFile(pDataFile);
}

BlueReturnCode_t blueOssSo_ReadEventFile(const BlueOssSoStorage_t *const pStorage, BlueOssSoFileEvent_t *const pEventFile, bool readEvents, uint8_t maxEventEntries)
{
    if (sizeof(pEventFile->supportedEventIds) != BlueEventId_MaxOssSoEventId - 1)
    {
        BLUE_LOG_DEBUG("Compiled with less eventIds than available.");
        return BlueReturnCode_InvalidState;
    }

    if (maxEventEntries == 0)
    {
        // Not support so leave early we have no events
        pEventFile->events_count = 0;

        return BlueReturnCode_Ok;
    }

    const uint8_t headerSize = 5;
    uint8_t headerBuffer[headerSize];

    //
    // Read regular header
    //

    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->read(pStorage->pContext, BlueOssSoFileId_Event, 0, headerBuffer, sizeof(headerBuffer)), "Read header of event file");

    const uint32_t eventConfig = BLUE_UINT32_READ_BE(&headerBuffer[0]);
    for (uint8_t eventId = 1; eventId < BlueEventId_MaxOssSoEventId - 1; eventId += 1)
    {
        pEventFile->supportedEventIds[eventId] = ((eventConfig >> (eventId - 1)) & 1) == 1 ? true : false;
    }

    const uint8_t eventsCount = headerBuffer[4];

    pEventFile->events_count = eventsCount;

    if (!readEvents)
    {
        // We don't want to read the events so we're done here
        return BlueReturnCode_Ok;
    }

    if (eventsCount > maxEventEntries)
    {
        return BlueReturnCode_OssSoMaxEventEntriesExceeded;
    }

    //
    // Read stored events now if any
    //
    uint8_t eventSize = 0;
    uint16_t eventTotalSize = 0;
    blueOssSo_GetEventFileSizes(pEventFile, &eventSize, &eventTotalSize);

    if (eventTotalSize > 0)
    {
        uint8_t payloadBuffer[eventTotalSize];

        BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->read(pStorage->pContext, BlueOssSoFileId_Event, headerSize, payloadBuffer, eventTotalSize), "Read event file payload for Events");

        for (uint8_t eventIndex = 0; eventIndex < pEventFile->events_count; eventIndex += 1)
        {
            const uint16_t offset = eventIndex * eventSize;
            BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadEvent(&payloadBuffer[offset], &pEventFile->events[eventIndex]), "Read event file Event");
        }
    }

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_ReadBlacklistFile(const BlueOssSoStorage_t *const pStorage, BlueOssSoFileBlacklist_t *const pBlacklistFile, uint8_t maxBlacklistEntries)
{
    if (maxBlacklistEntries == 0)
    {
        // Not support so leave early we have no blacklist
        pBlacklistFile->entries_count = 0;

        return BlueReturnCode_Ok;
    }

    const uint8_t headerSize = 1;
    uint8_t headerBuffer[headerSize];

    //
    // Read regular header
    //

    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->read(pStorage->pContext, BlueOssSoFileId_Blacklist, 0, headerBuffer, sizeof(headerBuffer)), "Read header of blacklist file");

    uint8_t entriesCount = headerBuffer[0];

    if (entriesCount > maxBlacklistEntries)
    {
        return BlueReturnCode_OssSoMaxBlacklistEntriesExceeded;
    }

    pBlacklistFile->entries_count = entriesCount;

    //
    // Read stored blacklist entries now if any
    //
    uint8_t entrySize = 0;
    uint16_t entryTotalSize = 0;
    blueOssSo_GetBlacklistFileSizes(pBlacklistFile, &entrySize, &entryTotalSize);

    if (entryTotalSize > 0)
    {
        uint8_t payloadBuffer[entryTotalSize];

        BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->read(pStorage->pContext, BlueOssSoFileId_Blacklist, headerSize, payloadBuffer, entryTotalSize), "Read blacklist file payload for BlacklistEntries");

        for (uint8_t entryIndex = 0; entryIndex < pBlacklistFile->entries_count; entryIndex += 1)
        {
            const uint16_t offset = entryIndex * entrySize;
            BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadBlacklistEntry(&payloadBuffer[offset], &pBlacklistFile->entries[entryIndex]), "Read blacklist file BlacklistEntry");
        }
    }

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_ReadCustomerExtensionsFile(const BlueOssSoStorage_t *const pStorage, BlueOssSoFileCustomerExtensions_t *const pCustomerExtensionsFile)
{
    const uint8_t headerSize = 2;
    uint8_t headerBuffer[headerSize];

    //
    // Read regular header
    //

    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->read(pStorage->pContext, BlueOssSoFileId_CustomerExtensions, 0, headerBuffer, sizeof(headerBuffer)), "Read header of customer extensions file");

    uint16_t fileSize = BLUE_UINT16_READ_BE(&headerBuffer[0]);

    if (fileSize < headerSize)
    {
        return BlueReturnCode_OssSoExtensionFileSizeInvalid;
    }

    fileSize -= headerSize;

    const uint16_t maxFeaturesCount = (sizeof(pCustomerExtensionsFile->extFeatures) / sizeof(pCustomerExtensionsFile->extFeatures[0]));
    const uint16_t maxFileSize = maxFeaturesCount * (3 + 3 + sizeof(pCustomerExtensionsFile->extFeatures[0].value.bytes));

    uint16_t extFeaturesCount = 0;
    BlueOssSoExtFeature_t extFeatures[maxFeaturesCount];

    if (fileSize > maxFileSize)
    {
        return BlueReturnCode_OssSoExtensionFileSizeTooLarge;
    }

    //
    // Read features if any into our temporary data
    //
    if (fileSize > 0)
    {

        uint8_t payloadBuffer[fileSize];

        BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->read(pStorage->pContext, BlueOssSoFileId_CustomerExtensions, headerSize, payloadBuffer, fileSize), "Read features of customer extensions file");

        uint32_t fileSizeRead = 0;

        while (fileSizeRead < fileSize)
        {
            uint16_t featureBytesRead = 0;
            BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadExtFeature(&payloadBuffer[fileSizeRead], &extFeatures[extFeaturesCount], fileSize - fileSizeRead, &featureBytesRead), "Read customer extension file ExtFeature");

            fileSizeRead += featureBytesRead;
            extFeaturesCount += 1;

            if (extFeaturesCount > maxFeaturesCount)
            {
                return BlueReturnCode_OssSoExtensionTooManyFeatures;
            }
        }
    }

    //
    // Try to iterate and handle known features. If the feature is not known then
    // place the raw feature data into extFeatures instead
    //
    pCustomerExtensionsFile->extFeatures_count = 0;

    for (uint16_t extFeatureIndex = 0; extFeatureIndex < extFeaturesCount; extFeatureIndex += 1)
    {
        const BlueOssSoExtFeature_t *const extFeature = &extFeatures[extFeatureIndex];

        if (extFeature->tag == BLUE_OSSSO_EXTFEATURE_VALIDITY_START_TAG)
        {
            pCustomerExtensionsFile->has_validityStart = true;
            pCustomerExtensionsFile->validityStart.isValid = false;

            if (extFeature->value.size == 6)
            {
                if (blueOssSo_ReadTimestamp(extFeature->value.bytes, &pCustomerExtensionsFile->validityStart.validityStartTime) == BlueReturnCode_Ok)
                {
                    pCustomerExtensionsFile->validityStart.isValid = true;
                }
            }
        }
        else
        {
            // Unknown tag so copy the feature over
            memcpy(&pCustomerExtensionsFile->extFeatures[pCustomerExtensionsFile->extFeatures_count], extFeature, sizeof(BlueOssSoExtFeature_t));
            pCustomerExtensionsFile->extFeatures_count += 1;
        }
    }

    return BlueReturnCode_Ok;
}

//
// -- Writing --
//

BlueReturnCode_t blueOssSo_WriteTimestamp(uint8_t *const pData, const BlueLocalTimestamp_t *const pTimestamp)
{
    BLUE_ERROR_CHECK(blueOssSo_ValidateTimestamp(pTimestamp));

    blueOss_EncodePackedBCD(&pData[0], pTimestamp->year, sizeof(uint16_t));
    blueOss_EncodePackedBCD(&pData[2], pTimestamp->month, sizeof(uint8_t));
    blueOss_EncodePackedBCD(&pData[3], pTimestamp->date, sizeof(uint8_t));
    blueOss_EncodePackedBCD(&pData[4], pTimestamp->hours, sizeof(uint8_t));
    blueOss_EncodePackedBCD(&pData[5], pTimestamp->minutes, sizeof(uint8_t));

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_WriteTimeperiod(uint8_t *const pData, const BlueLocalTimeperiod_t *const pTimeperiod)
{
    BLUE_ERROR_CHECK(blueOssSo_ValidateTimeperiod(pTimeperiod));

    blueOss_EncodePackedBCD(&pData[0], pTimeperiod->hoursFrom, sizeof(uint8_t));
    blueOss_EncodePackedBCD(&pData[1], pTimeperiod->minutesFrom, sizeof(uint8_t));
    blueOss_EncodePackedBCD(&pData[2], pTimeperiod->hoursTo, sizeof(uint8_t));
    blueOss_EncodePackedBCD(&pData[3], pTimeperiod->minutesTo, sizeof(uint8_t));

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_WriteCredentialType(uint8_t *const credentialTypeEncoded, const BlueOssSoCredentialType_t *const pCredentialType)
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
            return BlueReturnCode_OssSoInvalidCredentialType;
        }

        bits[7] = 0;

        const uint8_t credential = (uint8_t)pCredentialType->oss.credential;
        if (credential < _BLUEOSSSOCREDENTIALTYPEOSSCREDENTIAL_MIN || credential > _BLUEOSSSOCREDENTIALTYPEOSSCREDENTIAL_MAX)
        {
            return BlueReturnCode_OssSoInvalidCredentialType;
        }

        bits[0] = credential;

        *credentialTypeEncoded = blueOss_EncodeBits(bits);

        return BlueReturnCode_Ok;
    }
    else if (pCredentialType->typeSource == BlueOssCredentialTypeSource_Proprietary)
    {
        if (!pCredentialType->has_proprietary)
        {
            BLUE_LOG_DEBUG("No proprietary on credential type setup");
            return BlueReturnCode_OssSoInvalidCredentialType;
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

    return BlueReturnCode_OssSoInvalidCredentialType;
}

BlueReturnCode_t blueOssSo_WriteDoorInfo(uint8_t *const pData, const BlueOssSoDoorInfo_t *const pDoorInfo, uint8_t dtSchedulesCount)
{
    BLUE_ERROR_CHECK(blueOssSo_ValidateDoorInfo(pDoorInfo, dtSchedulesCount));

    BLUE_UINT16_WRITE_BE(&pData[0], pDoorInfo->id);

    uint8_t settingBits[8] =
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

    blueOss_EncodeBinaryNumber(settingBits, 7, 4, pDoorInfo->dtScheduleNumber);

    settingBits[3] = pDoorInfo->accessBy;

    if (pDoorInfo->accessType == BlueAccessType_Toggle)
    {
        settingBits[2] = 1;
    }
    else if (pDoorInfo->accessType == BlueAccessType_ExtendedTime)
    {
        settingBits[1] = 1;
    }

    pData[2] = blueOss_EncodeBits(settingBits);

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_WriteDTSchedule(uint8_t *const pData, const BlueOssSoDTSchedule_t *const pDTSchedule, uint8_t dayIdsCount, uint8_t timePeriodsCount)
{
    uint8_t offset = 0;

    for (uint8_t dayIndex = 0; dayIndex < dayIdsCount; dayIndex += 1)
    {
        BlueOssSoDTScheduleDay_t day = BLUEOSSSODTSCHEDULEDAY_INIT_ZERO;

        if (dayIndex < pDTSchedule->days_count)
        {
            memcpy(day.weekdays, pDTSchedule->days[dayIndex].weekdays, sizeof(day.weekdays));
            day.timePeriods_count = pDTSchedule->days[dayIndex].timePeriods_count;

            if (day.timePeriods_count > 0)
            {
                memcpy(day.timePeriods, pDTSchedule->days[dayIndex].timePeriods, day.timePeriods_count * sizeof(BlueLocalTimeperiod_t));
            }
        }

        // Write weekdays, our BlueWeekday_t is compatible with the bits so can simply use it
        uint8_t weekdaysBits[8] =
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

        for (uint8_t weekday = BlueWeekday_Monday; weekday <= BlueWeekday_Sunday; weekday += 1)
        {
            weekdaysBits[weekday] = day.weekdays[weekday] == true ? 1 : 0;
        }

        pData[offset] = blueOss_EncodeBits(weekdaysBits);

        offset += 1;

        // Write time period(s)
        for (uint8_t timePeriodIndex = 0; timePeriodIndex < timePeriodsCount; timePeriodIndex += 1)
        {
            BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteTimeperiod(&pData[offset], &day.timePeriods[timePeriodIndex]), "Write DTSChedule Timeperiod");
            offset += 4;
        }
    }

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_WriteEvent(uint8_t *const pData, const BlueOssSoEvent_t *const pEvent)
{
    BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteTimestamp(&pData[0], &pEvent->eventTime), "Write event time");

    BLUE_UINT16_WRITE_BE(&pData[6], pEvent->doorId);

    pData[8] = pEvent->eventId;
    pData[9] = pEvent->eventInfo;

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_WriteBlacklistEntry(uint8_t *const pData, const BlueBlacklistEntry_t *const pBlacklistEntry)
{
    BLUE_ERROR_CHECK_DEBUG(blueOss_WriteCredentialId(&pData[0], &pBlacklistEntry->credentialId), "Write blacklist entry credential");
    BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteTimestamp(&pData[10], &pBlacklistEntry->expiresAt), "Write blacklist entry expiry time");

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_WriteExtFeature(uint8_t *const pData, const BlueOssSoExtFeature_t *const pExtFeature, uint16_t *const pBytesWritten)
{
    if (pExtFeature->tag == 0 || pExtFeature->tag > 0xFFFF)
    {
        return BlueReturnCode_OssSoInvalidExtensionTag;
    }

    uint8_t *dataPtr = pData;

    if (pExtFeature->tag <= 0x7F)
    {
        dataPtr[0] = pExtFeature->tag;
        dataPtr += 1;
        *pBytesWritten += 1;
    }
    else if (pExtFeature->tag <= 0xFF)
    {
        dataPtr[0] = 0x81;
        dataPtr[1] = pExtFeature->tag;
        dataPtr += 2;
        *pBytesWritten += 2;
    }
    else
    {
        dataPtr[0] = 0x82;
        BLUE_UINT16_WRITE_BE(&dataPtr[1], pExtFeature->tag);
        dataPtr += 3;
        *pBytesWritten += 3;
    }

    if (pExtFeature->value.size <= 0x7F)
    {
        dataPtr[0] = pExtFeature->value.size;
        dataPtr += 1;
        *pBytesWritten += 1;
    }
    else if (pExtFeature->value.size <= 0xFF)
    {
        dataPtr[0] = 0x81;
        dataPtr[1] = pExtFeature->value.size;
        dataPtr += 2;
        *pBytesWritten += 2;
    }
    else
    {
        dataPtr[0] = 0x82;
        BLUE_UINT16_WRITE_BE(&dataPtr[1], pExtFeature->value.size);
        dataPtr += 3;
        *pBytesWritten += 3;
    }

    if (pExtFeature->value.size > 0)
    {
        memcpy(dataPtr, pExtFeature->value.bytes, pExtFeature->value.size);
        *pBytesWritten += pExtFeature->value.size;
    }

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_WriteInfoFile(const BlueOssSoStorage_t *const pStorage, const BlueOssSoFileInfo_t *const pInfoFile)
{
    uint8_t buffer[15];
    memset(buffer, 0, sizeof(buffer));

    buffer[0] = pInfoFile->versionMajor;
    buffer[1] = pInfoFile->versionMinor;

    BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteCredentialType(&buffer[2], &pInfoFile->credentialType), "Write info file CredentialType");
    BLUE_ERROR_CHECK_DEBUG(blueOss_WriteCredentialId(&buffer[3], &pInfoFile->credentialId), "Write info file CredentialId");

    buffer[13] = pInfoFile->maxEventEntries;
    buffer[14] = pInfoFile->maxBlacklistEntries;

    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->write(pStorage->pContext, BlueOssSoFileId_Info, 0, buffer, sizeof(buffer)), "Write info file");

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_WriteDataFile(const BlueOssSoStorage_t *const pStorage, const BlueOssSoFileData_t *const pDataFile)
{
    BLUE_ERROR_CHECK(blueOssSo_ValidateDataFile(pDataFile));

    const uint8_t headerSize = 16;

    uint8_t doorInfoSize = 0;
    uint8_t dtScheduleSize = 0;
    uint16_t doorInfoTotalSize = 0;
    uint16_t dtScheduleTotalSize = 0;

    blueOssSo_GetDataFileSizes(pDataFile, &doorInfoSize, &dtScheduleSize, &doorInfoTotalSize, &dtScheduleTotalSize);

    uint8_t buffer[headerSize + doorInfoTotalSize + dtScheduleTotalSize];
    memset(buffer, 0, sizeof(buffer));

    //
    // Write regular header
    //
    BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteTimestamp(&buffer[0], &pDataFile->validity), "Write data file validity");

    BLUE_UINT16_WRITE_BE(&buffer[6], pDataFile->siteId);

    //
    // Write the DataFileHeader now
    //

    uint8_t dtsBits[8];
    blueOss_EncodeBinaryNumber(dtsBits, 7, 4, pDataFile->dtSchedules_count);
    blueOss_EncodeBinaryNumber(dtsBits, 3, 2, pDataFile->numberOfDayIdsPerDTSchedule - 1);
    blueOss_EncodeBinaryNumber(dtsBits, 1, 0, pDataFile->numberOfTimePeriodsPerDayId - 1);

    buffer[9] = blueOss_EncodeBits(dtsBits);

    // Number of door entries
    buffer[10] = pDataFile->doorInfoEntries_count;

    // ExtensionsInfo
    uint8_t extensionsInfoBits[8] =
        {
            pDataFile->hasExtensions == true ? 1 : 0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
        };
    buffer[11] = blueOss_EncodeBits(extensionsInfoBits);

    //
    // Write door infos if any
    //
    if (pDataFile->doorInfoEntries_count > 0)
    {
        for (uint8_t doorIndex = 0; doorIndex < pDataFile->doorInfoEntries_count; doorIndex += 1)
        {
            const uint16_t offset = headerSize + (doorIndex * doorInfoSize);
            BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteDoorInfo(&buffer[offset], &pDataFile->doorInfoEntries[doorIndex], pDataFile->dtSchedules_count), "Read data file DoorInfo");
        }
    }

    //
    // Write DTSchedules if any
    //
    if (pDataFile->dtSchedules_count > 0)
    {
        for (uint8_t dtScheduleIndex = 0; dtScheduleIndex < pDataFile->dtSchedules_count; dtScheduleIndex += 1)
        {
            const uint16_t offset = headerSize + doorInfoTotalSize + (dtScheduleIndex * dtScheduleSize);
            BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteDTSchedule(&buffer[offset], &pDataFile->dtSchedules[dtScheduleIndex], pDataFile->numberOfDayIdsPerDTSchedule, pDataFile->numberOfTimePeriodsPerDayId), "Write data file DTSchedule");
        }
    }

    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->write(pStorage->pContext, BlueOssSoFileId_Data, 0, buffer, sizeof(buffer)), "Write data file");

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_WriteEventFile(const BlueOssSoStorage_t *const pStorage, const BlueOssSoFileEvent_t *const pEventFile, uint8_t maxEventEntries)
{
    if (sizeof(pEventFile->supportedEventIds) != BlueEventId_MaxOssSoEventId - 1)
    {
        BLUE_LOG_DEBUG("Compiled with less eventIds than available.");
        return BlueReturnCode_InvalidState;
    }

    if (pEventFile->events_count > maxEventEntries)
    {
        return BlueReturnCode_OssSoMaxEventEntriesExceeded;
    }

    if (maxEventEntries == 0)
    {
        // Leave early, no events support
        return BlueReturnCode_Ok;
    }

    const uint8_t headerSize = 5;

    uint8_t eventSize = 0;
    uint16_t eventTotalSize = 0;
    blueOssSo_GetEventFileSizes(pEventFile, &eventSize, &eventTotalSize);

    uint8_t buffer[headerSize + eventTotalSize];
    memset(buffer, 0, sizeof(buffer));

    //
    // Write regular header
    //
    uint32_t eventConfig = 0;

    for (uint8_t eventId = 1; eventId < BlueEventId_MaxOssSoEventId - 1; eventId += 1)
    {
        if (pEventFile->supportedEventIds[eventId])
        {
            eventConfig |= (1 << (eventId - 1));
        }
    }

    BLUE_UINT32_WRITE_BE(&buffer[0], eventConfig);

    buffer[4] = pEventFile->events_count;

    //
    // Write events if any
    //
    if (eventTotalSize > 0)
    {
        for (uint8_t eventIndex = 0; eventIndex < pEventFile->events_count; eventIndex += 1)
        {
            const uint16_t offset = headerSize + (eventIndex * eventSize);
            BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteEvent(&buffer[offset], &pEventFile->events[eventIndex]), "Write event file Event");
        }
    }

    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->write(pStorage->pContext, BlueOssSoFileId_Event, 0, buffer, sizeof(buffer)), "Write event file");

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_WriteBlacklistFile(const BlueOssSoStorage_t *const pStorage, const BlueOssSoFileBlacklist_t *const pBlacklistFile, uint8_t maxBlacklistEntries)
{
    if (pBlacklistFile->entries_count > maxBlacklistEntries)
    {
        return BlueReturnCode_OssSoMaxBlacklistEntriesExceeded;
    }

    if (maxBlacklistEntries == 0)
    {
        // Leave early no blacklist supported
        return BlueReturnCode_Ok;
    }

    const uint8_t headerSize = 1;

    uint8_t entrySize = 0;
    uint16_t entryTotalSize = 0;
    blueOssSo_GetBlacklistFileSizes(pBlacklistFile, &entrySize, &entryTotalSize);

    uint8_t buffer[headerSize + entryTotalSize];
    memset(buffer, 0, sizeof(buffer));

    //
    // Write regular header
    //
    buffer[0] = pBlacklistFile->entries_count;

    //
    // Write blacklist entries if any
    //
    if (entryTotalSize > 0)
    {
        for (uint8_t entryIndex = 0; entryIndex < pBlacklistFile->entries_count; entryIndex += 1)
        {
            const uint16_t offset = headerSize + (entryIndex * entrySize);
            BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteBlacklistEntry(&buffer[offset], &pBlacklistFile->entries[entryIndex]), "Write blacklist file BlacklistEntry");
        }
    }

    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->write(pStorage->pContext, BlueOssSoFileId_Blacklist, 0, buffer, sizeof(buffer)), "Write blacklist file");

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_WriteCustomerExtensionsFile(const BlueOssSoStorage_t *const pStorage, const BlueOssSoFileCustomerExtensions_t *const pCustomerExtensionsFile)
{
    const uint8_t headerSize = 2;

    const uint16_t maxFeaturesCount = (sizeof(pCustomerExtensionsFile->extFeatures) / sizeof(pCustomerExtensionsFile->extFeatures[0]));
    const uint16_t maxFileSize = maxFeaturesCount * (3 + 3 + sizeof(pCustomerExtensionsFile->extFeatures[0].value.bytes));

    uint8_t buffer[headerSize + maxFileSize];
    memset(buffer, 0, sizeof(buffer));

    uint16_t fileSize = headerSize;

    //
    // Write all features first so we know the final file size to write into the header
    //
    for (uint8_t extFeatureIndex = 0; extFeatureIndex < pCustomerExtensionsFile->extFeatures_count; extFeatureIndex += 1)
    {
        uint16_t bytesWritten = 0;
        BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteExtFeature(&buffer[fileSize], &pCustomerExtensionsFile->extFeatures[extFeatureIndex], &bytesWritten), "Write customer extensions file ExtFeature");
        fileSize += bytesWritten;
    }

    //
    // Write known custom features if any now
    //
    if (pCustomerExtensionsFile->has_validityStart)
    {
        BlueOssSoExtFeature_t extFeature =
            {
                .tag = BLUE_OSSSO_EXTFEATURE_VALIDITY_START_TAG,
                .value =
                    {
                        .size = 6,
                    },
            };

        if (blueOssSo_WriteTimestamp(extFeature.value.bytes, &pCustomerExtensionsFile->validityStart.validityStartTime) == BlueReturnCode_Ok)
        {
            uint16_t bytesWritten = 0;
            BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteExtFeature(&buffer[fileSize], &extFeature, &bytesWritten), "Write customer extensions file ValidityStart Feature");
            fileSize += bytesWritten;
        }
    }

    //
    // Write file-size into header now and store our extensions file
    //
    BLUE_UINT16_WRITE_BE(&buffer[0], fileSize);

    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->write(pStorage->pContext, BlueOssSoFileId_CustomerExtensions, 0, buffer, fileSize), "Write customer extensions file");

    return BlueReturnCode_Ok;
}

//
// -- Processing --
//

bool blueOssSo_HasDTScheduleAccess(const BlueLocalTimestamp_t *const pTimestamp, const BlueOssSoDTSchedule_t *const pDTSchedule, BlueLocalTimestamp_t *const pScheduleEndTime)
{
    BlueWeekday_t timestampWeekday = blueUtils_TimestampGetWeekday(pTimestamp);

    const uint16_t timestampTimeMinutes = pTimestamp->hours * 60 + pTimestamp->minutes;

    bool hasAccess = false;

    BlueLocalTimestamp_t scheduleEndTime;
    memcpy(&scheduleEndTime, pScheduleEndTime, sizeof(BlueLocalTimestamp_t));

    //
    // Iterate days and find a matching schedule
    //
    for (uint8_t dayIndex = 0; dayIndex < pDTSchedule->days_count; dayIndex += 1)
    {
        const BlueOssSoDTScheduleDay_t *const day = &pDTSchedule->days[dayIndex];

        if (!day->weekdays[timestampWeekday])
        {
            // Wrong weekday so leave here
            continue;
        }

        // Iterate time periods and figure if we're within any
        for (uint8_t timePeriodIndex = 0; timePeriodIndex < day->timePeriods_count; timePeriodIndex += 1)
        {
            const BlueLocalTimeperiod_t *const timePeriod = &day->timePeriods[timePeriodIndex];

            const uint16_t startTimeMinutes = timePeriod->hoursFrom * 60 + timePeriod->minutesFrom;
            const uint16_t endTimeMinutes = timePeriod->hoursTo * 60 + timePeriod->minutesTo;

            if (startTimeMinutes > timestampTimeMinutes)
            {
                continue;
            }

            if (endTimeMinutes < timestampTimeMinutes)
            {
                continue;
            }

            // Coming here means we do have access by schedule though we'll continue to iterate to figure
            // the best matching schedule as well as we will try to find a proper schedule ending time (longest)
            hasAccess = true;

            // Construct the ending timestamp now
            BlueLocalTimestamp_t endTime = {
                .year = pTimestamp->year,
                .month = pTimestamp->month,
                .date = pTimestamp->date,
                .hours = timePeriod->hoursTo,
                .minutes = timePeriod->minutesTo,
                .seconds = 0,
            };

            // Handle special case - if our time period is ending at midnight (24:00) we have to check if there's
            // a matching day and time period on the current schedule that starts at the next weekday at 00:00 and if so,
            // take that time period's ending time intead.
            if (endTime.hours == 24 && endTime.minutes == 0)
            {
                // Find the follow-up weekday starting at exactly 00:00
                for (uint8_t di = 0; di < pDTSchedule->days_count; di += 1)
                {
                    const BlueOssSoDTScheduleDay_t *const d = &pDTSchedule->days[di];
                    if (d->weekdays[timestampWeekday + 1])
                    {
                        for (uint8_t tpi = 0; tpi < d->timePeriods_count; tpi += 1)
                        {
                            // Make sure to not match ourself
                            if (di == dayIndex && tpi == timePeriodIndex)
                            {
                                continue;
                            }

                            const BlueLocalTimeperiod_t *const tp = &d->timePeriods[tpi];
                            if (tp->hoursFrom == 0 && tp->minutesFrom == 0)
                            {
                                endTime.hours = tp->hoursTo;
                                endTime.minutes = tp->minutesTo;
                                blueUtils_TimestampAdd(&endTime, 1, BlueTimeUnit_Days);
                                break;
                            }
                        }
                    }
                }
            }

            // Coming here means our schedule matches so store its end time in our overall
            // schedule end time if not set yet or our current end time is larger on the same day (!)
            if (scheduleEndTime.year == 0 || (blueUtils_TimestampCompare(&endTime, &scheduleEndTime) == 1))
            {
                memcpy(&scheduleEndTime, &endTime, sizeof(BlueLocalTimestamp_t));
            }
        }
    }

    if (!hasAccess)
    {
        return false;
    }

    memcpy(pScheduleEndTime, &scheduleEndTime, sizeof(BlueLocalTimestamp_t));

    return true;
}

BlueReturnCode_t blueOssSo_EvaluateAccess(const BlueLocalTimestamp_t *const pTimestamp, const BlueOssSoProcessConfig_t *const pConfig, const BlueOssSoFileData_t *const pDataFile, BlueOssAccessResult_t *const pResult)
{
    BlueOssAccessResult_t result = BlueOssAccessResult_Default;

    //
    // Iterate all door infos now then evaluate each if it allows access. If it does and we got multiple
    // ones we simply need to order the access-type by priority as set by oss specification
    //
    for (uint8_t doorInfoIndex = 0; doorInfoIndex < pDataFile->doorInfoEntries_count; doorInfoIndex += 1)
    {
        const BlueOssSoDoorInfo_t *const doorInfo = &pDataFile->doorInfoEntries[doorInfoIndex];

        if (doorInfo->id == 0)
        {
            // We break at first 0 door info to avoid looping potentially too much
            break;
        }

        //
        // Test if maps against door id or any door group id otherwise leave early
        //
        if (doorInfo->accessBy == BlueOssSoDoorInfoAccessBy_DoorId)
        {
            if (doorInfo->id != pConfig->doorId)
            {
                continue;
            }
        }
        else if (doorInfo->accessBy == BlueOssSoDoorInfoAccessBy_DoorGroupId)
        {
            int32_t groupIdIndex = -1;

            BLUE_BINARY_SEARCH(pConfig->doorGroupIds, pConfig->doorGroupIdsCount, doorInfo->id, BLUE_BINARY_SEARCH_CMP, groupIdIndex);

            if (groupIdIndex == -1)
            {
                continue;
            }
        }
        else
        {
            // Unknown so continue
            continue;
        }

        //
        // Now test if the door info has a schedule and if yes test if we're within
        // that given schedule and if not leave early here
        //
        bool hasAccess = false;

        if (doorInfo->dtScheduleNumber > 0)
        {
            if (doorInfo->dtScheduleNumber - 1 > pDataFile->dtSchedules_count)
            {
                return BlueReturnCode_OssSoInvalidDTScheduleNumber;
            }

            const BlueOssSoDTSchedule_t *const dtSchedule = &pDataFile->dtSchedules[doorInfo->dtScheduleNumber - 1];

            hasAccess = blueOssSo_HasDTScheduleAccess(pTimestamp, dtSchedule, &result.scheduleEndTime);

            if (!hasAccess)
            {
                result.scheduleMissmatch = true;
            }
        }
        else
        {
            // No schedule set so has access all-time
            hasAccess = true;
            result.scheduleMissmatch = false;
        }

        if (hasAccess)
        {
            if (!result.accessGranted)
            {
                result.accessGranted = true;
                result.accessType = doorInfo->accessType;
            }
            else
            {
                // Only assign access type if has higer prio than the current one
                if (doorInfo->accessType > result.accessType)
                {
                    result.accessType = doorInfo->accessType;
                }
            }
        }
    }

    memcpy(pResult, &result, sizeof(BlueOssAccessResult_t));

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_WritePendingEvents(const BlueOssSoStorage_t *const pStorage, const BlueOssSoProcess_t *const pProcess, const BlueOssSoFileInfo_t *const pInfoFile)
{
    const uint8_t headerSize = 5;

    if (pInfoFile->maxEventEntries == 0)
    {
        // Nothing to do
        return BlueReturnCode_Ok;
    }

    BlueOssSoFileEvent_t eventFile;

    BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadEventFile(pStorage, &eventFile, true, pInfoFile->maxEventEntries), "Read event file header for processing pending events");

    //
    // Leave early if no more space available
    //
    if (eventFile.events_count >= pInfoFile->maxEventEntries)
    {
        return BlueReturnCode_OssSoMaxEventEntriesExceeded;
    }

    uint8_t eventSize = 0;
    uint16_t previousEventotalSize = 0;

    blueOssSo_GetEventFileSizes(&eventFile, &eventSize, &previousEventotalSize);

    uint8_t previousEventsCount = eventFile.events_count;

    BlueOssSoProcessPendingEventQuery_t eventQuery =
        {
            .pCredentialId = &pInfoFile->credentialId,
            .startEvent = BLUEOSSSOEVENT_INIT_ZERO,
            .pEventIds = &eventFile.supportedEventIds[0],
            .eventIdsCount = sizeof(eventFile.supportedEventIds) / sizeof(eventFile.supportedEventIds[0]),
            .maxEvents = pInfoFile->maxEventEntries - eventFile.events_count,
        };

    // Iterate all existing events and find the newest ones timestamp and id to use as starting point
    for (uint8_t eventIndex = 0; eventIndex < eventFile.events_count; eventIndex += 1)
    {
        const BlueOssSoEvent_t *const event = &eventFile.events[eventIndex];

        if (event->doorId != pProcess->config.doorId)
        {
            continue;
        }

        if (blueUtils_TimestampCompare(&event->eventTime, &eventQuery.startEvent.eventTime) == 1)
        {
            memcpy(&eventQuery.startEvent, event, sizeof(BlueOssSoEvent_t));
        }
    }

    uint8_t pendingEventsCount = 0;

    BLUE_ERROR_CHECK_DEBUG(pProcess->pFuncs->queryPendingEvents(pProcess->pContext, &eventQuery, &eventFile.events[eventFile.events_count], &pendingEventsCount), "Query events to be written");

    if (pendingEventsCount > 0)
    {
        eventFile.events_count += pendingEventsCount;

        uint16_t afterEventTotalSize = 0;

        blueOssSo_GetEventFileSizes(&eventFile, &eventSize, &afterEventTotalSize);

        //
        // Store all new pending events into a buffer now ready for writing
        //
        uint8_t eventsData[afterEventTotalSize - previousEventotalSize];
        uint8_t eventsDataOffset = 0;

        for (uint8_t eventIndex = previousEventsCount; eventIndex < eventFile.events_count; eventIndex += 1)
        {
            BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteEvent(&eventsData[eventsDataOffset], &eventFile.events[eventIndex]), "Write pending event into buffer");
            eventsDataOffset += eventSize;
        }

        // We first try to append all events to the file at the given offset if enough space. If we
        // receive a BlueReturnCode_NotSupported we know direct writing is not possible and will try to
        // call the seperate writeEvent function instead for each stored event

        const BlueReturnCode_t returnCode = pStorage->pFuncs->write(pStorage->pContext, BlueOssSoFileId_Event, headerSize + previousEventotalSize, eventsData, sizeof(eventsData));
        if (returnCode == BlueReturnCode_NotSupported)
        {
            // Try to iterate each event and use the writeEvent function instead
            for (uint8_t eventIndex = 0; eventIndex < pendingEventsCount; eventIndex += 1)
            {
                const uint16_t offset = eventIndex * eventSize;
                BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->writeEvent(pStorage->pContext, &eventsData[offset], eventSize), "Write event via writeEvent");
            }

            // We leave here as we've written all events via writeEvent function
            return BlueReturnCode_Ok;
        }

        BLUE_ERROR_CHECK_DEBUG(returnCode, "Append to event file");

        // Event was successfully written so make sure to update the header event entries count too
        const uint8_t eventsCount[1] =
            {
                eventFile.events_count,
            };

        BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->write(pStorage->pContext, BlueOssSoFileId_Event, headerSize - 1, eventsCount, sizeof(eventsCount)), "Write single event new header count");
    }

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_UpdateFromBlacklist(const BlueOssSoStorage_t *const pStorage, const BlueOssSoProcess_t *const pProcess, const BlueOssSoFileInfo_t *const pInfoFile)
{
    if (pInfoFile->maxBlacklistEntries == 0)
    {
        // Nothing todo
        return BlueReturnCode_Ok;
    }

    BlueOssSoFileBlacklist_t blacklistFile;

    BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadBlacklistFile(pStorage, &blacklistFile, pInfoFile->maxBlacklistEntries), "Read blacklist file for processing blacklist");

    if (blacklistFile.entries_count > 0)
    {
        BLUE_ERROR_CHECK_DEBUG(pProcess->pFuncs->updateBlacklist(pProcess->pContext, blacklistFile.entries, blacklistFile.entries_count), "Update blacklist");
    }

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_GetStorage(BlueTransponderType_t transponderType, BlueOssSoStorage_t *const pStorage, const BlueOssSoSettings_t *const pSettings, uint8_t *const pOutput, uint16_t *const pOutputSize)
{
    if (transponderType == BlueTransponderType_MobileTransponder)
    {
        BLUE_ERROR_CHECK_DEBUG(blueOssSoMobile_GetStorage(pStorage, pOutput, pOutputSize), "Get mobile Oss So storage");

        return BlueReturnCode_Ok;
    }
    else if (transponderType == BlueTransponderType_MifareDesfire)
    {
        BLUE_ERROR_CHECK_DEBUG(blueOssSoMifareDesfire_GetStorage(pStorage, pSettings), "Get mifare desfire Oss So storage");

        return BlueReturnCode_Ok;
    }

    return BlueReturnCode_InvalidArguments;
}

BlueReturnCode_t blueOssSo_GetStorage_Ext(BlueTransponderType_t transponderType, BlueOssSoStorage_t *const pStorage, const uint8_t *const pSettingsBuffer, uint16_t settingsBufferSize, uint8_t *const pOutput, uint16_t *const pOutputSize)
{
    BlueOssSoSettings_t settings = BLUEOSSSOSETTINGS_INIT_ZERO;

    if (pSettingsBuffer != NULL)
    {
        BLUE_ERROR_CHECK_DEBUG(blueUtils_DecodeData(&settings, BLUEOSSSOSETTINGS_FIELDS, pSettingsBuffer, settingsBufferSize), "Decode Oss So settings");
    }

    return blueOssSo_GetStorage(transponderType, pStorage, pSettingsBuffer != NULL ? &settings : NULL, pOutput, pOutputSize);
}

BlueReturnCode_t blueOssSo_GetStorageProfile(const BlueOssSoStorage_t *const pStorage, const BlueOssSoProvisioningConfiguration_t *const pProvisioningConfig, BlueOssSoStorageProfile_t *const pProfile)
{
    BlueOssSoProvisioningConfiguration_t provisioningConfig;

    if (!pProvisioningConfig)
    {
        BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->getDefaultProvisioningConfiguration(pStorage->pContext, &provisioningConfig), "Get default provisioning config");
    }
    else
    {
        memcpy(&provisioningConfig, pProvisioningConfig, sizeof(BlueOssSoProvisioningConfiguration_t));
    }

    return pStorage->pFuncs->getStorageProfile(pStorage->pContext, &provisioningConfig, pProfile);
}

BlueReturnCode_t blueOssSo_GetStorageProfile_Ext(const BlueOssSoStorage_t *const pStorage, const uint8_t *const pConfigBuffer, uint16_t configBufferSize, uint8_t *const pProfileBuffer, uint16_t profileBufferSize)
{
    const BlueOssSoProvisioningConfiguration_t *pConfiguration = NULL;

    if (pConfigBuffer != NULL)
    {
        BlueOssSoProvisioningConfiguration_t configuration = BLUEOSSSOPROVISIONINGCONFIGURATION_INIT_ZERO;

        BLUE_ERROR_CHECK_DEBUG(blueUtils_DecodeData(&configuration, BLUEOSSSOPROVISIONINGCONFIGURATION_FIELDS, pConfigBuffer, configBufferSize), "Decode Oss So provisioning configuration");

        pConfiguration = &configuration;
    }

    BlueOssSoStorageProfile_t profile = BLUEOSSSOSTORAGEPROFILE_INIT_ZERO;

    BLUE_ERROR_CHECK(blueOssSo_GetStorageProfile(pStorage, pConfiguration, &profile));

    BLUE_ERROR_CHECK_DEBUG(blueUtils_EncodeData(&profile, BLUEOSSSOSTORAGEPROFILE_FIELDS, pProfileBuffer, profileBufferSize), "Encode Oss Os storage profile");

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_Format(const BlueOssSoStorage_t *const pStorage, bool factoryReset)
{
    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->prepare(pStorage->pContext, BlueOssPrepareMode_Format), "Prepare storage in format mode");
    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->format(pStorage->pContext, factoryReset), "Format storage");

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_IsProvisioned(const BlueOssSoStorage_t *const pStorage)
{
    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->prepare(pStorage->pContext, BlueOssPrepareMode_Read), "Prepare storage in read mode");

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t provisionWrite(const BlueOssSoProvisioningData_t *const pData, const BlueOssSoStorage_t *const pStorage)
{
    //
    // Write default configuration after provisioning
    //
    const BlueOssSoVersion_t ossSoVersion = BLUEOSSSOVERSION_INIT_DEFAULT;

    BlueOssSoConfiguration_t configuration = BLUEOSSSOCONFIGURATION_INIT_ZERO;

    configuration.has_info = true;
    configuration.info.versionMajor = ossSoVersion.versionMajor;
    configuration.info.versionMinor = ossSoVersion.versionMinor;
    memcpy(&configuration.info.credentialType, &pData->credentialType, sizeof(BlueOssSoCredentialType_t));
    memcpy(&configuration.info.credentialId, &pData->credentialId, sizeof(BlueCredentialId_t));
    configuration.info.maxEventEntries = pData->configuration.numberOfEvents;
    configuration.info.maxBlacklistEntries = pData->configuration.numberOfBlacklistEntries;

    configuration.has_data = true;
    configuration.data.siteId = pData->siteId;
    configuration.data.hasExtensions = pData->configuration.customerExtensionsSize > 0;
    configuration.data.numberOfDayIdsPerDTSchedule = pData->configuration.numberOfDayIdsPerDTSchedule;
    configuration.data.numberOfTimePeriodsPerDayId = pData->configuration.numberOfTimePeriodsPerDayId;
    configuration.data.dtSchedules_count = pData->configuration.numberOfDTSchedules;
    configuration.data.doorInfoEntries_count = pData->configuration.numberOfDoors;

    for (uint8_t dtScheduleIndex = 0; dtScheduleIndex < configuration.data.dtSchedules_count; dtScheduleIndex += 1)
    {
        BlueOssSoDTSchedule_t *const dtSchedule = &configuration.data.dtSchedules[dtScheduleIndex];
        dtSchedule->days_count = configuration.data.numberOfDayIdsPerDTSchedule;
        for (uint8_t dayIndex = 0; dayIndex < dtSchedule->days_count; dayIndex += 1)
        {
            dtSchedule->days[dayIndex].timePeriods_count = configuration.data.numberOfTimePeriodsPerDayId;
        }
    }

    configuration.has_blacklist = true;
    configuration.blacklist.entries_count = 0;

    configuration.has_event = true;
    configuration.event.events_count = 0;
    memcpy(configuration.event.supportedEventIds, pData->configuration.supportedEventIds, sizeof(configuration.event.supportedEventIds));

    configuration.has_customerExtensions = true;

    return writeConfiguration(pStorage, &configuration, BlueOssSoReadWriteFlags_All);
}

BlueReturnCode_t blueOssSo_Provision(const BlueOssSoStorage_t *const pStorage, const BlueOssSoProvisioningData_t *const pData)
{
    BlueOssSoProvisioningData_t data;
    memcpy(&data, pData, sizeof(BlueOssSoProvisioningData_t));

    if (!data.has_configuration)
    {
        BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->getDefaultProvisioningConfiguration(pStorage->pContext, &data.configuration), "Get default provisioning config");
        data.has_configuration = true;
    }

    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->prepare(pStorage->pContext, BlueOssPrepareMode_Provision), "Prepare storage in provision mode");
    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->provision(pStorage->pContext, &data, &provisionWrite, pStorage), "Provision Oss So on storage");

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_Provision_Ext(const BlueOssSoStorage_t *const pStorage, const uint8_t *const pDataBuffer, uint16_t dataBufferSize)
{
    BlueOssSoProvisioningData_t data = BLUEOSSSOPROVISIONINGDATA_INIT_ZERO;

    BLUE_ERROR_CHECK_DEBUG(blueUtils_DecodeData(&data, BLUEOSSSOPROVISIONINGDATA_FIELDS, pDataBuffer, dataBufferSize), "Decode Oss So provisioning data");

    return blueOssSo_Provision(pStorage, &data);
}

BlueReturnCode_t blueOssSo_Unprovision(const BlueOssSoStorage_t *const pStorage)
{
    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->prepare(pStorage->pContext, BlueOssPrepareMode_Unprovision), "Prepare storage in unprovision mode");
    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->unprovision(pStorage->pContext), "Unprovision Oss So on storage");

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_ReadConfiguration(const BlueOssSoStorage_t *const pStorage, BlueOssSoConfiguration_t *const pConfiguration, BlueOssSoReadWriteFlags_t readFlags)
{
    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->prepare(pStorage->pContext, BlueOssPrepareMode_Read), "Prepare storage in read mode");

    BlueOssSoConfiguration_t zeroConfig = BLUEOSSSOCONFIGURATION_INIT_ZERO;
    memcpy(pConfiguration, &zeroConfig, sizeof(BlueOssSoConfiguration_t));

    if ((readFlags & BlueOssSoReadWriteFlags_Info) == BlueOssSoReadWriteFlags_Info)
    {
        BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadInfoFile(pStorage, &pConfiguration->info), "Read config info file");
        pConfiguration->has_info = true;
    }

    if ((readFlags & BlueOssSoReadWriteFlags_Data) == BlueOssSoReadWriteFlags_Data)
    {
        BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadDataFile(pStorage, &pConfiguration->data), "Read config data file");
        pConfiguration->has_data = true;
    }

    if ((readFlags & BlueOssSoReadWriteFlags_Event) == BlueOssSoReadWriteFlags_Event)
    {
        BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadEventFile(pStorage, &pConfiguration->event, true, pConfiguration->info.maxEventEntries), "Read config event file");
        pConfiguration->has_event = true;
    }

    if ((readFlags & BlueOssSoReadWriteFlags_Blacklist) == BlueOssSoReadWriteFlags_Blacklist)
    {
        BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadBlacklistFile(pStorage, &pConfiguration->blacklist, pConfiguration->info.maxBlacklistEntries), "Read config blacklist file");
        pConfiguration->has_blacklist = true;
    }

    if (pConfiguration->data.hasExtensions && (readFlags & BlueOssSoReadWriteFlags_CustomerExtensions) == BlueOssSoReadWriteFlags_CustomerExtensions)
    {
        BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadCustomerExtensionsFile(pStorage, &pConfiguration->customerExtensions), "Read config customer extensions file");
        pConfiguration->has_customerExtensions = true;
    }

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_ReadConfiguration_Ext(const BlueOssSoStorage_t *const pStorage, uint8_t *const pConfigurationBuffer, uint16_t configurationBufferSize, BlueOssSoReadWriteFlags_t readFlags)
{
    BlueOssSoConfiguration_t configuration = BLUEOSSSOCONFIGURATION_INIT_ZERO;

    BLUE_ERROR_CHECK(blueOssSo_ReadConfiguration(pStorage, &configuration, readFlags));

    BLUE_ERROR_CHECK_DEBUG(blueUtils_EncodeData(&configuration, BLUEOSSSOCONFIGURATION_FIELDS, pConfigurationBuffer, configurationBufferSize), "Encode Oss So configuration");

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t writeConfiguration(const BlueOssSoStorage_t *const pStorage, const BlueOssSoConfiguration_t *const pConfiguration, BlueOssSoReadWriteFlags_t writeFlags)
{
    if ((writeFlags & BlueOssSoReadWriteFlags_Info) == BlueOssSoReadWriteFlags_Info)
    {
        if (!pConfiguration->has_info)
        {
            return BlueReturnCode_InvalidArguments;
        }

        BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteInfoFile(pStorage, &pConfiguration->info), "Write config info file");
    }

    if ((writeFlags & BlueOssSoReadWriteFlags_Data) == BlueOssSoReadWriteFlags_Data)
    {
        if (!pConfiguration->has_data)
        {
            return BlueReturnCode_InvalidArguments;
        }

        BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteDataFile(pStorage, &pConfiguration->data), "Write config data file");
    }

    if ((writeFlags & BlueOssSoReadWriteFlags_Event) == BlueOssSoReadWriteFlags_Event)
    {
        if (!pConfiguration->has_event)
        {
            return BlueReturnCode_InvalidArguments;
        }

        BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteEventFile(pStorage, &pConfiguration->event, pConfiguration->info.maxEventEntries), "Write config event file");
    }

    if ((writeFlags & BlueOssSoReadWriteFlags_Blacklist) == BlueOssSoReadWriteFlags_Blacklist)
    {
        if (!pConfiguration->has_blacklist)
        {
            return BlueReturnCode_InvalidArguments;
        }

        BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteBlacklistFile(pStorage, &pConfiguration->blacklist, pConfiguration->info.maxBlacklistEntries), "Write config blacklist file");
    }

    if ((writeFlags & BlueOssSoReadWriteFlags_CustomerExtensions) == BlueOssSoReadWriteFlags_CustomerExtensions)
    {
        if (!pConfiguration->has_data || !pConfiguration->has_customerExtensions)
        {
            return BlueReturnCode_InvalidArguments;
        }

        if (pConfiguration->data.hasExtensions)
        {
            BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteCustomerExtensionsFile(pStorage, &pConfiguration->customerExtensions), "Write config customer extensions file");
        }
    }

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_WriteConfiguration(const BlueOssSoStorage_t *const pStorage, const BlueOssSoConfiguration_t *const pConfiguration, BlueOssSoReadWriteFlags_t writeFlags)
{
    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->prepare(pStorage->pContext, BlueOssPrepareMode_Write), "Prepare storage in write mode");

    return writeConfiguration(pStorage, pConfiguration, writeFlags);
}

BlueReturnCode_t blueOssSo_WriteConfiguration_Ext(const BlueOssSoStorage_t *const pStorage, const uint8_t *const pConfigurationBuffer, uint16_t configurationBufferSize, BlueOssSoReadWriteFlags_t writeFlags)
{
    BlueOssSoConfiguration_t configuration = BLUEOSSSOCONFIGURATION_INIT_ZERO;

    BLUE_ERROR_CHECK_DEBUG(blueUtils_DecodeData(&configuration, BLUEOSSSOCONFIGURATION_FIELDS, pConfigurationBuffer, configurationBufferSize), "Decode Oss So configuration");

    return blueOssSo_WriteConfiguration(pStorage, &configuration, writeFlags);
}

BlueReturnCode_t blueOssSo_UpdateConfiguration(const BlueOssSoStorage_t *const pStorage, const BlueOssSoConfiguration_t *const pConfiguration, bool clearEvents)
{
    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->prepare(pStorage->pContext, BlueOssPrepareMode_Write), "Prepare storage in write mode");

    BlueOssSoFileInfo_t infoFile;
    bool hasInfoFile = false;

    // Update data if desired
    if (pConfiguration->has_data)
    {
        BlueOssSoFileData_t dataFile;
        BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadDataFile(pStorage, &dataFile), "Read Oss So data file");

        if (dataFile.siteId != pConfiguration->data.siteId)
        {
            BLUE_LOG_ERROR("Expected siteId %d but received siteId %d", dataFile.siteId, pConfiguration->data.siteId);
            return BlueReturnCode_InvalidArguments;
        }

        memcpy(&dataFile.validity, &pConfiguration->data.validity, sizeof(BlueLocalTimestamp_t));

        //
        // Update door infos
        //

        if (pConfiguration->data.doorInfoEntries_count > dataFile.doorInfoEntries_count)
        {
            BLUE_LOG_DEBUG("Update configuration has %d door info entries but only %d entries supported", pConfiguration->data.doorInfoEntries_count, dataFile.doorInfoEntries_count);
            return BlueReturnCode_InvalidArguments;
        }

        for (uint32_t doorInfoIndex = 0; doorInfoIndex < pConfiguration->data.doorInfoEntries_count; doorInfoIndex += 1)
        {
            memcpy(&dataFile.doorInfoEntries[doorInfoIndex], &pConfiguration->data.doorInfoEntries[0], sizeof(BlueOssSoDoorInfo_t));
        }

        // Clear any that are left-over
        if (pConfiguration->data.doorInfoEntries_count < dataFile.doorInfoEntries_count)
        {
            for (uint32_t doorInfoIndex = pConfiguration->data.doorInfoEntries_count; doorInfoIndex < dataFile.doorInfoEntries_count; doorInfoIndex += 1)
            {
                dataFile.doorInfoEntries[doorInfoIndex] = (BlueOssSoDoorInfo_t)BLUEOSSSODOORINFO_INIT_ZERO;
            }
        }

        //
        // Update schedules
        //

        if (pConfiguration->data.dtSchedules_count > dataFile.dtSchedules_count)
        {
            BLUE_LOG_DEBUG("Update configuration has %d schedules but only %d schedules supported", pConfiguration->data.dtSchedules_count, dataFile.dtSchedules_count);
            return BlueReturnCode_InvalidArguments;
        }

        if (pConfiguration->data.numberOfDayIdsPerDTSchedule > dataFile.numberOfDayIdsPerDTSchedule)
        {
            BLUE_LOG_DEBUG("Update configuration has %d days but only %d days per schedule supported", pConfiguration->data.numberOfDayIdsPerDTSchedule, dataFile.numberOfDayIdsPerDTSchedule);
            return BlueReturnCode_InvalidArguments;
        }

        if (pConfiguration->data.numberOfTimePeriodsPerDayId > dataFile.numberOfTimePeriodsPerDayId)
        {
            BLUE_LOG_DEBUG("Update configuration has %d time periods but only %d time periods per schedule day supported", pConfiguration->data.numberOfTimePeriodsPerDayId, dataFile.numberOfTimePeriodsPerDayId);
            return BlueReturnCode_InvalidArguments;
        }

        for (uint32_t dtScheduleIndex = 0; dtScheduleIndex < pConfiguration->data.dtSchedules_count; dtScheduleIndex += 1)
        {
            memcpy(&dataFile.dtSchedules[dtScheduleIndex], &pConfiguration->data.dtSchedules[dtScheduleIndex], sizeof(BlueOssSoDTSchedule_t));
        }

        // Clear any that are left-over. We can simply set day count to zero as when writing the data it'll be corrected
        if (pConfiguration->data.dtSchedules_count < dataFile.dtSchedules_count)
        {
            for (uint32_t dtScheduleIndex = pConfiguration->data.dtSchedules_count; dtScheduleIndex < dataFile.dtSchedules_count; dtScheduleIndex += 1)
            {
                dataFile.dtSchedules[dtScheduleIndex].days_count = 0;
            }
        }

        BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteDataFile(pStorage, &dataFile), "Write Oss So data file");
    }

    // Update custom extensions if desired
    if (pConfiguration->has_customerExtensions)
    {
        // No need to read them, we just write it
        BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteCustomerExtensionsFile(pStorage, &pConfiguration->customerExtensions), "Write Oss So customer extensions");
    }

    // Update blacklist if desired
    if (pConfiguration->has_blacklist)
    {
        if (!hasInfoFile)
        {
            BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadInfoFile(pStorage, &infoFile), "Read Oss So info file");
            hasInfoFile = true;
        }

        if (pConfiguration->blacklist.entries_count > infoFile.maxBlacklistEntries)
        {
            BLUE_LOG_DEBUG("Update configuration has %d blacklist entries but only %d entries supported", pConfiguration->blacklist.entries_count, infoFile.maxBlacklistEntries);
            return BlueReturnCode_InvalidArguments;
        }

        BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteBlacklistFile(pStorage, &pConfiguration->blacklist, infoFile.maxBlacklistEntries), "Write Oss So blacklist");
    }

    // Clear events if desired
    if (clearEvents)
    {
        if (!hasInfoFile)
        {
            BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadInfoFile(pStorage, &infoFile), "Read Oss So info file");
            hasInfoFile = true;
        }

        if (infoFile.maxEventEntries > 0)
        {
            BlueOssSoFileEvent_t eventFile;
            BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadEventFile(pStorage, &eventFile, false, infoFile.maxEventEntries), "Read Oss So event file");

            if (eventFile.events_count > 0)
            {
                eventFile.events_count = 0;

                BLUE_ERROR_CHECK_DEBUG(blueOssSo_WriteEventFile(pStorage, &eventFile, infoFile.maxEventEntries), "Write Oss So event file");
            }
        }
    }

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueOssSo_UpdateConfiguration_Ext(const BlueOssSoStorage_t *const pStorage, const uint8_t *const pConfigurationBuffer, uint16_t configurationBufferSize, bool clearEvents)
{
    BlueOssSoConfiguration_t configuration = BLUEOSSSOCONFIGURATION_INIT_ZERO;

    if (pConfigurationBuffer != NULL)
    {
        BLUE_ERROR_CHECK_DEBUG(blueUtils_DecodeData(&configuration, BLUEOSSSOCONFIGURATION_FIELDS, pConfigurationBuffer, configurationBufferSize), "Decode Oss So configuration");
    }

    return blueOssSo_UpdateConfiguration(pStorage, &configuration, clearEvents);
}

BlueReturnCode_t blueOssSo_ProcessAccess(const BlueLocalTimestamp_t *const pTimestamp, const BlueOssSoStorage_t *const pStorage, const BlueOssSoProcess_t *const pProcess, BlueOssAccessResult_t *const pAccessResult)
{
#define STORE_PROCESS_EVENT(EVENT_ID, EVENT_INFO, CREDENTIAL_ID)                 \
    {                                                                            \
        const BlueOssSoEvent_t event = (BlueOssSoEvent_t){                       \
            .eventTime = *pTimestamp,                                            \
            .doorId = pProcess->config.doorId,                                   \
            .eventId = EVENT_ID,                                                 \
            .eventInfo = EVENT_INFO,                                             \
        };                                                                       \
                                                                                 \
        pProcess->pFuncs->storeEvent(pProcess->pContext, &event, CREDENTIAL_ID); \
    }

    BLUE_ERROR_CHECK_DEBUG(pStorage->pFuncs->prepare(pStorage->pContext, pProcess->config.writePendingEvents ? BlueOssPrepareMode_ReadWrite : BlueOssPrepareMode_Read), "Prepare storage in read/write mode");

    BlueOssSoFileInfo_t infoFile;

    BLUE_ERROR_CHECK(blueOssSo_ReadInfoFile(pStorage, &infoFile));

    const BlueOssSoVersion_t ossSoVersion = BLUEOSSSOVERSION_INIT_DEFAULT;
    if (infoFile.versionMajor > ossSoVersion.versionMajor)
    {
        BLUE_LOG_DEBUG("Invalid Oss So version, received %d.%d but only supports %d.%d", infoFile.versionMajor, infoFile.versionMinor, ossSoVersion.versionMajor, ossSoVersion.versionMinor);
        return BlueReturnCode_OssSoIncompatibleMajorVersion;
    }

    if (pAccessResult != NULL)
    {
        memset(pAccessResult, 0, sizeof(BlueOssAccessResult_t));
    }

    if (infoFile.credentialType.typeSource == BlueOssCredentialTypeSource_Proprietary)
    {
        if (!infoFile.credentialType.has_proprietary)
        {
            BLUE_LOG_DEBUG("Missing proprietary on credentialType");
            return BlueReturnCode_InvalidState;
        }

        BLUE_ERROR_CHECK_DEBUG(pProcess->pFuncs->processProprietaryCredentialType(pProcess->pContext, &infoFile.credentialType.proprietary), "Process processProprietaryCredentialType");
    }
    else if (infoFile.credentialType.typeSource == BlueOssCredentialTypeSource_Oss)
    {
        if (!infoFile.credentialType.has_oss)
        {
            BLUE_LOG_DEBUG("Missing oss on credentialType");
            return BlueReturnCode_InvalidState;
        }

        // If we have an intervention media credential we must quickly leave here by checking the blacklist
        // and if not blacklisted we'll immediately open and leave here
        if (infoFile.credentialType.oss.credential == BlueOssSoCredentialTypeOssCredential_InterventionMedia)
        {
            bool isBlacklisted = false;
            BLUE_ERROR_CHECK_DEBUG(pProcess->pFuncs->verifyCredentialIdIsNotBlacklisted(pProcess->pContext, &infoFile.credentialId, &isBlacklisted), "Process verifyCredentialIdIsNotBlacklisted");

            if (isBlacklisted)
            {
                STORE_PROCESS_EVENT(BlueEventId_BlacklistedCredentialDetected, 0, NULL);

                if (pAccessResult != NULL)
                {
                    pAccessResult->accessType = BlueAccessType_NoAccessBlacklisted;
                }

                return pProcess->pFuncs->denyAccess((void *)pProcess->pContext, BlueAccessType_NoAccessBlacklisted);
            }

            STORE_PROCESS_EVENT(BlueEventId_AccessGranted, BlueEventInfoAccess_GrantedDefaultTime, &infoFile.credentialId);

            if (pAccessResult != NULL)
            {
                pAccessResult->accessType = BlueAccessType_DefaultTime;
            }

            return pProcess->pFuncs->grantAccess((void *)pProcess->pContext, BlueAccessType_DefaultTime, NULL);
        }
    }
    else
    {
        return BlueReturnCode_InvalidState;
    }

    // At this stage if our internal timestamp is invalid the spec says to leave here
    if (pProcess->config.timestampIsInvalid)
    {
        if (pAccessResult != NULL)
        {
            pAccessResult->accessType = BlueAccessType_NoAccess;
        }

        return pProcess->pFuncs->denyAccess((void *)pProcess->pContext, BlueAccessType_NoAccess);
    }

    //
    // We are ready to read the dataFile file now
    //
    BlueOssSoFileData_t dataFile;

    BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadDataFile(pStorage, &dataFile), "Process read dataFile file");

    //
    // If the siteId doesn't match, then return immediately
    //
    if (dataFile.siteId != pProcess->config.siteId)
    {
        STORE_PROCESS_EVENT(BlueEventId_AccessDenied, BlueEventInfoAccess_Denied, &infoFile.credentialId);

        if (pAccessResult != NULL)
        {
            pAccessResult->accessType = BlueAccessType_NoAccess;
        }

        return pProcess->pFuncs->denyAccess((void *)pProcess->pContext, BlueAccessType_NoAccess);
    }

    //
    // If the credential is blacklisted then return here
    //
    bool isBlacklisted = false;
    BLUE_ERROR_CHECK_DEBUG(pProcess->pFuncs->verifyCredentialIdIsNotBlacklisted(pProcess->pContext, &infoFile.credentialId, &isBlacklisted), "Process verifyCredentialIdIsNotBlacklisted");

    if (isBlacklisted)
    {
        STORE_PROCESS_EVENT(BlueEventId_BlacklistedCredentialDetected, 0, NULL);
        STORE_PROCESS_EVENT(BlueEventId_AccessDenied, BlueEventInfoAccess_DeniedBlacklisted, &infoFile.credentialId);

        // We're still supposed to write pending events into the card at this stage but we don't fail only log
        if (pProcess->config.writePendingEvents)
        {
            BLUE_ERROR_LOG_DEBUG(blueOssSo_WritePendingEvents(pStorage, pProcess, &infoFile), "Process pending events on blacklisted credential");
        }

        if (pAccessResult != NULL)
        {
            pAccessResult->accessType = BlueAccessType_NoAccessBlacklisted;
        }

        return pProcess->pFuncs->denyAccess(pProcess->pContext, BlueAccessType_NoAccessBlacklisted);
    }

    //
    // Read customer extensions now if wanted
    //
    BlueOssSoFileCustomerExtensions_t customerExtensionsFile = BLUEOSSSOFILECUSTOMEREXTENSIONS_INIT_ZERO; // init with zero as may not be read

    if (dataFile.hasExtensions)
    {
        BLUE_ERROR_CHECK_DEBUG(blueOssSo_ReadCustomerExtensionsFile(pStorage, &customerExtensionsFile), "Process read customer extensions file");
    }

    //
    // Verify the validity of the data now.
    //
    bool dataStartIsValid = false;
    bool dataEndIsValid = false;

    // If we have a validity start extension feature then check this first. If its invalid we immediately deny access
    if (customerExtensionsFile.has_validityStart)
    {
        if (!customerExtensionsFile.validityStart.isValid)
        {
            BLUE_LOG_DEBUG("Customer extension validity start is invalid");
        }
        else if (blueUtils_TimestampCompare(&customerExtensionsFile.validityStart.validityStartTime, pTimestamp) == 1)
        {
            BLUE_LOG_DEBUG("Customer extension validity start is after now");
        }
        else
        {
            dataStartIsValid = true;
        }
    }
    else
    {
        dataStartIsValid = true;
    }

    // Check regular validity now
    if (blueUtils_TimestampCompare(&dataFile.validity, pTimestamp) == -1)
    {
        BLUE_LOG_DEBUG("Validity end is before now");
    }
    else
    {
        dataEndIsValid = true;
    }

    if (!dataStartIsValid || !dataEndIsValid)
    {
        STORE_PROCESS_EVENT(BlueEventId_AccessDenied, BlueEventInfoAccess_DeniedValidity, &infoFile.credentialId);

        // We're still supposed to write pending events into the card at this stage but we don't fail only log failure
        if (pProcess->config.writePendingEvents)
        {
            BLUE_ERROR_LOG_DEBUG(blueOssSo_WritePendingEvents(pStorage, pProcess, &infoFile), "Process pending events on data without validity");
        }

        if (pAccessResult != NULL)
        {
            pAccessResult->accessType = BlueAccessType_NoAccessValidity;
        }

        return pProcess->pFuncs->denyAccess(pProcess->pContext, BlueAccessType_NoAccessValidity);
    }

    //
    // Figure the access type now
    //
    BlueOssAccessResult_t accessResult = BlueOssAccessResult_Default;

    BLUE_ERROR_CHECK_DEBUG(blueOssSo_EvaluateAccess(pTimestamp, &pProcess->config, &dataFile, &accessResult), "Evaluate access type");

    //
    // No matter of the access type we're supposed to store events here and update from the blacklist if any. However we'll just
    // log any errors and will not prevent granting access in case any of those will fail
    //
    if (pProcess->config.writePendingEvents)
    {
        BLUE_ERROR_LOG_DEBUG(blueOssSo_WritePendingEvents(pStorage, pProcess, &infoFile), "Process writing pending events");
    }

    if (pProcess->config.updateFromBlacklist)
    {
        const BlueReturnCode_t blacklistUpdateReturn = blueOssSo_UpdateFromBlacklist(pStorage, pProcess, &infoFile);
        BLUE_ERROR_LOG_DEBUG(blacklistUpdateReturn, "Process reading blacklist");
        if (blacklistUpdateReturn == BlueReturnCode_StorageFull)
        {
            STORE_PROCESS_EVENT(BlueEventId_BlacklistFull, 0, NULL);
        }
    }

    if (pAccessResult != NULL)
    {
        memcpy(pAccessResult, &accessResult, sizeof(BlueOssAccessResult_t));
    }

    //
    // Handle access now finally
    //
    if (!accessResult.accessGranted)
    {
        STORE_PROCESS_EVENT(BlueEventId_AccessDenied, accessResult.scheduleMissmatch ? BlueEventInfoAccess_DeniedDTSchedule : BlueEventInfoAccess_Denied, &infoFile.credentialId);

        return pProcess->pFuncs->denyAccess((void *)pProcess->pContext, accessResult.scheduleMissmatch ? BlueAccessType_NoAccessValidity : BlueAccessType_NoAccess);
    }

    BlueEventInfoAccess_t eventInfo = BlueEventInfoAccess_Granted;

    switch (accessResult.accessType)
    {
    case BlueAccessType_DefaultTime:
        eventInfo = BlueEventInfoAccess_GrantedDefaultTime;
        break;
    case BlueAccessType_ExtendedTime:
        eventInfo = BlueEventInfoAccess_GrantedExtendedTime;
        break;
    case BlueAccessType_Toggle:
        eventInfo = BlueEventInfoAccess_GrantedToggleUnlock;
        break;
    default:
        break;
    }

    STORE_PROCESS_EVENT(BlueEventId_AccessGranted, eventInfo, &infoFile.credentialId);

    return pProcess->pFuncs->grantAccess((void *)pProcess->pContext, accessResult.accessType, accessResult.scheduleEndTime.year > 0 ? &accessResult.scheduleEndTime : NULL);
}
