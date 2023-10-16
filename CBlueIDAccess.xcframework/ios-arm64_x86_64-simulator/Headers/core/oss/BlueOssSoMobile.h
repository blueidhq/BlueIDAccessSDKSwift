#ifndef BLUE_OSSSOMOBILE_H
#define BLUE_OSSSOMOBILE_H

#include "core/BlueCore.h"

typedef struct BlueOssSoStorage BlueOssSoStorage_t;

#ifdef __cplusplus
extern "C"
{
#endif

    BlueReturnCode_t blueOssSoMobile_GetStorage(BlueOssSoStorage_t *const pStorage, uint8_t *const pOutput, uint16_t *const pOutputSize);
    BlueReturnCode_t blueOssSoMobile_GetStorage_Memory(BlueOssSoStorage_t *const pStorage, const BlueOssSoMobile_t *const pOssSoMobile);

#ifdef __cplusplus
}
#endif

#endif
