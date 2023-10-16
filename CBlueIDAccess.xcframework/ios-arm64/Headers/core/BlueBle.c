#include "core/BlueBle.h"
#include "core/BlueUtils.h"
#include "core/BlueLog.h"

typedef enum BleAdvField
{
    BleAdvField_Flags = 0x01,
    BleAdvField_CompleteLocalName = 0x09,
    BleAdvField_ServiceUUID16Complete = 0x03,
    BleAdvField_ManufacturerData = 0xFF,
    BleAdvField_TxPower = 0x0A
} BleAdvField_t;

BlueReturnCode_t blueBle_ReadManufacturerData(const uint8_t *const pMfData, uint8_t mfSize, bool readCompanyIdentifier, BlueBleManufacturerInfo_t *const pMfInfo)
{
    if (mfSize != BLUE_BLE_MANUFACTURER_DATA_SIZE - (readCompanyIdentifier ? 0 : BLUE_BLE_COMPANY_IDENTIFIER_SIZE))
    {
        return BlueReturnCode_InvalidArguments;
    }

    uint8_t offset = 0;

    if (readCompanyIdentifier)
    {
        uint16_t companyIdentifier = BLUE_UINT16_READ_LE(&pMfData[0]);

        if (companyIdentifier != BLUE_BLUETOOTH_COMPANY_IDENTIFIER)
        {
            return BlueReturnCode_BleInvalidCompanyIdentifier;
        }

        offset = BLUE_BLE_COMPANY_IDENTIFIER_SIZE;
    }

    pMfInfo->hardwareType = pMfData[offset];
    pMfInfo->batteryLevel = pMfData[offset + 1];
    pMfInfo->applicationVersion = BLUE_UINT16_READ_LE(&pMfData[offset + 3]);
    pMfInfo->localMidnightTimeEpoch = BLUE_UINT32_READ_LE(&pMfData[offset + 5]);

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueBle_ReadManufacturerData_Ext(const uint8_t *const pMfData, uint8_t mfSize, bool readCompanyIdentifier, uint8_t *const pMfInfoBuffer, uint16_t mfInfoBufferSize)
{
    BlueBleManufacturerInfo_t mfInfo = BLUEBLEMANUFACTURERINFO_INIT_ZERO;

    BLUE_ERROR_CHECK(blueBle_ReadManufacturerData(pMfData, mfSize, readCompanyIdentifier, &mfInfo));

    BLUE_ERROR_CHECK_DEBUG(blueUtils_EncodeData(&mfInfo, BLUEBLEMANUFACTURERINFO_FIELDS, pMfInfoBuffer, mfInfoBufferSize), "Encode manufacturer info");

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueBle_WriteManufacturerData(uint8_t *const pMfData, uint8_t mfSize, bool writeCompanyIdentifier, const BlueBleManufacturerInfo_t *const pMfInfo)
{
    if (mfSize != BLUE_BLE_MANUFACTURER_DATA_SIZE - (writeCompanyIdentifier ? 0 : BLUE_BLE_COMPANY_IDENTIFIER_SIZE))
    {
        return BlueReturnCode_InvalidArguments;
    }

    memset(pMfData, 0, mfSize);

    uint8_t offset = 0;

    if (writeCompanyIdentifier)
    {
        BLUE_UINT16_WRITE_LE(&pMfData[0], BLUE_BLUETOOTH_COMPANY_IDENTIFIER);
        offset = BLUE_BLE_COMPANY_IDENTIFIER_SIZE;
    }

    pMfData[offset] = (uint8_t)pMfInfo->hardwareType;
    pMfData[offset + 1] = (uint8_t)pMfInfo->batteryLevel;
    BLUE_UINT16_WRITE_LE(&pMfData[offset + 3], pMfInfo->applicationVersion);
    BLUE_UINT32_WRITE_LE(&pMfData[offset + 5], pMfInfo->localMidnightTimeEpoch);

    return BlueReturnCode_Ok;
}

static uint8_t writeAdvField(BleAdvField_t field, const void *pData, uint8_t length, uint8_t *pAdvData, uint8_t position)
{
    pAdvData[position++] = length + 1;
    pAdvData[position++] = field;
    memcpy(&pAdvData[position], pData, length);
    return length + 2;
}

BlueReturnCode_t blueBle_WritePlainAdvertisementData(uint8_t *const pAdvData, uint8_t advSize, const BlueBleAdvertisementInfo_t *const pAdvInfo)
{
    if (advSize != BLUE_BLE_AD_DATA_SIZE)
    {
        return BlueReturnCode_InvalidArguments;
    }

    if (pAdvInfo->isIBeacon)
    {
        //
        // Our Advertisement Data consists of iBeacon manufacturer data plus our service id
        //

        // Define the special iBeacon manufacturer data
        uint8_t iBeaconMfData[BLUE_BLE_MANUFACTURER_DATA_IBEACON_SIZE] = {
            // Apple company identifier for iBeacons
            /* [00] */ 0x4C,
            /* [01] */ 0x00,
            // Beacon Type + Length
            /* [02] */ 0x02,
            /* [03] */ 0x15,
            // UUID (16 bytes)
            /* [04] */ BLUE_BLE_BEACON_UUID_DATA_BE,
            // Major (2 bytes) + Minor (2 bytes)
            /* [20] */ 0x00,
            /* [21] */ 0x00,
            /* [22] */ 0x00,
            /* [23] */ 0x00,
            // TX power (1 byte)
            /* [24] */ (uint8_t)pAdvInfo->txPower1Meter,
        };

        // Ugly but we'll write the device id's first 4 bytes into minor
        // and major version. This is written in big endian as iBeacon mf data is big endian
        // so make sure to read correctly in the client
        iBeaconMfData[20] = pAdvInfo->deviceId[0];
        iBeaconMfData[21] = pAdvInfo->deviceId[1];
        iBeaconMfData[22] = pAdvInfo->deviceId[2];
        iBeaconMfData[23] = pAdvInfo->deviceId[3];

        uint8_t pos = 0;

        // Append our 16-Bit Service UUID
        uint8_t serviceUUID[2];
        BLUE_UINT16_WRITE_LE(&serviceUUID[0], BLUE_BLE_SERVICE_UUID);
        pos += writeAdvField(BleAdvField_ServiceUUID16Complete, serviceUUID, sizeof(serviceUUID), pAdvData, pos);

        // Append our manufacturer data
        pos += writeAdvField(BleAdvField_ManufacturerData, iBeaconMfData, sizeof(iBeaconMfData), pAdvData, pos);

        if (pos != BLUE_BLE_AD_DATA_SIZE)
        {
            return BlueReturnCode_InvalidState;
        }

        return BlueReturnCode_Ok;
    }
    else
    {
        // TODO : Could add meaningful mf data here outside company identifier? The full
        // MfData comes in the scan response as we have more space there
        uint8_t regularMfData[BLUE_BLE_MANUFACTURER_DATA_INITIAL_SIZE] = {
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
        };

        BLUE_UINT16_WRITE_LE(&regularMfData[0], BLUE_BLUETOOTH_COMPANY_IDENTIFIER);

        uint8_t pos = 0;

        // Append our 16-Bit Service UUID
        uint8_t serviceUUID[2];
        BLUE_UINT16_WRITE_LE(&serviceUUID[0], BLUE_BLE_SERVICE_UUID);
        pos += writeAdvField(BleAdvField_ServiceUUID16Complete, serviceUUID, sizeof(serviceUUID), pAdvData, pos);

        // Append our manufacturer data
        pos += writeAdvField(BleAdvField_ManufacturerData, regularMfData, sizeof(regularMfData), pAdvData, pos);

        // Append our complete local name
        pos += writeAdvField(BleAdvField_CompleteLocalName, pAdvInfo->deviceId, sizeof(pAdvInfo->deviceId) - 1, pAdvData, pos);

        // Append our tx-power
        const int8_t txPower[1] = {(int8_t)pAdvInfo->txPower1Meter};
        pos += writeAdvField(BleAdvField_TxPower, txPower, sizeof(txPower), pAdvData, pos);

        if (pos != BLUE_BLE_AD_DATA_SIZE)
        {
            return BlueReturnCode_InvalidState;
        }

        return BlueReturnCode_Ok;
    }

    return BlueReturnCode_InvalidArguments;
}

BlueReturnCode_t blueBle_WritePlainScanResponseData(uint8_t *const pSrdData, uint8_t srdSize, const BlueBleAdvertisementInfo_t *const pAdvInfo)
{
    //
    // Our Scan Response Data consists of our custom manufacturer data plus our complete local name (device-id)
    //

    if (srdSize != BLUE_BLE_AD_DATA_SIZE)
    {
        return BlueReturnCode_InvalidArguments;
    }

    uint8_t mfData[BLUE_BLE_MANUFACTURER_DATA_SIZE];

    BLUE_ERROR_CHECK(blueBle_WriteManufacturerData(mfData, sizeof(mfData), true, &pAdvInfo->mfInfo));

    uint8_t pos = 0;

    // Append our manufacturer data
    pos += writeAdvField(BleAdvField_ManufacturerData, mfData, sizeof(mfData), pSrdData, pos);

    // Append our complete local name
    pos += writeAdvField(BleAdvField_CompleteLocalName, pAdvInfo->deviceId, sizeof(pAdvInfo->deviceId) - 1, pSrdData, pos);

    if (pos != BLUE_BLE_AD_DATA_SIZE)
    {
        return BlueReturnCode_InvalidState;
    }

    return BlueReturnCode_Ok;
}
