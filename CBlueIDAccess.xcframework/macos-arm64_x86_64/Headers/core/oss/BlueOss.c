#include "core/BlueLog.h"

#include "core/oss/BlueOss.h"

//
// -- Reading --
//

#define OSS_ID_LENGTH 10

BlueReturnCode_t blueOss_ReadCredentialId(const uint8_t *const pData, BlueCredentialId_t *const pCredentialId)
{
    // The oss id is 10 characters though it can contain leading \0s to have shorter ids so we
    // will support this by reading only the valid id characters

    memset(pCredentialId->id, 0, sizeof(pCredentialId->id));

    uint8_t idLength = 0;
    for (uint8_t index = 0; index < OSS_ID_LENGTH; index += 1)
    {
        if (pData[index] == 0 && idLength > 0)
        {
            return BlueReturnCode_OssInvalidCredentialId;
        }

        if (pData[index] != 0)
        {
            pCredentialId->id[idLength] = pData[index];
            idLength += 1;
        }
    }

    if (idLength == 0)
    {
        return BlueReturnCode_OssInvalidCredentialId;
    }

    return BlueReturnCode_Ok;
}

//
// -- Writing --
//

BlueReturnCode_t blueOss_WriteCredentialId(uint8_t *const pData, const BlueCredentialId_t *const pCredentialId)
{
    // As oss supports ids less than 10 characters we musst pad left with \0s in that case
    uint8_t idLength = 0;
    for (uint8_t index = 0; index < sizeof(pCredentialId->id); index += 1)
    {
        if (pCredentialId->id[index] == 0)
        {
            break;
        }

        idLength += 1;
    }

    if (idLength == 0)
    {
        return BlueReturnCode_OssInvalidCredentialId;
    }

    memset(pData, 0, OSS_ID_LENGTH);

    const uint16_t padLeft = OSS_ID_LENGTH - idLength;
    memcpy(&pData[padLeft], pCredentialId->id, idLength);

    return BlueReturnCode_Ok;
}
