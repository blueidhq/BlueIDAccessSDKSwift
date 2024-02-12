#ifndef BLUE_CORE_H
#define BLUE_CORE_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdlib.h>
#include <limits.h>
#include <string.h>

#include "BlueCore.pb.h"

#define BLUE_ERROR_CHECK(EXPRESSION)                        \
    {                                                       \
        BlueReturnCode_t __blue_return_code__ = EXPRESSION; \
        if (__blue_return_code__ < 0)                       \
        {                                                   \
            return __blue_return_code__;                    \
        }                                                   \
    }

#define BLUE_ERROR_CHECK_EXT(EXPRESSION, MESSAGE, IS_ERROR, RETURN)                       \
    {                                                                                     \
        BlueReturnCode_t __blue_return_code__ = EXPRESSION;                               \
        if (__blue_return_code__ < 0)                                                     \
        {                                                                                 \
            if (IS_ERROR)                                                                 \
                BLUE_LOG_ERROR("Failed with <%d> on: %s", __blue_return_code__, MESSAGE); \
            else                                                                          \
                BLUE_LOG_DEBUG("Failed with <%d> on: %s", __blue_return_code__, MESSAGE); \
            RETURN;                                                                       \
        }                                                                                 \
    }

// Return with error codes in case of error
#define BLUE_ERROR_CHECK_ERROR(EXPRESSION, ERROR_MESSAGE) BLUE_ERROR_CHECK_EXT(EXPRESSION, ERROR_MESSAGE, true, return __blue_return_code__)
#define BLUE_ERROR_CHECK_DEBUG(EXPRESSION, ERROR_MESSAGE) BLUE_ERROR_CHECK_EXT(EXPRESSION, ERROR_MESSAGE, false, return __blue_return_code__)

// Return with void in case of error
#define BLUE_ERROR_CHECK_ERROR_VOID(EXPRESSION, ERROR_MESSAGE) BLUE_ERROR_CHECK_EXT(EXPRESSION, ERROR_MESSAGE, true, return)
#define BLUE_ERROR_CHECK_DEBUG_VOUD(EXPRESSION, ERROR_MESSAGE) BLUE_ERROR_CHECK_EXT(EXPRESSION, ERROR_MESSAGE, false, return)

// Just log errors without returning
#define BLUE_ERROR_LOG_ERROR(EXPRESSION, DEBUG_MESSAGE) BLUE_ERROR_CHECK_EXT(EXPRESSION, DEBUG_MESSAGE, true, (void)0)
#define BLUE_ERROR_LOG_DEBUG(EXPRESSION, DEBUG_MESSAGE) BLUE_ERROR_CHECK_EXT(EXPRESSION, DEBUG_MESSAGE, false, (void)0)

#define WC_ERROR_CHECK_LOG(EXPRESSION, ERROR_MESSAGE)                                     \
    {                                                                                     \
        int __wc_return_code__ = EXPRESSION;                                              \
        if (__wc_return_code__ != 0)                                                      \
        {                                                                                 \
            BLUE_LOG_ERROR("Failed with <%d> on: %s", __wc_return_code__, ERROR_MESSAGE); \
            return BlueReturnCode_CryptLibraryFailed;                                     \
        }                                                                                 \
    }

#define BLUE_MIN(a, b) (((a) < (b)) ? (a) : (b))
#define BLUE_MAX(a, b) (((a) > (b)) ? (a) : (b))

#define BLUE_BINARY_SEARCH_CMP(LEFT, RIGHT) ((int)LEFT - (int)RIGHT)
#define BLUE_BINARY_SEARCH_CMP_STR(LEFT, RIGHT) strcmp(LEFT, RIGHT)

