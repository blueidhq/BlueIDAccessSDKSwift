#include "core/BlueCore.h"
#include "core/BlueLog.h"
#include "core/BlueUtils.h"

#include "wolfssl/wolfcrypt/wc_port.h"
#include "wolfssl/wolfcrypt/random.h"

#ifndef BLUE_VERSION
#error "Missing BLUE_VERSION"
#endif

#ifndef BLUE_BUILD_TIME
#error "Missing BLUE_BUILD_TIME"
#endif

static BlueVersionInfo_t versionInfo =
    {
        .buildTime = BLUE_BUILD_TIME,
        .version = BLUE_VERSION,
};

const BlueVersionInfo_t *const pBlueVersionInfo = &versionInfo;

static WC_RNG wcRNG;
WC_RNG *const pRNG = &wcRNG;

BlueReturnCode_t blueCore_Init(void)
{
    // Do some asserts, first
    if (sizeof(uint16_t) != 2)
    {
        BLUE_LOG_ERROR("The size of uint16_t was expected to equal 2");
        return BlueReturnCode_InvalidState;
    }

    if (sizeof(pb_size_t) != sizeof(uint16_t))
    {
        BLUE_LOG_ERROR("The size of pb_size_t was expected to equal the size of uint16_t");
        return BlueReturnCode_InvalidState;
    }

    int ret = wolfCrypt_Init();
    if (ret != 0)
    {
        BLUE_LOG_ERROR("wolfCrypt_Init failed with %d", ret);
        return BlueReturnCode_CryptLibraryFailed;
    }

    ret = wc_InitRng(&wcRNG);
    if (ret != 0)
    {
        BLUE_LOG_ERROR("wc_InitRng failed with %d", ret);
        return BlueReturnCode_CryptLibraryFailed;
    }

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueCore_Release(void)
{
    int ret = wc_FreeRng(&wcRNG);
    if (ret != 0)
    {
        BLUE_LOG_ERROR("wc_FreeRng failed with %d", ret);
        return BlueReturnCode_CryptLibraryFailed;
    }

    ret = wolfCrypt_Cleanup();
    if (ret != 0)
    {
        BLUE_LOG_ERROR("wolfCrypt_Cleanup failed with %d", ret);
        return BlueReturnCode_CryptLibraryFailed;
    }

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueCore_getVersionInfo_Ext(uint8_t *const pVersionInfoData, uint16_t versionInfoSize)
{
    return blueUtils_EncodeData(pBlueVersionInfo, BLUEVERSIONINFO_FIELDS, pVersionInfoData, versionInfoSize);
}

uint8_t blueCore_printVersionInfo(char *const pOutput, uint8_t outputSize)
{
    memset(pOutput, 0, outputSize);

    const BlueLocalTimestamp_t buildStamp = blueUtils_TimestampFromUnix(versionInfo.buildTime);

    int res = snprintf(pOutput, outputSize, "%d (%02d.%02d.%d %02d:%02d:%02dZ)",
                       (int)versionInfo.version,
                       (int)buildStamp.date,
                       (int)buildStamp.month,
                       (int)buildStamp.year,
                       (int)buildStamp.hours,
                       (int)buildStamp.minutes,
                       (int)buildStamp.seconds);

    return res < 0 ? 0 : (uint8_t)res;
}

void blueCore_logVersionInfo(void)
{
    char buffer[64];
    blueCore_printVersionInfo(buffer, sizeof(buffer));

    BLUE_LOG_INFO("Blue Version: %s", buffer);
}

int blueCore_qSortUInt32Cmp(const void *a, const void *b)
{
    return (*(uint32_t *)a - *(uint32_t *)b);
}
