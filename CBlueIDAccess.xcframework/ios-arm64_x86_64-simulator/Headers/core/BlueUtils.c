#include "core/BlueUtils.h"
#include "core/BlueLog.h"

#include "wolfssl/wolfcrypt/random.h"
#include "wolfssl/wolfcrypt/asn.h"
#include "wolfssl/wolfcrypt/ecc.h"

#include <time.h>

#include "pb_encode.h"
#include "pb_decode.h"

int blueUtils_GetEncodedDataSize(const void *pDataObject, const pb_msgdesc_t *pFields)
{
    pb_ostream_t stream = PB_OSTREAM_SIZING;

    if (!pb_encode_submessage(&stream, pFields, pDataObject))
    {
        BLUE_LOG_ERROR("Getting encoded data size failed");
        return -1;
    }

    return stream.bytes_written;
}

int blueUtils_EncodeData(const void *pDataObject, const pb_msgdesc_t *pFields, uint8_t *pBuffer, size_t size)
{
    pb_ostream_t stream = pb_ostream_from_buffer(pBuffer, size);
    bool status = pb_encode_ex(&stream, pFields, pDataObject, PB_ENCODE_DELIMITED);

    if (!status)
    {
        BLUE_LOG_ERROR("Writing to stream failed with %s, size: %d", PB_GET_ERROR(&stream), size);
        return BlueReturnCode_EncodeDataWriteFailed;
    }

    if (stream.bytes_written <= 0)
    {
        BLUE_LOG_ERROR("No data was written.");
        return BlueReturnCode_EncodeDataWriteNothingWritten;
    }

    return (int)stream.bytes_written;
}

