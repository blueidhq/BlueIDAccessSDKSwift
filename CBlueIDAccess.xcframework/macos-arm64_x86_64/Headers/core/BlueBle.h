#ifndef BLUE_BLE_H
#define BLUE_BLE_H

#include "core/BlueCore.h"

#ifdef __cplusplus
extern "C"
{
#endif

    typedef struct _blue_system_information blue_system_information;

#define BLUE_BLE_ATT_HEADER_SIZE 3
#define BLUE_BLE_COMPANY_IDENTIFIER_SIZE 2

#define BLUE_BLE_AD_DATA_SIZE 31

#define BLUE_BLE_MANUFACTURER_DATA_INITIAL_SIZE 12
#define BLUE_BLE_MANUFACTURER_DATA_SIZE 19
#define BLUE_BLE_MANUFACTURER_DATA_IBEACON_SIZE 25

#define BLUE_BLUETOOTH_COMPANY_IDENTIFIER 0x0C5E

#define BLUE_BLE_SERVICE_UUID 0xFCBA

#define BLUE_BLE_BEACON_UUID "3ABE6601-D90D-4975-88B7-8E3FE83A687A"
#define BLUE_BLE_BEACON_UUID_DATA_BE 0x3a, 0xbe, 0x66, 0x01, 0xd9, 0x0d, 0x49, 0x75, 0x88, 0xb7, 0x8e, 0x3f, 0xe8, 0x3a, 0x68, 0x7a

#define BLUE_BLE_TX_CHARACTERISTIC_UUID "A0150002-4C92-496C-9CF1-007367D7E838"
#define BLUE_BLE_TX_CHARACTERISTIC_UUID_DATA_BE 0xa0, 0x15, 0x00, 0x02, 0x4c, 0x92, 0x49, 0x6c, 0x9c, 0xf1, 0x00, 0x73, 0x67, 0xd7, 0xe8, 0x38
#define BLUE_BLE_TX_CHARACTERISTIC_UUID_DATA_LE 0x38, 0xe8, 0xd7, 0x67, 0x73, 0x00, 0xf1, 0x9c, 0x6c, 0x49, 0x92, 0x4c, 0x02, 0x00, 0x15, 0xa0

#define BLUE_BLE_RX_CHARACTERISTIC_UUID "58920001-0BB5-4F7D-ADA1-988C7FEC44E4"
#define BLUE_BLE_RX_CHARACTERISTIC_UUID_DATA_BE 0x58, 0x92, 0x00, 0x01, 0x0b, 0xb5, 0x4f, 0x7d, 0xad, 0xa1, 0x98, 0x8c, 0x7f, 0xec, 0x44, 0xe4
#define BLUE_BLE_RX_CHARACTERISTIC_UUID_DATA_LE 0xe4, 0x44, 0xec, 0x7f, 0x8c, 0x98, 0xa1, 0xad, 0x7d, 0x4f, 0xb5, 0x0b, 0x01, 0x00, 0x92, 0x58

#define BLUE_BLE_MF_CHARACTERISTIC_UUID "BB650003-6479-4BD3-9629-F68CCB395D81"
#define BLUE_BLE_MF_CHARACTERISTIC_UUID_DATA_BE 0xbb, 0x65, 0x00, 0x03, 0x64, 0x79, 0x4b, 0xd3, 0x96, 0x29, 0xf6, 0x8c, 0xcb, 0x39, 0x5d, 0x81
#define BLUE_BLE_MF_CHARACTERISTIC_UUID_DATA_LE 0x81, 0x5d, 0x39, 0xcb, 0x8c, 0xf6, 0x29, 0x96, 0xd3, 0x4b, 0x79, 0x64, 0x03, 0x00, 0x65, 0xbb

    BlueReturnCode_t blueBle_ReadManufacturerData(const uint8_t *const pMfData, uint8_t mfSize, bool readCompanyIdentifier, BlueBleManufacturerInfo_t *const pMfInfo);
    BlueReturnCode_t blueBle_ReadManufacturerData_Ext(const uint8_t *const pMfData, uint8_t mfSize, bool readCompanyIdentifier, uint8_t *const pMfInfoBuffer, uint16_t mfInfoBufferSize);
    BlueReturnCode_t blueBle_WriteManufacturerData(uint8_t *const pMfData, uint8_t mfSize, bool writeCompanyIdentifier, const BlueBleManufacturerInfo_t *const pMfInfo);
    BlueReturnCode_t blueBle_WritePlainAdvertisementData(uint8_t *const pAdvData, uint8_t advSize, const BlueBleAdvertisementInfo_t *const pAdvInfo);
    BlueReturnCode_t blueBle_WritePlainScanResponseData(uint8_t *const pSrdData, uint8_t srdSize, const BlueBleAdvertisementInfo_t *const pAdvInfo);

#ifdef __cplusplus
}
#endif

#endif
