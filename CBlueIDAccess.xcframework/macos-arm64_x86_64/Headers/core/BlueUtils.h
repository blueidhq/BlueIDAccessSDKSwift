#ifndef BLUE_UTILS_H
#define BLUE_UTILS_H

#include "core/BlueCore.h"

typedef struct pb_msgdesc_s pb_msgdesc_t;

typedef struct ecc_key ecc_key;

typedef bool (*BlueUtilsFilterDayOfYearFunc_t)(uint16_t dayOfYear);

#ifdef __cplusplus
extern "C"
{
#endif

    // Returns required size in bytes if the given data object would be serialized
    int blueUtils_GetEncodedDataSize(const void *pDataObject, const pb_msgdesc_t *pFields);

    // Retuns the total size of the encoded data given a partial buffer
    int blueUtils_GetEncodedDataTotalSize(uint8_t *pBuffer, size_t size);

    // Convert given data object into binary protobuf serialized buffer, if positive returns size otherwise returns error return code
    int blueUtils_EncodeData(const void *pDataObject, const pb_msgdesc_t *pFields, uint8_t *pBuffer, size_t size);

    // Convert a serialized binary protobuf buffer into a data object
    BlueReturnCode_t blueUtils_DecodeData(void *pDataObject, const pb_msgdesc_t *pFields, const void *pBuffer, size_t size);

    // Create the signature for a given data
    BlueReturnCode_t blueUtils_CreateSignature(const uint8_t *const pData, uint16_t dataSize, uint8_t *const pSignature, uint16_t signatureSize, uint16_t *const pReturnedSignatureSize, ecc_key *const pPrivateKey);
    BlueReturnCode_t blueUtils_CreateSignature_Ext(const uint8_t *const pData, uint16_t dataSize, uint8_t *const pSignature, uint16_t signatureSize, uint16_t *const pReturnedSignatureSize, const uint8_t *const pPrivateKeyBuffer, uint16_t privateKeyBufferSize);

    // Verify a given signature for a given data
    BlueReturnCode_t blueUtils_VerifySignature(const uint8_t *const pData, uint16_t dataSize, const uint8_t *const pSignature, uint16_t signatureSize, ecc_key *const pPublicKey);
    BlueReturnCode_t blueUtils_VerifySignature_Ext(const uint8_t *const pData, uint16_t dataSize, const uint8_t *const pSignature, uint16_t signatureSize, const uint8_t *const pPublicKey, uint16_t publicKeySize);

    // Check if a given public key in DER-Format is valid or not
    BlueReturnCode_t blueUtils_IsValidPublicDERKey(const uint8_t *const pKey, uint16_t keySize);
    // Check if a given private key in DER-Format is valid or not
    BlueReturnCode_t blueUtils_IsValidPrivateDERKey(const uint8_t *const pKey, uint16_t keySize);

    // Generate a random vector with a given size
    BlueReturnCode_t blueUtils_RandomVector(uint8_t *const pOutput, uint32_t size);

    // Returns the number of unique bytes within a given data
    uint32_t blueUtils_UniqueByteCount(const uint8_t *const pData, uint32_t dataSize);

    // Generate crc checksums for a given data and size
    uint16_t blueUtils_Crc16(uint16_t crc, const void *pData, uint16_t size);

    // Pad the given buffer if necessary with zeros to full-fill the given block size
    BlueReturnCode_t blueUtils_Pad(uint8_t *const pData, uint32_t *const pSize, uint32_t blockSize, uint32_t maxDataSize);

    // Return the given padded size
    uint32_t blueUtils_PadLength(uint32_t size, uint32_t blockSize);

    // Returns true if the given year is a leap year
    bool blueUtils_IsLeapYear(uint16_t year);

    // Returns the number of days in a given month and year (handles leap years too)
    uint8_t blueUtils_GetTotalDaysInMonth(uint16_t year, uint8_t month);

    // Returns -1 if timestamp is before reference, 0 if they're equal and +1 if timestamp is after the reference
    int8_t blueUtils_TimestampCompare(const BlueLocalTimestamp_t *const pTimestamp, const BlueLocalTimestamp_t *const pReference);
    int8_t blueUtils_TimestampCompareDate(const BlueLocalTimestamp_t *const pTimestamp, const BlueLocalTimestamp_t *const pReference);
    int8_t blueUtils_TimestampCompareTime(const BlueLocalTimestamp_t *const pTimestamp, const BlueLocalTimestamp_t *const pReference);

    // Returns the difference between two timestamps in a given unit
    int32_t blueUtils_TimestampDiff(const BlueLocalTimestamp_t *const pOldTime, const BlueLocalTimestamp_t *const pNewTime, BlueTimeUnit_t timeUnit);

    // Returns the weekday for a given timestamp
    BlueWeekday_t blueUtils_TimestampGetWeekday(const BlueLocalTimestamp_t *const pTimestamp);

    // Gets the day of the year for a given timestamp, if is366 is true then always a value between 1..366 is returned
    uint16_t blueUtils_TimestampGetDayOfYear(const BlueLocalTimestamp_t *const pTimestamp, bool is366);

    // Constructs a timestamp from a given year and day of year. If is366 is set the day must always be between 0..366
    BlueLocalTimestamp_t blueUtils_TimestampFromDayOfYear(uint16_t year, uint16_t dayOfYear, bool is366, uint8_t hours, uint8_t minutes, uint8_t seconds);

    // Convert a given timestamp into a utc epoch time in seconds
    uint32_t blueUtils_TimestampToUnix(const BlueLocalTimestamp_t *const pTimestamp);

    // Convert a given unix epoch in seconds to a timestamp
    BlueLocalTimestamp_t blueUtils_TimestampFromUnix(uint32_t epoch);

    // Adds a given value in the given time unit to a timestamp
    void blueUtils_TimestampAdd(BlueLocalTimestamp_t *const pTimestamp, uint16_t value, BlueTimeUnit_t timeUnit);

    // Subtracts a given value in the given time unit from a timestamp
    void blueUtils_TimestampSubtract(BlueLocalTimestamp_t *const pTimestamp, uint16_t value, BlueTimeUnit_t timeUnit);

    // Serialize a timestamp into binary
    void blueUtils_TimestampEncode(const BlueLocalTimestamp_t *const pTimestamp, uint8_t *const pData, uint8_t dataSize, bool littleEndian);

    // Deserialize timestamp from binary
    void blueUtils_TimestampDecode(BlueLocalTimestamp_t *const pTimestamp, const uint8_t *const pData, uint8_t dataSize, bool littleEndian);

    // Validates a time schedule
    bool blueUtils_TimeScheduleIsValid(const BlueLocalTimeSchedule_t *const pTimeSchedule, bool noEndTime);

    // Checks if a given timestamp matches any of the given schedules
    bool blueUtils_TimeScheduleMatches(const BlueLocalTimestamp_t *const pTimestamp, const BlueLocalTimeSchedule_t *const pTimeSchedules, uint16_t timeSchedulesCount);

    // Returns a calculated next timestamp based on a set of given time schedules and current time. If filterDay is provided then this callback is called to check if a day should be considered or not.
    BlueReturnCode_t blueUtils_TimeScheduleCalculateNext(const BlueLocalTimestamp_t *const pTime, const BlueLocalTimeSchedule_t *const pTimeSchedules, uint16_t timeSchedulesCount,
                                                         BlueLocalTimestamp_t *const pStartTime, BlueLocalTimestamp_t *const pEndTime, BlueUtilsFilterDayOfYearFunc_t filterDay);

#ifdef __cplusplus
}
#endif

#endif
