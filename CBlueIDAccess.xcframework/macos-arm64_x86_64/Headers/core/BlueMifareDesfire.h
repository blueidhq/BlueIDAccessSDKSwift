#ifndef BLUE_MIFARE_DESFIRE_H
#define BLUE_MIFARE_DESFIRE_H

#include "core/BlueCore.h"

typedef enum BlueMifareDesfireKeyType
{
    BlueMifareDesfireKeyType_Des,
    BlueMifareDesfireKeyType_2k3Des,
    BlueMifareDesfireKeyType_3k3Des,
    BlueMifareDesfireKeyType_Aes,
} BlueMifareDesfireKeyType_t;

typedef struct BlueMifareDesfireKey
{
    BlueMifareDesfireKeyType_t type;
    uint8_t data[24];
    uint8_t cmac_sk1[24];
    uint8_t cmac_sk2[24];
    uint8_t aesVersion;
} BlueMifareDesfireKey_t;

typedef struct BlueMifareDesfireTag
{
    uint32_t aid;
    bool hasAid;
    BlueMifareDesfireKey_t sessionKey;
    uint8_t authenticatedKeyNo;
    uint8_t ivect[16];
    uint8_t cmac[16];
} BlueMifareDesfireTag_t;

typedef struct BlueMifareDesfireFileSettings
{
    uint32_t fileSize;
} BlueMifareDesfireFileSettings_t;

#ifdef __cplusplus
extern "C"
{
#endif

    uint16_t blueMifareDesfire_GetFileAccessRights(int8_t readKeyNo, uint8_t writeKeyNo, uint8_t readWriteKeyNo, uint8_t changeKeyNo);

    uint8_t blueMifareDesfire_GetKeySize(BlueMifareDesfireKeyType_t keyType);

    // Try to read free memory available, requires no auth or tag
    BlueReturnCode_t blueMifareDesfire_ReadFreeMemory(BlueMifareDesfireTag_t *const pTag, uint32_t *const pFreeMemory);

    // Selects and authenticates at the master app (PICC)
    BlueReturnCode_t blueMifareDesfire_SelectMaster(BlueMifareDesfireTag_t *const pTag, BlueMifareDesfireKeyType_t keyType, const uint8_t *const pKeyValue);

    // Selects and authenticates at the master app (PICC) and if is default card will provision with new master picc key first
    BlueReturnCode_t blueMifareDesfire_SelectMasterAutoProvision(BlueMifareDesfireTag_t *const pTag, BlueMifareDesfireKeyType_t keyType, const uint8_t *const pKeyValue);

    // Format a mifare desfire card
    BlueReturnCode_t blueMifareDesfire_Format(BlueMifareDesfireTag_t *const pTag);

    // Select an application on a given tag and if app key is provided also authenticates at the app
    BlueReturnCode_t blueMifareDesfire_SelectApplication(BlueMifareDesfireTag_t *const pTag, uint32_t aid, BlueMifareDesfireKeyType_t keyType, const uint8_t *const pKeyValue, uint8_t keyNo);

    // Change the auth key of a given application
    BlueReturnCode_t blueMifareDesfire_ChangeApplicationKey(BlueMifareDesfireTag_t *const pTag, BlueMifareDesfireKeyType_t newKeyType, const uint8_t *const pNewKeyValue, const uint8_t *const pOldKeyValue, uint8_t keyNo);

    // Create a new application
    BlueReturnCode_t blueMifareDesfire_CreateApplication(BlueMifareDesfireTag_t *pTag, uint32_t aid, uint8_t settings, BlueMifareDesfireKeyType_t keysType, uint8_t numberOfKeys);

    // Delete an application
    BlueReturnCode_t blueMifareDesfire_DeleteApplication(BlueMifareDesfireTag_t *pTag, uint32_t aid);

    // Create a standard file
    BlueReturnCode_t blueMifareDesfire_CreateFile(BlueMifareDesfireTag_t *const pTag, uint8_t fileId, uint32_t fileSize, uint8_t communicationSettings, uint16_t accessRights);

    // Delete a file
    BlueReturnCode_t blueMifareDesfire_DeleteFile(BlueMifareDesfireTag_t *const pTag, uint8_t fileId);

    // Write into a file
    BlueReturnCode_t blueMifareDesfire_WriteFile(BlueMifareDesfireTag_t *const pTag, uint8_t fileId, uint16_t offset, const uint8_t *pData, uint16_t size, uint8_t communicationSettings);

    // Read from a file
    BlueReturnCode_t blueMifareDesfire_ReadFile(BlueMifareDesfireTag_t *const pTag, uint8_t fileId, uint16_t offset, uint8_t *const pData, uint16_t size, uint8_t communicationSettings);

    // Get file information
    BlueReturnCode_t blueMifareDesfire_GetFileSettings(BlueMifareDesfireTag_t *const pTag, uint8_t fileId, BlueMifareDesfireFileSettings_t *const pFileSettings);

    // Change file settings
    BlueReturnCode_t blueMifareDesfire_ChangeFileSettings(BlueMifareDesfireTag_t *const pTag, uint8_t fileId, uint8_t communicationSettings, uint16_t accessRights);

#ifdef __cplusplus
}
#endif

#endif
