#ifndef BLUE_OSSSIDMOBILE_H
#define BLUE_OSSSIDMOBILE_H

#include "core/BlueCore.h"

typedef struct BlueOssSidStorage BlueOssSidStorage_t;

#ifdef __cplusplus
extern "C"
{
#endif

    BlueReturnCode_t blueOssSidMobile_GetStorage(BlueOssSidStorage_t *const pStorage, uint8_t *const pOutput, uint16_t *const pOutputSize);
    BlueReturnCode_t blueOssSidMobile_GetStorage_Memory(BlueOssSidStorage_t *const pStorage, const BlueOssSidMobile_t *const pOssSidMobile);

#ifdef __cplusplus
}
#endif

#endif