#define BLUE_BINARY_SEARCH(ARRAY, ARRAY_COUNT, KEY, KEY_CMP, RESULT_INDEX) \
    {                                                                      \
        RESULT_INDEX = -1;                                                 \
        int left = 0;                                                      \
        int right = ARRAY_COUNT - 1;                                       \
                                                                           \
        while (left <= right)                                              \
        {                                                                  \
            int middle = left + (right - left) / 2;                        \
                                                                           \
            if (KEY_CMP(ARRAY[middle], KEY) == 0)                          \
            {                                                              \
                RESULT_INDEX = middle;                                     \
                break;                                                     \
            }                                                              \
                                                                           \
            if (KEY_CMP(ARRAY[middle], KEY) < 0)                           \
            {                                                              \
                left = middle + 1;                                         \
            }                                                              \
            else                                                           \
            {                                                              \
                right = middle - 1;                                        \
            }                                                              \
        }                                                                  \
    }

//
// Big / little endian helpers
//

#define BLUE_IS_LITTLE_ENDIAN (*(uint16_t *)"\0\x01")

#define BLUE_UINT16_READ_BE(DATA) \
    (((uint16_t)(*(DATA) << 8)) | (uint16_t)(*(DATA + 1)))

#define BLUE_UINT16_READ_LE(DATA) \
    (((uint16_t)(*(DATA))) | (uint16_t)(*(DATA + 1) << 8))

#define BLUE_UINT16_WRITE_BE(DATA, VALUE)  \
    {                                      \
        uint16_t __value__ = VALUE;        \
        *(DATA) = (__value__ >> 8) & 0xFF; \
        *(DATA + 1) = __value__ & 0xFF;    \
    }

#define BLUE_UINT16_WRITE_LE(DATA, VALUE)      \
    {                                          \
        uint16_t __value__ = VALUE;            \
        *(DATA) = (__value__ & 0xFF);          \
        *(DATA + 1) = (__value__ >> 8) & 0xFF; \
    }

#define BLUE_UINT32_READ_BE(DATA) \
    (((uint32_t)(*(DATA) << 24)) | ((uint32_t)(*(DATA + 1)) << 16) | ((uint32_t)(*(DATA + 2) << 8)) | (uint32_t)(*(DATA + 3)))

#define BLUE_UINT32_READ_LE(DATA) \
    (((uint32_t)(*(DATA))) | ((uint32_t)(*(DATA + 1)) << 8) | ((uint32_t)(*(DATA + 2) << 16)) | (uint32_t)(*(DATA + 3) << 24))

#define BLUE_UINT32_WRITE_BE(DATA, VALUE)       \
    {                                           \
        uint32_t __value__ = VALUE;             \
        *(DATA) = (__value__ >> 24) & 0xFF;     \
        *(DATA + 1) = (__value__ >> 16) & 0xFF; \
        *(DATA + 2) = (__value__ >> 8) & 0xFF;  \
        *(DATA + 3) = __value__ & 0xFF;         \
    }

#define BLUE_UINT32_WRITE_LE(DATA, VALUE)       \
    {                                           \
        uint32_t __value__ = VALUE;             \
        *(DATA) = __value__ & 0xFF;             \
        *(DATA + 1) = (__value__ >> 8) & 0xFF;  \
        *(DATA + 2) = (__value__ >> 16) & 0xFF; \
        *(DATA + 3) = (__value__ >> 24) & 0xFF; \
    }

extern const BlueVersionInfo_t *const pBlueVersionInfo;

typedef struct WC_RNG WC_RNG;

extern WC_RNG *const pRNG;

#ifdef __cplusplus
extern "C"
{
#endif

    BlueReturnCode_t blueCore_Init(void);
    BlueReturnCode_t blueCore_Release(void);

    BlueReturnCode_t blueCore_getVersionInfo_Ext(uint8_t *const pVersionInfoData, uint16_t versionInfoSize);
    uint8_t blueCore_printVersionInfo(char *const pOutput, uint8_t outputSize);
    void blueCore_logVersionInfo(void);

    int blueCore_qSortUInt8Cmp(const void *a, const void *b);
    int blueCore_qSortUInt32Cmp(const void *a, const void *b);

    static inline int32_t blueCore_floor(float x)
    {
        int32_t i = (int32_t)x;
        return i - ((i > x) && (x < 0));
    }

#ifdef __cplusplus
}
#endif

#endif
