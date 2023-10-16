#ifndef BLUE_OSS_H
#define BLUE_OSS_H

#include "core/BlueCore.h"

typedef enum BlueOssPrepareMode
{
    BlueOssPrepareMode_Read,
    BlueOssPrepareMode_ReadWrite,
    BlueOssPrepareMode_Write,
    BlueOssPrepareMode_Provision,
    BlueOssPrepareMode_Unprovision,
    BlueOssPrepareMode_Format,
} BlueOssPrepareMode_t;

#define BlueOssAccessResult_Default               \
    {                                             \
        .accessGranted = false,                   \
        .accessType = BlueAccessType_DefaultTime, \
        .scheduleMissmatch = false,               \
        .scheduleEndTime = {                      \
            .year = 0,                            \
            .month = 0,                           \
            .date = 0,                            \
            .hours = 0,                           \
            .minutes = 0,                         \
        },                                        \
    }

typedef BlueReturnCode_t (*BlueOssGrantAccessFunc_t)(void *pContext, BlueAccessType_t accessType, const BlueLocalTimestamp_t *const pScheduleEndTime);
typedef BlueReturnCode_t (*BlueOssDenyAccessFunc_t)(void *pContext, BlueAccessType_t accessType);

#ifdef __cplusplus
extern "C"
{
#endif

    static inline void blueOss_DecodeBits(uint8_t value, uint8_t *const bits)
    {
        bits[0] = (value >> 0) & 1;
        bits[1] = (value >> 1) & 1;
        bits[2] = (value >> 2) & 1;
        bits[3] = (value >> 3) & 1;
        bits[4] = (value >> 4) & 1;
        bits[5] = (value >> 5) & 1;
        bits[6] = (value >> 6) & 1;
        bits[7] = (value >> 7) & 1;
    }

    static inline uint8_t blueOss_EncodeBits(const uint8_t *const bits)
    {
        return (bits[0] << 0) |
               (bits[1] << 1) |
               (bits[2] << 2) |
               (bits[3] << 3) |
               (bits[4] << 4) |
               (bits[5] << 5) |
               (bits[6] << 6) |
               (bits[7] << 7);
    }

    static inline uint8_t blueOss_DecodeBinaryNumber(const uint8_t *const bits, uint8_t fromBit, uint8_t toBit)
    {
        uint8_t result = 0;

        for (int8_t bit = fromBit; bit >= toBit; bit -= 1)
        {
            result = result * 2 + bits[bit];
        }

        return result;
    }

    static inline void blueOss_EncodeBinaryNumber(uint8_t *const bits, uint8_t fromBit, uint8_t toBit, uint8_t number)
    {
        for (uint8_t bit = toBit; bit <= fromBit; bit++)
        {
            bits[bit] = number & 1;
            number >>= 1;
        }
    }

    static inline uint32_t blueOss_DecodePackedBCD(const uint8_t *const pData, uint8_t size)
    {
        uint32_t result = 0;

        for (uint8_t i = 0; i < size; i += 1)
        {
            result *= 100;
            result += (10 * (pData[i] >> 4));
            result += pData[i] & 0xf;
        }

        return result;
    }

    static inline void blueOss_EncodePackedBCD(uint8_t *const pData, uint32_t value, uint8_t size)
    {
        memset(pData, 0, size);

        for (uint8_t i = 0; i < size * 2; i += 1)
        {
            uint32_t hexpart = value % 10;
            pData[size - 1 - (i / 2)] |= (uint8_t)(hexpart << ((i % 2) * 4));
            value /= 10;
        }
    }

    BlueReturnCode_t blueOss_ReadCredentialId(const uint8_t *const pData, BlueCredentialId_t *const pCredentialId);
    BlueReturnCode_t blueOss_WriteCredentialId(uint8_t *const pData, const BlueCredentialId_t *const pCredentialId);

#ifdef __cplusplus
}
#endif

#endif
