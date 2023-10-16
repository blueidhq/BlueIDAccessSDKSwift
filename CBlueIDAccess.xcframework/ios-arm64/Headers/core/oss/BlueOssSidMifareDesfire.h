#ifndef BLUE_OSS_SID_MIFARE_DESFIRE_H
#define BLUE_OSS_SID_MIFARE_DESFIRE_H

#include "core/BlueCore.h"

typedef struct BlueOssSidStorage BlueOssSidStorage_t;

#ifdef __cplusplus
extern "C"
{
#endif

    BlueReturnCode_t blueOssSidMifareDesfire_GetStorage(BlueOssSidStorage_t *const pStorage, const BlueOssSidSettings_t *const pSettings);

#ifdef __cplusplus
}
#endif

#endif