BlueReturnCode_t blueUtils_DecodeData(void *pDataObject, const pb_msgdesc_t *pFields, const void *pBuffer, size_t size)
{
    pb_istream_t stream = pb_istream_from_buffer(pBuffer, size);

    bool status = pb_decode_ex(&stream, pFields, pDataObject, PB_DECODE_DELIMITED | PB_DECODE_NOINIT);

    if (!status)
    {
        BLUE_LOG_ERROR("Reading from proto stream failed with %s, size: %d", PB_GET_ERROR(&stream), size);
        return BlueReturnCode_DecodeDataReadFailed;
    }

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueUtils_CreateSignature(const uint8_t *const pData, uint16_t dataSize, uint8_t *const pSignature, uint16_t signatureSize, uint16_t *const pReturnedSignatureSize, ecc_key *const pPrivateKey)
{
    if (dataSize == 0)
    {
        return BlueReturnCode_InvalidArguments;
    }

    //
    // Generate signature for data
    //
    byte hash[WC_SHA256_DIGEST_SIZE];
    int ret = wc_Sha256Hash(pData, dataSize, hash);
    if (ret != 0)
    {
        BLUE_LOG_ERROR("Sign data failed due wc_Sha256Hash failed with %d", ret);
        return BlueReturnCode_CryptLibraryFailed;
    }

    word32 signatureSizeWord32 = signatureSize;
    ret = wc_ecc_sign_hash(hash, sizeof(hash), pSignature, &signatureSizeWord32, pRNG, pPrivateKey);
    if (ret != 0)
    {
        BLUE_LOG_ERROR("Sign data failed due wc_ecc_sign_hash failed with %d", ret);
        return BlueReturnCode_CryptLibraryFailed;
    }

    *pReturnedSignatureSize = signatureSizeWord32;

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueUtils_CreateSignature_Ext(const uint8_t *const pData, uint16_t dataSize, uint8_t *const pSignature, uint16_t signatureSize, uint16_t *const pReturnedSignatureSize, const uint8_t *const pPrivateKeyBuffer, uint16_t privateKeyBufferSize)
{
    ecc_key privateKey;

    WC_ERROR_CHECK_LOG(wc_ecc_init(&privateKey), "Init private key");
    word32 key_dummy_index = 0;
    WC_ERROR_CHECK_LOG(wc_EccPrivateKeyDecode(pPrivateKeyBuffer, &key_dummy_index, &privateKey, privateKeyBufferSize), "Decode private key");

    const BlueReturnCode_t returnCode = blueUtils_CreateSignature(pData, dataSize, pSignature, signatureSize, pReturnedSignatureSize, &privateKey);

    WC_ERROR_CHECK_LOG(wc_ecc_free(&privateKey), "Release private key");

    return returnCode;
}

BlueReturnCode_t blueUtils_VerifySignature(const uint8_t *const pData, uint16_t dataSize, const uint8_t *const pSignature, uint16_t signatureSize, ecc_key *const pPublicKey)
{
    if (dataSize == 0 || signatureSize == 0)
    {
        return BlueReturnCode_InvalidArguments;
    }

    //
    // Verify signature now
    //
    byte hash[WC_SHA256_DIGEST_SIZE];
    int ret = wc_Sha256Hash(pData, dataSize, hash);
    if (ret != 0)
    {
        BLUE_LOG_ERROR("Verify data failed due wc_Sha256Hash failed with %d", ret);
        return BlueReturnCode_CryptLibraryFailed;
    }

    int validSignature = 0;
    ret = wc_ecc_verify_hash(pSignature, signatureSize, hash, sizeof(hash), &validSignature, pPublicKey);
    if (ret != 0)
    {
        BLUE_LOG_ERROR("Verify data failed due wc_ecc_verify_hash failed with %d", ret);
        return BlueReturnCode_CryptLibraryFailed;
    }

    if (validSignature != 1)
    {
        return BlueReturnCode_InvalidSignature;
    }

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueUtils_VerifySignature_Ext(const uint8_t *const pData, uint16_t dataSize, const uint8_t *const pSignature, uint16_t signatureSize, const uint8_t *const pPublicKey, uint16_t publicKeySize)
{
    ecc_key publicKey;

    WC_ERROR_CHECK_LOG(wc_ecc_init(&publicKey), "Init public key");
    word32 key_dummy_index = 0;
    WC_ERROR_CHECK_LOG(wc_EccPublicKeyDecode(pPublicKey, &key_dummy_index, &publicKey, publicKeySize), "Decode public key");

    const BlueReturnCode_t returnCode = blueUtils_VerifySignature(pData, dataSize, pSignature, signatureSize, &publicKey);

    WC_ERROR_CHECK_LOG(wc_ecc_free(&publicKey), "Release public key");

    return returnCode;
}

BlueReturnCode_t blueUtils_IsValidPublicDERKey(const uint8_t *const pKey, uint16_t keySize)
{
    ecc_key testKey;
    word32 keyLoadIdx = 0;

    WC_ERROR_CHECK_LOG(wc_ecc_init(&testKey), "Init ecc key");

    WC_ERROR_CHECK_LOG(wc_EccPublicKeyDecode(pKey, &keyLoadIdx, &testKey, keySize), "Decode ecc key");

    bool isValid = wc_ecc_check_key(&testKey) == MP_OKAY;

    WC_ERROR_CHECK_LOG(wc_ecc_free(&testKey), "Free ecc key");

    return isValid ? BlueReturnCode_Ok : BlueReturnCode_InvalidArguments;
}

BlueReturnCode_t blueUtils_IsValidPrivateDERKey(const uint8_t *const pKey, uint16_t keySize)
{
    ecc_key testKey;
    word32 keyLoadIdx = 0;

    WC_ERROR_CHECK_LOG(wc_ecc_init(&testKey), "Init ecc key");

    WC_ERROR_CHECK_LOG(wc_EccPrivateKeyDecode(pKey, &keyLoadIdx, &testKey, keySize), "Decode ecc key");

    bool isValid = wc_ecc_check_key(&testKey) == MP_OKAY;

    WC_ERROR_CHECK_LOG(wc_ecc_free(&testKey), "Free ecc key");

    return isValid ? BlueReturnCode_Ok : BlueReturnCode_InvalidArguments;
}

BlueReturnCode_t blueUtils_RandomVector(uint8_t *const pOutput, uint32_t size)
{
    int error = wc_RNG_GenerateBlock(pRNG, pOutput, size);

    if (error)
    {
        return BlueReturnCode_Error;
    }

    return BlueReturnCode_Ok;
}

uint32_t blueUtils_UniqueByteCount(const uint8_t *const pData, uint32_t dataSize)
{
    uint8_t hash[256] = {0};

    for (uint32_t i = 0; i < dataSize; i += 1)
    {
        hash[pData[i]] = 1;
    }

    uint32_t result = 0;

    for (uint32_t x = 0; x < 255; x += 1)
    {
        result += hash[x];
    }

    return result;
}

uint16_t blueUtils_Crc16(uint16_t crc, const void *pData, uint16_t size)
{
    static const uint16_t rtable[16] =
        {
            0x0000,
            0x1021,
            0x2042,
            0x3063,
            0x4084,
            0x50a5,
            0x60c6,
            0x70e7,
            0x8108,
            0x9129,
            0xa14a,
            0xb16b,
            0xc18c,
            0xd1ad,
            0xe1ce,
            0xf1ef,
        };

    const uint8_t *data = pData;

    for (uint16_t i = 0; i < size; i++)
    {
        crc = (crc << 4) ^ rtable[(crc >> 12) ^ (data[i] >> 4)];
        crc = (crc << 4) ^ rtable[(crc >> 12) ^ (data[i] & 0x0F)];
    }

    return crc;
}

uint32_t blueUtils_Crc32(uint32_t crc, const void *pData, uint32_t size)
{
    static const uint32_t rtable[16] =
        {
            0x00000000,
            0x1db71064,
            0x3b6e20c8,
            0x26d930ac,
            0x76dc4190,
            0x6b6b51f4,
            0x4db26158,
            0x5005713c,
            0xedb88320,
            0xf00f9344,
            0xd6d6a3e8,
            0xcb61b38c,
            0x9b64c2b0,
            0x86d3d2d4,
            0xa00ae278,
            0xbdbdf21c,
        };

    const uint8_t *data = pData;

    for (size_t i = 0; i < size; i++)
    {
        crc = (crc >> 4) ^ rtable[(crc ^ (data[i] >> 0)) & 0xf];
        crc = (crc >> 4) ^ rtable[(crc ^ (data[i] >> 4)) & 0xf];
    }

    return crc;
}

BlueReturnCode_t blueUtils_Pad(uint8_t *const pData, uint32_t *const pSize, uint32_t blockSize, uint32_t maxDataSize)
{
    uint32_t newSize = *pSize;
    uint32_t odd = (newSize % blockSize);

    if (odd != 0)
    {
        uint32_t addSize = blockSize - odd;
        newSize += addSize;

        if (newSize > maxDataSize)
        {
            BLUE_LOG_ERROR("padding data with %d exceeds max data size %d", addSize, maxDataSize);
            return BlueReturnCode_Overflow;
        }

        memset(pData + *pSize, 0, addSize);

        *pSize = newSize;
    }

    return BlueReturnCode_Ok;
}

uint32_t blueUtils_PadLength(uint32_t size, uint32_t blockSize)
{
    if ((!size) || (size % blockSize))
    {
        return ((size / blockSize) + 1) * blockSize;
    }
    else
    {
        return size;
    }
}

bool blueUtils_IsLeapYear(uint16_t year)
{
    if ((year % 4 == 0) && ((year % 100 != 0) || (year % 400 == 0)))
    {
        return true;
    }

    return false;
}

uint8_t blueUtils_GetTotalDaysInMonth(uint16_t year, uint8_t month)
{
    switch (month)
    {
    case 2: // February
        return blueUtils_IsLeapYear(year) ? 29 : 28;
    case 4:  // April
    case 6:  // June
    case 9:  // September
    case 11: // November
        return 30;
    default: // January, March, May, July, August, October, December
        return 31;
    }
}

int8_t blueUtils_TimestampCompare(const BlueLocalTimestamp_t *const pTimestamp, const BlueLocalTimestamp_t *const pReference)
{
    int8_t result = blueUtils_TimestampCompareDate(pTimestamp, pReference);

    if (result == 0)
    {
        result = blueUtils_TimestampCompareTime(pTimestamp, pReference);
    }

    return result;
}

int8_t blueUtils_TimestampCompareDate(const BlueLocalTimestamp_t *const pTimestamp, const BlueLocalTimestamp_t *const pReference)
{
    if (pTimestamp->year < pReference->year)
    {
        return -1;
    }
    else if (pTimestamp->year > pReference->year)
    {
        return 1;
    }

    if (pTimestamp->month < pReference->month)
    {
        return -1;
    }
    else if (pTimestamp->month > pReference->month)
    {
        return 1;
    }

    if (pTimestamp->date < pReference->date)
    {
        return -1;
    }
    else if (pTimestamp->date > pReference->date)
    {
        return 1;
    }

    return 0;
}

int8_t blueUtils_TimestampCompareTime(const BlueLocalTimestamp_t *const pTimestamp, const BlueLocalTimestamp_t *const pReference)
{
    if (pTimestamp->hours < pReference->hours)
    {
        return -1;
    }
    else if (pTimestamp->hours > pReference->hours)
    {
        return 1;
    }

    if (pTimestamp->minutes < pReference->minutes)
    {
        return -1;
    }
    else if (pTimestamp->minutes > pReference->minutes)
    {
        return 1;
    }

    if (pTimestamp->seconds < pReference->seconds)
    {
        return -1;
    }
    else if (pTimestamp->seconds > pReference->seconds)
    {
        return 1;
    }

    return 0;
}

int32_t blueUtils_TimestampDiff(const BlueLocalTimestamp_t *const pOldTime, const BlueLocalTimestamp_t *const pNewTime, BlueTimeUnit_t timeUnit)
{
    if (timeUnit == BlueTimeUnit_Seconds || timeUnit == BlueTimeUnit_Minutes || timeUnit == BlueTimeUnit_Hours || timeUnit == BlueTimeUnit_Days)
    {
        int32_t secondsOld = pOldTime->year * 31536000 + pOldTime->month * 2592000 + pOldTime->date * 86400 + pOldTime->hours * 3600 + pOldTime->minutes * 60 + pOldTime->seconds;
        int32_t secondsNew = pNewTime->year * 31536000 + pNewTime->month * 2592000 + pNewTime->date * 86400 + pNewTime->hours * 3600 + pNewTime->minutes * 60 + pNewTime->seconds;
        int32_t secondsDiff = secondsNew - secondsOld;

        switch (timeUnit)
        {
        case BlueTimeUnit_Seconds:
            return secondsDiff;
        case BlueTimeUnit_Minutes:
            return secondsDiff / 60;
        case BlueTimeUnit_Hours:
            return secondsDiff / 3600;
        case BlueTimeUnit_Days:
            return secondsDiff / 86400;
        default:
            break;
        }
    }
    else if (timeUnit == BlueTimeUnit_Months)
    {
        // Calculate the difference in months
        int32_t monthsOld = pOldTime->year * 12 + pNewTime->month;
        int32_t monthsNew = pNewTime->year * 12 + pNewTime->month;
        return monthsNew - monthsOld;
    }
    else if (timeUnit == BlueTimeUnit_Years)
    {
        return pNewTime->year - pOldTime->year;
    }

    return -1;
}

BlueWeekday_t blueUtils_TimestampGetWeekday(const BlueLocalTimestamp_t *const pTimestamp)
{
    int year = pTimestamp->year;
    int month = pTimestamp->month;
    int date = pTimestamp->date;

    if (month <= 2)
    {
        year--;
        month += 12;
    }

    int q = date;
    int m = month;
    int K = year % 100;
    int J = year / 100;

    int h = (q + 13 * (m + 1) / 5 + K + K / 4 + J / 4 + 5 * J) % 7;

    switch (h)
    {
    case 0:
        return BlueWeekday_Saturday;
    case 1:
        return BlueWeekday_Sunday;
    case 2:
        return BlueWeekday_Monday;
    case 3:
        return BlueWeekday_Tuesday;
    case 4:
        return BlueWeekday_Wednesday;
    case 5:
        return BlueWeekday_Thursday;
    case 6:
        return BlueWeekday_Friday;
    default:
        // not supposed to happen at all
        return -1;
    }
}

uint16_t blueUtils_TimestampGetDayOfYear(const BlueLocalTimestamp_t *const pTimestamp, bool is366)
{
    uint8_t daysInMonth[] = {0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};

    const bool isLeapYear = blueUtils_IsLeapYear(pTimestamp->year);

    if (isLeapYear)
    {
        daysInMonth[2] = 29; // correct february for leap year
    }

    uint16_t dayOfYear = pTimestamp->date;

    for (uint8_t month = 1; month < pTimestamp->month; month += 1)
    {
        dayOfYear += daysInMonth[month];
    }

    if (!is366 || isLeapYear)
    {
        return dayOfYear;
    }

    if (pTimestamp->month > 2)
    {
        dayOfYear += 1;
    }

    return dayOfYear;
}

BlueLocalTimestamp_t blueUtils_TimestampFromDayOfYear(uint16_t year, uint16_t dayOfYear, bool is366, uint8_t hours, uint8_t minutes, uint8_t seconds)
{
    BlueLocalTimestamp_t result = {
        .year = year,
        .month = 0,
        .date = 0,
        .hours = hours,
        .minutes = minutes,
        .seconds = seconds,
    };

    uint8_t daysInMonth[] = {0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};

    const bool isLeapYear = blueUtils_IsLeapYear(year);

    if (isLeapYear)
    {
        daysInMonth[2] = 29; // correct february for leap year
    }

    int16_t daysOfYearLeft = dayOfYear;

    if (is366 && !isLeapYear && daysOfYearLeft >= 60)
    {
        daysOfYearLeft -= 1;
    }

    for (uint8_t month = 1; month <= 12; month += 1)
    {
        if (daysOfYearLeft <= daysInMonth[month])
        {
            result.month = month;
            result.date = daysOfYearLeft;
            break;
        }

        daysOfYearLeft -= daysInMonth[month];
    }

    return result;
}

uint32_t blueUtils_TimestampToUnix(const BlueLocalTimestamp_t *const pTimestamp)
{
    struct tm time;

    // Initialize the tm structure from the BlueTimestamp
    time.tm_year = pTimestamp->year - 1900;
    time.tm_mon = pTimestamp->month - 1;
    time.tm_mday = pTimestamp->date;
    time.tm_hour = pTimestamp->hours;
    time.tm_min = pTimestamp->minutes;
    time.tm_sec = pTimestamp->seconds;
    time.tm_isdst = -1;

#if defined(HAVE_STRUCT_TM_GMTOFF)
    time.tm_gmtoff = 0;
    time.tm_zone = "UTC";
#endif

    const time_t t = mktime(&time);

#if defined(HAVE_STRUCT_TM_GMTOFF)
    return (uint32_t)(t + time.tm_gmtoff);
#else
    return (uint32_t)(t);
#endif
}

BlueLocalTimestamp_t blueUtils_TimestampFromUnix(uint32_t epoch)
{
    time_t e = (time_t)epoch;
    struct tm *time = gmtime(&e);

    return (BlueLocalTimestamp_t){
        .year = time->tm_year + 1900,
        .month = time->tm_mon + 1,
        .date = time->tm_mday,
        .hours = time->tm_hour,
        .minutes = time->tm_min,
        .seconds = time->tm_sec,
    };
}

static uint32_t getSecondsForUnit(uint16_t value, BlueTimeUnit_t timeUnit)
{
    switch (timeUnit)
    {
    case BlueTimeUnit_Seconds:
        return value;
    case BlueTimeUnit_Minutes:
        return value * 60;
    case BlueTimeUnit_Hours:
        return value * 3600;
    case BlueTimeUnit_Days:
        return value * 86400;
    default:
        return 0; // others not supported
    }
}

void blueUtils_TimestampAdd(BlueLocalTimestamp_t *const pTimestamp, uint16_t value, BlueTimeUnit_t timeUnit)
{
    *pTimestamp = blueUtils_TimestampFromUnix(blueUtils_TimestampToUnix(pTimestamp) + getSecondsForUnit(value, timeUnit));
}

void blueUtils_TimestampSubtract(BlueLocalTimestamp_t *const pTimestamp, uint16_t value, BlueTimeUnit_t timeUnit)
{
    *pTimestamp = blueUtils_TimestampFromUnix(blueUtils_TimestampToUnix(pTimestamp) - getSecondsForUnit(value, timeUnit));
}

void blueUtils_TimestampEncode(const BlueLocalTimestamp_t *const pTimestamp, uint8_t *const pData, uint8_t dataSize, bool littleEndian)
{
    if (littleEndian)
    {
        BLUE_UINT16_WRITE_LE(&pData[0], pTimestamp->year);
    }
    else
    {
        BLUE_UINT16_WRITE_BE(&pData[0], pTimestamp->year);
    }

    pData[2] = (uint8_t)pTimestamp->month;
    pData[3] = (uint8_t)pTimestamp->date;
    pData[4] = (uint8_t)pTimestamp->hours;
    pData[5] = (uint8_t)pTimestamp->minutes;

    if (dataSize > 6)
    {
        pData[6] = (uint8_t)pTimestamp->seconds;
    }
}

void blueUtils_TimestampDecode(BlueLocalTimestamp_t *const pTimestamp, const uint8_t *const pData, uint8_t dataSize, bool littleEndian)
{
    if (littleEndian)
    {
        pTimestamp->year = BLUE_UINT16_READ_LE(&pData[0]);
    }
    else
    {
        pTimestamp->year = BLUE_UINT16_READ_BE(&pData[0]);
    }

    pTimestamp->month = pData[2];
    pTimestamp->date = pData[3];
    pTimestamp->hours = pData[4];
    pTimestamp->minutes = pData[5];

    if (dataSize > 6)
    {
        pTimestamp->seconds = pData[6];
    }
    else
    {
        pTimestamp->seconds = 0;
    }
}

bool blueUtils_TimeScheduleIsValid(const BlueLocalTimeSchedule_t *const pTimeSchedule, bool noEndTime)
{
    if (pTimeSchedule->dayOfYearStart == 0 || pTimeSchedule->dayOfYearStart > 366)
    {
        return false;
    }

    if (pTimeSchedule->dayOfYearEnd == 0 || pTimeSchedule->dayOfYearEnd > 366 || pTimeSchedule->dayOfYearEnd < pTimeSchedule->dayOfYearStart)
    {
        return false;
    }

    for (uint8_t i = 0; i < 7; i += 1)
    {
        if (pTimeSchedule->weekdays[i] != 0 && pTimeSchedule->weekdays[i] != 1)
        {
            return false;
        }
    }

    if (pTimeSchedule->timePeriod.hoursFrom > 23 || pTimeSchedule->timePeriod.minutesFrom > 59)
    {
        return false;
    }

    if (pTimeSchedule->timePeriod.hoursTo == 0 || pTimeSchedule->timePeriod.hoursTo > 24 || pTimeSchedule->timePeriod.minutesTo > 59 || (pTimeSchedule->timePeriod.hoursTo == 24 && pTimeSchedule->timePeriod.minutesTo > 0))
    {
        return false;
    }

    const uint32_t startMins = pTimeSchedule->timePeriod.hoursFrom * 60 + pTimeSchedule->timePeriod.minutesFrom;
    const uint32_t endMins = pTimeSchedule->timePeriod.hoursTo * 60 + pTimeSchedule->timePeriod.minutesTo;

    if (endMins <= startMins)
    {
        return false;
    }

    if (noEndTime && endMins != startMins)
    {
        return false;
    }

    return true;
}

BlueReturnCode_t blueUtils_TimeScheduleCalculateNext(const BlueLocalTimestamp_t *const pTime, const BlueLocalTimeSchedule_t *const pTimeSchedules, uint16_t timeSchedulesCount, BlueLocalTimestamp_t *const pStartTime, BlueLocalTimestamp_t *const pEndTime, BlueUtilsFilterDayOfYearFunc_t filterDay)
{
    if (timeSchedulesCount == 0)
    {
        return BlueReturnCode_NotFound;
    }

    uint16_t dayOfYearStart = blueUtils_TimestampGetDayOfYear(pTime, true);
    uint16_t dayOfYear = dayOfYearStart;
    uint16_t year = pTime->year;

    bool hasMatch = false;

    while (dayOfYear <= 366)
    {
        if (filterDay == NULL || filterDay(dayOfYear) == false)
        {
            // If day of year is before the start it means we're already in the next year
            const BlueLocalTimestamp_t currentTime = blueUtils_TimestampFromDayOfYear(year, dayOfYear, true, pTime->hours, pTime->minutes, pTime->seconds);
            const BlueWeekday_t weekday = blueUtils_TimestampGetWeekday(&currentTime);

            for (uint16_t i = 0; i < timeSchedulesCount; i += 1)
            {
                const BlueLocalTimeSchedule_t *const schedule = &pTimeSchedules[i];

                if (schedule->weekdays[weekday] != 1)
                {
                    continue;
                }

                const BlueLocalTimestamp_t startTs = blueUtils_TimestampFromDayOfYear(year, schedule->dayOfYearStart, true, schedule->timePeriod.hoursFrom, schedule->timePeriod.minutesTo, 0);
                if (blueUtils_TimestampCompareDate(&startTs, &currentTime) > 0)
                {
                    continue;
                }

                const BlueLocalTimestamp_t endTs = blueUtils_TimestampFromDayOfYear(year, schedule->dayOfYearEnd, true, schedule->timePeriod.hoursTo, schedule->timePeriod.minutesTo, 0);
                if (blueUtils_TimestampCompareDate(&endTs, &currentTime) < 0)
                {
                    continue;
                }

                // If the end time already passed then skip it
                if (blueUtils_TimestampCompareTime(&endTs, &currentTime) < 0)
                {
                    continue;
                }

                const BlueLocalTimestamp_t startTime = {currentTime.year, currentTime.month, currentTime.date, startTs.hours, startTs.minutes, 0};
                const BlueLocalTimestamp_t endTime = {currentTime.year, currentTime.month, currentTime.date, endTs.hours, endTs.minutes, 0};

                if (!hasMatch || blueUtils_TimestampCompareTime(&startTime, pStartTime) < 0)
                {
                    memcpy(pStartTime, &startTime, sizeof(BlueLocalTimestamp_t));
                }

                if (!hasMatch || (blueUtils_TimestampCompareTime(&startTime, pStartTime) < 0 && blueUtils_TimestampCompareTime(&endTime, pEndTime) > 0))
                {
                    memcpy(pEndTime, &endTime, sizeof(BlueLocalTimestamp_t));
                }

                // We'll still continue to figure better times within all schedules
                hasMatch = true;
            }

            if (hasMatch)
            {
                return BlueReturnCode_Ok;
            }
        }

        if (dayOfYear + 1 > 366)
        {
            // Go to next year
            year += 1;
            dayOfYear = 1;
        }
        else
        {
            dayOfYear += 1;

            // If already in next year stop at the day of year start
            if (year > pTime->year && dayOfYear >= dayOfYearStart)
            {
                break;
            }
        }
    }

    return BlueReturnCode_NotFound;
}
