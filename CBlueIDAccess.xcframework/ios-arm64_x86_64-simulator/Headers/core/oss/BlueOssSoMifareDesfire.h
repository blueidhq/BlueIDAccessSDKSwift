#ifndef BLUE_OSSSOMIFAREDESFIRE_H
#define BLUE_OSSSOMIFAREDESFIRE_H

#include "core/BlueCore.h"

typedef struct BlueOssSoStorage BlueOssSoStorage_t;

#ifdef __cplusplus
extern "C"
{
#endif

    BlueReturnCode_t blueOssSoMifareDesfire_GetStorage(BlueOssSoStorage_t *const pStorage, const BlueOssSoSettings_t *const pSettings);

#ifdef __cplusplus
}
#endif

#endif
