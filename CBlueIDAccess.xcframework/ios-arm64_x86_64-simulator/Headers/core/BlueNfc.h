#ifndef BLUE_NFC_H
#define BLUE_NFC_H

#include "core/BlueCore.h"

#include <stdio.h>
#include <stdarg.h>

#ifdef __cplusplus
extern "C"
{
#endif

    // -- must be implemented by an installed driver
    extern BlueReturnCode_t blueNfc_Transceive(const uint8_t *const pCommandApdu, uint32_t commandApduLength, uint8_t *const pResponseApdu, uint32_t *pResponseApduLength);

#ifdef __cplusplus
}
#endif

#endif
