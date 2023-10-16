#include "core/BlueMifareDesfire.h"
#include "core/BlueNfc.h"
#include "core/BlueUtils.h"
#include "core/BlueLog.h"

#include "wolfssl/wolfcrypt/aes.h"
#include "wolfssl/wolfcrypt/des3.h"

#include <math.h>

/* Configuration */
#define MAX_FILE_LEN 160L
#define STD_CMD_LEN 8
#define CMAC_LENGTH 8
#define MAX_CRYPTO_BLOCK_SIZE 16
#define MAX_BUFFER_SIZE_CRYPT (STD_CMD_LEN + MAX_FILE_LEN + MAX_CRYPTO_BLOCK_SIZE)
#define DATA_TRANSFER_CHUNK_SIZE 160

/* Constants */
#define CRC32_PRESET 0xFFFFFFFF

/* PICC command */
#define AUTHENTICATE_DES 0x0A
#define AUTHENTICATE_ISO 0x1A
#define AUTHENTICATE_AES 0xAA
#define DES_FORMAT_CARD 0xFC
#define DES_GET_CARD_UID 0x51
#define DES_SELECT_APPLICATION 0x5A
#define DES_WRITE_DATA 0x3D
#define DES_READ_DATA 0xBD
#define DES_CREATE_APPLICATION 0xCA
#define DES_CREATE_STD_DATA_FILE 0xCD
#define DES_CHANGE_KEY 0xC4
#define DES_CHANGE_KEY_SETTINGS 0x54
#define DES_GET_KEY_SETTINGS 0x45
#define DES_DELETE_APPLICATION 0xDA
#define DES_DELETE_FILE 0xDF
#define DES_GET_FILE_SETTINGS 0xF5
#define DES_CHANGE_FILE_SETTINGS 0x5F
#define DES_SET_CONFIGURATION 0x5C
#define DES_FORMAT_CARD 0xFC
#define DES_FREE_MEM 0x6E
#define DES_CREATE_VALUE_FILE 0xCC
#define DES_GET_VALUE 0x6C
#define DES_CREDIT_VALUE 0x0C
#define DES_DEBIT_VALUE 0xDC
#define DES_LIMITED_CREDIT_VALUE 0x1C
#define DES_COMMIT_TRANSACTION 0xC7
#define DES_ABORT_TRANSACTION 0xA7
#define DES_GET_APPLICATION_IDS 0x6A
#define DES_CREATE_LINEAR_RECORD_FILE 0xC1
#define DES_CREATE_CYCLIC_RECORD_FILE 0xC0
#define DES_WRITE_RECORD 0x3B
#define DES_READ_RECORDS 0xBB
#define DES_CLEAR_RECORD_FILE 0xEB
#define DES_CREATE_TRANSACTION_MAC_FILE 0xCE
#define DES_COMMIT_READER_ID 0xC8
#define DES_READ_SIGNATURE 0x3C

/* Status and error codes */
#define OPERATION_OK 0x00
/*#define NO_CHANGES 0x0C
#define OUT_OF_EEPROM_ERROR 0x0E
#define ILLEGAL_COMMAND_CODE 0x1C
#define INTEGRITY_ERROR 0x1E
#define NO_SUCH_KEY 0x40
#define LENGTH_ERROR 0x7E
#define PERMISSION_DENIED 0x9D
#define PARAMETER_ERROR 0x9E
*/
#define APPLICATION_NOT_FOUND 0xA0
/*
#define APPL_INTEGRITY_ERROR 0xA1
*/
#define AUTHENTICATION_ERROR 0xAE
#define ADDITIONAL_FRAME 0xAF
/*
#define BOUNDARY_ERROR 0xBE
#define PICC_INTEGRITY_ERROR 0xC1
#define COMMAND_ABORTED 0xCA
#define PICC_DISABLED_ERROR 0xCD
#define COUNT_ERROR 0xCE
#define DUPLICATE_ERROR 0xDE
#define EEPROM_ERROR_DES 0xEE
#define FILE_NOT_FOUND 0xF0
#define FILE_INTEGRITY_ERROR 0xF1
*/

///// TODO
/* TODO : Whats those? */
#define MDCM_MASK 0x0003
#define CMAC_NONE 0
// Data send to the PICC is used to update the CMAC
#define CMAC_COMMAND 0x010
// Data received from the PICC is used to update the CMAC
#define CMAC_VERIFY 0x020
// MAC the command (when MDCM_MACED)
#define MAC_COMMAND 0x100
// The command returns a MAC to verify (when MDCM_MACED)
#define MAC_VERIFY 0x200
#define ENC_COMMAND 0x1000
#define NO_CRC 0x2000
#define CRC_GLOBAL 0x4000
#define MAC_MASK 0x0F0
#define CMAC_MACK 0xF00
#define MDCM_PLAIN 0x00
#define MDCM_MACED 0x01
#define MDCM_ENCIPHERED 0x03
// END: TODO

// TODO : GET RID OF THOSE GLOBALS
uint8_t cmac_way = 0;
bool crc_found = false;
uint32_t crc32_global;
uint8_t crc_32_f[5];

uint8_t picc_e_rnd_b[16]; // obsolete
uint8_t picc_rnd_b[16];
uint8_t pcd_rnd_a[16];
uint8_t pcd_r_rnd_b[16];
uint8_t picc_e_rnd_a_s[16];
uint8_t picc_rnd_a_s[16];
uint8_t pcd_rnd_a_s[16];

// END: TODO

// TODO : Proper rename enum values
typedef enum
{
    MCD_SEND,
    MCD_RECEIVE,
    MCD_EBC_DIRECTION
} mifare_crypto_direction;

typedef enum
{
    MCO_ENCYPHER,
    MCO_DECYPHER,
    MCO_DECYPHER_NO_CRC,
    MCO_ENCYPHER_NO_CRC
} mifare_crypto_operation;
// END: TODO

static BlueReturnCode_t mifareDesfire_Command(uint8_t cmdLen, uint8_t *cmd_data, uint8_t *resp_len, uint8_t *resp_data)
{
    uint32_t apdu_cmd_len;
    uint8_t cmd_apdu[100];
    uint8_t resp_apdu[100];
    uint32_t resp_apdu_len = sizeof(resp_apdu);

    memset(cmd_apdu, 0, 100);
    cmd_apdu[0] = 0x90;        // CLA
    cmd_apdu[1] = cmd_data[0]; // native command
    cmd_apdu[2] = 0x00;        // P1 must be 0x00
    cmd_apdu[3] = 0x00;        // P2 must be 0x00

    if (cmdLen > 1)
    {
        cmd_apdu[4] = cmdLen - 1;                       // length of native command parameters
        memcpy(&cmd_apdu[5], &cmd_data[1], cmdLen - 1); // native command parameters
        cmd_apdu[5 + cmdLen - 1] = 0;                   // LE mus be 0x00
        apdu_cmd_len = 5 + cmdLen;
    }
    else
    {
        cmd_apdu[4] = 0x00; // LE must be 0x00
        apdu_cmd_len = 5;
    }

#ifdef BLUE_TAG_LOG_COMMANDS
    BLUE_LOG_DEBUG("Send apdu command (%d bytes)", apdu_cmd_len);
    BLUE_LOG_HEXDUMP(cmd_apdu, apdu_cmd_len);
#endif

    BlueReturnCode_t transceiveResult = blueNfc_Transceive(cmd_apdu, apdu_cmd_len, resp_apdu, &resp_apdu_len);
    if (transceiveResult != BlueReturnCode_Ok)
    {
        BLUE_LOG_DEBUG("Failed on apdu command with %d", transceiveResult);
        *resp_len = 0;
        return transceiveResult;
    }

    memcpy((void *)resp_data, (const void *)resp_apdu, resp_apdu_len);
    *resp_len = resp_apdu_len;

#ifdef BLUE_TAG_LOG_COMMANDS
    if (resp_apdu_len == 0)
    {
        BLUE_LOG_DEBUG("Received empty apdu response");
    }
    else
    {
        BLUE_LOG_DEBUG("Received apdu response (%d bytes)", resp_apdu_len);
        BLUE_LOG_HEXDUMP(resp_apdu, resp_apdu_len);
    }
#endif

    return BlueReturnCode_Ok;
}

//
// Inline utils
//

static void xor_1(uint8_t *ivect, uint8_t *data, uint8_t len)
{
    uint8_t i;
    for (i = 0; i < len; i++)
    {
        data[i] ^= ivect[i];
    }
}

static void rol(uint8_t *data, uint8_t len)
{
    uint8_t first = data[0];
    uint8_t i;
    for (i = 0; i < len - 1; i++)
    {
        data[i] = data[i + 1];
    }
    data[len - 1] = first;
}

static void lsl(uint8_t *data, uint8_t len)
{
    uint8_t n;
    for (n = 0; n < len - 1; n++)
    {
        data[n] = (uint8_t)((data[n] << 1) | (data[n + 1] >> 7));
    }
    data[len - 1] <<= 1;
}

// TODO : Replace with blue utils crc32

static void crc32_byte(uint32_t *crc, uint8_t value)
{
    /* x32 + x26 + x23 + x22 + x16 + x12 + x11 + x10 + x8 + x7 + x5 + x4 + x2 + x + 1 */
    uint32_t poly = 0xEDB88320;
    int8_t current_bit;
    uint32_t bit_out;
    *crc ^= (uint32_t)value;

    for (current_bit = 7; current_bit >= 0; current_bit--)
    {
        bit_out = (*crc) & 0x00000001;
        *crc >>= 1;
        if (bit_out)
        {
            *crc ^= poly;
        }
    }
}

static void crc32(const uint8_t *data, uint8_t len, uint8_t *crc, bool first_crc)
{
    uint32_t desfire_crc;
    uint8_t i;

    if (first_crc)
    {
        desfire_crc = CRC32_PRESET;
    }
    else
    {
        desfire_crc = crc32_global;
    }

    for (i = 0; i < len; i++)
    {
        crc32_byte(&desfire_crc, data[i]);
    }

    memcpy((void *)crc, (void *)&desfire_crc, 4);
    crc32_global = desfire_crc;
}

static void crc32_append(uint8_t *data, uint8_t len)
{
    crc32(data, len, data + len, true);
}

//
// Crypto
//

static uint8_t mifareDesfire_encipheredDataLength(BlueMifareDesfireTag_t *tag, uint8_t nbytes, uint32_t communication_settings)
{
    uint8_t crcLength = 0;
    uint8_t blockSize;

    if (!(communication_settings & NO_CRC))
    {
        if ((communication_settings & 0x03) == MDCM_ENCIPHERED)
        {
            crcLength = 4; // AES and 3K3DES
        }
    }

    if (tag->sessionKey.type == BlueMifareDesfireKeyType_Aes)
    {
        blockSize = 16;
    }
    else
    {
        blockSize = 8;
    }

    return blueUtils_PadLength(nbytes + crcLength, blockSize);
}

static void mifareDesfire_cypherSingleBlockDes(BlueMifareDesfireKey_t *key, uint8_t *data, uint8_t *ivect, mifare_crypto_direction direction, mifare_crypto_operation operation)
{
    uint8_t ovect[8];

    Des des;

    if (direction == MCD_SEND)
    {
        xor_1(ivect, data, 8);
    }
    else
    {
        memcpy(ovect, data, 8);
    }

    uint8_t edata[8];

    switch (key->type)
    {
    case BlueMifareDesfireKeyType_Des:
    {
        switch (operation)
        {
        case MCO_ENCYPHER:
        {
            wc_Des_SetKey(&des, key->data, ivect, DES_ENCRYPTION);
            wc_Des_EcbEncrypt(&des, edata, data, 8);
            break;
        }
        case MCO_DECYPHER:
        {
            wc_Des_SetKey(&des, key->data, ivect, DES_DECRYPTION);
            wc_Des_EcbDecrypt(&des, edata, data, 8);
            break;
        }

        default:
        {
            break;
        }
        }
        break;
    }
    case BlueMifareDesfireKeyType_2k3Des:
    {
        switch (operation)
        {
        case MCO_ENCYPHER:
        {
            break;
        }
        case MCO_DECYPHER:
        {
            break;
        }
        default:
        {
            break;
        }
        }
        break;
    case BlueMifareDesfireKeyType_3k3Des:
    {
        switch (operation)
        {
        case MCO_ENCYPHER:
        {
            break;
        }
        case MCO_DECYPHER:
        {
            break;
        }
        default:
        {
            break;
        }
        }
        break;
    }
    }
    default:
    {
        break;
    }
    }

    memcpy(data, edata, 8);

    if (direction == MCD_SEND)
    {
        memcpy(ivect, data, 8);
    }
    else
    {
        xor_1(ivect, data, 8);
        memcpy(ivect, ovect, 8);
    }
}

static void mifareDesfire_cypherSingleBlockAes(uint8_t *keyL1, uint8_t *dataL1, uint8_t *ivect, mifare_crypto_direction direction, mifare_crypto_operation operation)
{
    uint8_t block[16];

    uint8_t localKey[MAX_CRYPTO_BLOCK_SIZE];
    uint8_t i;
    Aes aes;

    for (i = 0; i < 16; i++)
    {
        localKey[i] = keyL1[i];
    }

    for (i = 0; i < 16; i++)
    {
        block[i] = dataL1[i];
    }

    /*
    if (direction == MCD_SEND)
    {
            xor_1(ivect, block, 16);
    }
    else if (direction == MCD_RECEIVE)
    {
            memcpy((void *)ovect, (void *)block, 16);
    }
    */

    switch (operation)
    {
    case MCO_ENCYPHER:
    {
        wc_AesSetKey(&aes, localKey, 16, ivect, AES_ENCRYPTION);
        wc_AesCbcEncrypt(&aes, block, block, 16);
        memcpy(ivect, &aes.reg, 16);
        break;
    }
    case MCO_DECYPHER:
    {
        wc_AesSetKey(&aes, localKey, 16, ivect, AES_DECRYPTION);
        wc_AesCbcDecrypt(&aes, block, block, 16);
        memcpy(ivect, &aes.reg, 16);
        break;
    }
    default:
    {
        break;
    }
    }

    /*
    if (direction == MCD_SEND)
    {
            memcpy((void *)ivect, (void *)block, 16);
    }
    else if (direction == MCD_RECEIVE)
    {
            xor_1(ivect, block, 16);
            memcpy((void *)ivect, (void *)ovect, 16);
    }
    */

    for (i = 0; i < 16; ++i)
    {
        dataL1[i] = block[i];
    }
}

/*
 * This function performs all CBC cyphering / deciphering.
 *
 * The tag argument may be NULL, in which case both key and ivect shall be set.
 * When using the tag sessionKey and ivect for processing data, these
 * arguments should be set to NULL.
 *
 * Because the tag may contain additional data, one may need to call this
 * function with tag, key and ivect defined.
 */
static void mifareDesfire_cypherChainedBlocksAes(uint8_t *keyL, uint8_t *ivect, uint8_t *dataL, uint8_t data_size, mifare_crypto_direction direction, mifare_crypto_operation operation)
{
    uint8_t offset = 0;

    while (offset < data_size)
    {
        mifareDesfire_cypherSingleBlockAes(keyL, dataL + offset, ivect, direction, operation);
        offset += 16;
    }
}

static void mifareDesfire_cypherChainedBlocksDes(BlueMifareDesfireKey_t *key, uint8_t *ivect, uint8_t *data, uint8_t data_size, mifare_crypto_direction direction, mifare_crypto_operation operation)
{
    uint8_t offset = 0;

    if (operation == MCO_DECYPHER_NO_CRC)
    {
        operation = MCO_DECYPHER;
    }
    else if (operation == MCO_ENCYPHER_NO_CRC)
    {
        operation = MCO_ENCYPHER;
    }

    while (offset < data_size)
    {
        mifareDesfire_cypherSingleBlockDes(key, data + offset, ivect, direction, operation);
        offset += 8;
    }
}

static void mifareDesfire_Cmac(BlueMifareDesfireKey_t *key, uint8_t *ivect, uint8_t *data, uint8_t len, uint8_t *cmac)
{
    uint8_t kbs;
    uint8_t bufferTmp[256];

    if (key->type == BlueMifareDesfireKeyType_Aes)
    {
        kbs = 16;
    }
    else
    {
        kbs = 8;
    }

    memcpy((void *)bufferTmp, (void *)data, len);

    if (cmac_way == 0)
    {
        if ((!len) || (len % kbs))
        {
            bufferTmp[len++] = 0x80;
            while (len % kbs)
            {
                bufferTmp[len++] = 0x00;
            }
            xor_1(key->cmac_sk2, bufferTmp + len - kbs, kbs);
        }
        else
        {
            xor_1(key->cmac_sk1, bufferTmp + len - kbs, kbs);
        }
    }
    else if (cmac_way == 3)
    {
        bufferTmp[len++] = 0x80;
        while (len % kbs)
        {
            bufferTmp[len++] = 0x00;
        }
        xor_1(key->cmac_sk2, bufferTmp + len - kbs, kbs);
    }
    else if (cmac_way == 2)
    {
        xor_1(key->cmac_sk1, bufferTmp + len - kbs, kbs);
    }

    if (key->type == BlueMifareDesfireKeyType_Aes)
    {
        mifareDesfire_cypherChainedBlocksAes((uint8_t *)key->data, ivect, bufferTmp, len, MCD_SEND, MCO_ENCYPHER);
    }
    else
    {
        mifareDesfire_cypherChainedBlocksDes(key, ivect, bufferTmp, len, MCD_SEND, MCO_ENCYPHER);
    }

    memcpy((void *)cmac, (void *)ivect, kbs);
}

static void mifareDesfire_CmacGenerateSubkeys(BlueMifareDesfireKey_t *key)
{
    uint8_t l[16];
    uint8_t ivect[16];
    uint8_t xor_2 = 0;
    uint8_t kbs;
    uint8_t R;

    if (key->type == BlueMifareDesfireKeyType_Aes)
    {
        kbs = 16;
        R = 0x87;
    }
    else
    {
        kbs = 8;
        R = 0x1B;
    }

    memset(l, 0, kbs);
    memset(ivect, 0, kbs);

    if (key->type == BlueMifareDesfireKeyType_Aes)
    {
        mifareDesfire_cypherChainedBlocksAes((uint8_t *)key->data, ivect, l, kbs,
                                             MCD_RECEIVE, MCO_ENCYPHER);
    }
    else
    {
        mifareDesfire_cypherChainedBlocksDes(key, ivect, l, kbs,
                                             MCD_RECEIVE, MCO_ENCYPHER);
    }

    // Used to compute CMAC on complete blocks
    memcpy((void *)key->cmac_sk1, (void *)l, kbs);
    xor_2 = l[0] & 0x80;
    lsl(key->cmac_sk1, kbs);

    if (xor_2)
    {
        key->cmac_sk1[kbs - 1] ^= R;
    }

    // Used to compute CMAC on the last block if non-complete
    memcpy((void *)key->cmac_sk2, (void *)key->cmac_sk1, kbs);
    xor_2 = key->cmac_sk1[0] & 0x80;
    lsl(key->cmac_sk2, kbs);
    if (xor_2)
    {
        key->cmac_sk2[kbs - 1] ^= R;
    }
}

static BlueReturnCode_t mifareDesfire_cryptoPreprocessData(BlueMifareDesfireTag_t *tag, uint8_t *data, uint8_t *nbytes, uint8_t offset, uint32_t communication_settings, uint8_t *res)
{
    uint8_t edl;
    uint8_t append_mac = 0xFF;

    if (*nbytes > MAX_BUFFER_SIZE_CRYPT)
    {
        return BlueReturnCode_Overflow;
    }

    switch (communication_settings & MDCM_MASK)
    {
    case MDCM_PLAIN:
    {
        memcpy((void *)res, (void *)data, *nbytes);

        append_mac = 0;
    }
        /* pass through */
    case MDCM_MACED:
    {
        if (!(communication_settings & CMAC_COMMAND))
        {
            break;
        }

        memcpy((void *)res, (void *)data, *nbytes);
        mifareDesfire_Cmac((BlueMifareDesfireKey_t *)&(tag->sessionKey), tag->ivect, res, *nbytes, tag->cmac);

        if (append_mac)
        {
            memcpy((void *)res, (void *)data, *nbytes);
            memcpy((void *)(res + *nbytes), (void *)tag->cmac, CMAC_LENGTH);
            *nbytes += CMAC_LENGTH;
        }

        break;
    }
    case MDCM_ENCIPHERED:
    {
        if (!(communication_settings & ENC_COMMAND))
        {
            break;
        }

        edl = mifareDesfire_encipheredDataLength(tag, *nbytes - offset, communication_settings) + offset;

        // Fill in the crypto buffer with data ...
        memcpy((void *)res, (void *)data, *nbytes);
        if (!(communication_settings & NO_CRC))
        {
            crc32_append(res, *nbytes);
            *nbytes += 4;
        }

        // ... and padding
        memset((void *)(res + *nbytes), 0, edl - *nbytes);

        *nbytes = edl;

        if (tag->sessionKey.type == BlueMifareDesfireKeyType_Aes)
        {
            mifareDesfire_cypherChainedBlocksAes(tag->sessionKey.data, tag->ivect, res + offset, *nbytes - offset, MCD_SEND, MCO_ENCYPHER);
        }

        else
        {
            mifareDesfire_cypherChainedBlocksDes((BlueMifareDesfireKey_t *)&tag->sessionKey, tag->ivect, res + offset, *nbytes - offset, MCD_SEND, MCO_ENCYPHER);
        }

        break;
    }
    default:
        return BlueReturnCode_InvalidArguments;
    }

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t mifareDesfire_cryptoPostprocessData(BlueMifareDesfireTag_t *tag, void *data, uint8_t *nbytes, uint32_t communication_settings, uint8_t *res)
{
    uint8_t first_cmac_byte;
    int32_t n;
    uint8_t verified = 0;
    int16_t crc_pos;
    uint8_t end_crc_pos;
    uint8_t x;
    uint32_t crc, crc_temp;
    uint8_t byte;
    uint8_t *pData = (uint8_t *)data;

    // Return directly if we just have a status code.
    if (1 == *nbytes)
    {
        res = (uint8_t *)data;
        return BlueReturnCode_Ok;
    }

    if (*nbytes > MAX_BUFFER_SIZE_CRYPT)
    {
        return BlueReturnCode_Overflow;
    }

    switch (communication_settings & MDCM_MASK)
    {
    case MDCM_PLAIN:
        /* pass through */
    case MDCM_MACED:
    {
        if (!(communication_settings & CMAC_COMMAND))
        {
            break;
        }

        if (communication_settings & NO_CRC)
        {
            (*nbytes)--;
        }

        if (communication_settings & CMAC_VERIFY)
        {
            if (*nbytes < 9)
            {
                return BlueReturnCode_MifareDesfireCmacNotReceived;
            }

            // frame structure
            //|plain data (*nbytes - 9)|cmac (8 bytes)|status (1 byte)|
            first_cmac_byte = (pData)[*nbytes - 9];
            // append status to the end of plain data
            (pData)[*nbytes - 9] = (pData)[*nbytes - 1];
        }

        n = (communication_settings & CMAC_VERIFY) ? 8 : 0;
        mifareDesfire_Cmac((BlueMifareDesfireKey_t *)&(tag->sessionKey), tag->ivect, (pData), (uint8_t)(*nbytes - n), tag->cmac);

        if (communication_settings & CMAC_VERIFY)
        {
            // place first CMAC byte to the right location for verify
            (pData)[*nbytes - 9] = first_cmac_byte;
            if (memcmp((void *)(tag->cmac), (void *)(pData + *nbytes - 9), 8))
            {
                return BlueReturnCode_MifareDesfireCmacNotVerified;
            }
            else
            {
                *nbytes -= 9;
                memcpy((void *)res, (void *)data, *nbytes);
            }
        }
        else
        {
            memcpy((void *)res, (void *)data, *nbytes);
        }

        break;
    }
    case MDCM_ENCIPHERED:
    {
        (*nbytes)--;

        memcpy((void *)res, (void *)data, *nbytes);

        if (tag->sessionKey.type == BlueMifareDesfireKeyType_Aes)
        {
            mifareDesfire_cypherChainedBlocksAes(tag->sessionKey.data, tag->ivect, res, *nbytes, MCD_RECEIVE, MCO_DECYPHER);
        }
        else
        {
            if (communication_settings & (NO_CRC | CRC_GLOBAL))
            {
                mifareDesfire_cypherChainedBlocksDes((BlueMifareDesfireKey_t *)&tag->sessionKey, tag->ivect, res, *nbytes, MCD_RECEIVE, MCO_DECYPHER_NO_CRC);
            }
            else
            {
                mifareDesfire_cypherChainedBlocksDes((BlueMifareDesfireKey_t *)&tag->sessionKey, tag->ivect, res, *nbytes, MCD_RECEIVE, MCO_DECYPHER);
            }
        }

        if (communication_settings & NO_CRC)
        {
            if (crc_found)
            {
                for (byte = 0; byte < crc_32_f[4]; byte++)
                {
                    crc_32_f[byte] = res[*nbytes - crc_32_f[4] + byte];
                }

                *nbytes -= crc_32_f[4];
            }

            // calculate CRC, but no verify it
            crc32(res, *nbytes, (uint8_t *)&crc, false);
            return 0;
        }

        /*
         * Look for the CRC and ensure it is followed by NULL padding.  We
         * can't start by the end because the CRC is supposed to be 0 when
         * verified, and accumulating 0's in it should not change it.
         */

        if (crc_found)
        {
            memmove(res + crc_32_f[4], res, *nbytes - crc_32_f[4]);
            memcpy(res, crc_32_f, crc_32_f[4]);
        }

        crc_pos = (int16_t)(*nbytes) - 16 - 3;
        if (crc_pos < 0)
        {
            /* Single block */
            crc_pos = 0;
        }
        memmove(res + crc_pos + 1, (void *)(res + crc_pos), (uint8_t)(*nbytes - crc_pos));
        ((uint8_t *)res)[crc_pos] = 0x00;
        crc_pos++;
        *nbytes += 1;

        crc_temp = crc32_global;

        do
        {
            end_crc_pos = (uint8_t)(crc_pos + 4);

            if (communication_settings & CRC_GLOBAL)
            {
                crc32_global = crc_temp;
                crc32(res, end_crc_pos, (uint8_t *)&crc, false);
            }
            else
            {
                crc32(res, end_crc_pos, (uint8_t *)&crc, true);
            }

            if (!crc)
            {
                verified = 0xFF;
                for (n = end_crc_pos; n < *nbytes - 1; n++)
                {
                    byte = ((uint8_t *)res)[n];
                    if (!((0x00 == byte) || ((0x80 == byte) && (n == end_crc_pos))))
                    {
                        verified = 0;
                    }
                }
            }
            if (verified)
            {
                *nbytes = (uint8_t)crc_pos;
            }
            else
            {
                x = ((uint8_t *)res)[crc_pos - 1];

                ((uint8_t *)res)[crc_pos - 1] = ((uint8_t *)res)[crc_pos];

                ((uint8_t *)res)[crc_pos] = x;

                crc_pos++;
            }
        } while (!verified && (end_crc_pos < *nbytes));

        if (!verified)
        {
            return BlueReturnCode_InvalidCrc;
        }

        break;
    }
    default:
        return BlueReturnCode_InvalidArguments;
    }

    return BlueReturnCode_Ok;
}

//
// Keys
//

static void mifareDesfire_UpdateKeySchedules(BlueMifareDesfireKey_t *key)
{
    if (BlueMifareDesfireKeyType_3k3Des == key->type)
    {
    }
}

static void mifareDesfire_InitDesKey(BlueMifareDesfireKey_t *key, const uint8_t *value)
{
    uint8_t i;
    key->type = BlueMifareDesfireKeyType_Des;

    memcpy(key->data, value, 8);
    memcpy(key->data + 8, value, 8);

    for (i = 0; i < 16; i++)
    {
        key->data[i] &= 0xFE;
    }

    mifareDesfire_UpdateKeySchedules(key);
}

static void mifareDesfire_Init2k3DesKey(BlueMifareDesfireKey_t *key, const uint8_t *value)
{
    uint8_t i;
    key->type = BlueMifareDesfireKeyType_2k3Des;

    memcpy(key->data, value, 16);

    for (i = 0; i < 8; i++)
    {
        key->data[i] &= 0xFE;
    }

    for (i = 8; i < 16; i++)
    {
        key->data[i] |= 0x01;
    }

    mifareDesfire_UpdateKeySchedules(key);
}

static void mifareDesfire_Init3k3DesKey(BlueMifareDesfireKey_t *key, const uint8_t *value)
{
    uint8_t i;
    key->type = BlueMifareDesfireKeyType_3k3Des;

    memcpy(key->data, value, 24);

    for (i = 0; i < 8; i++)
    {
        key->data[i] &= 0xFE;
    }

    mifareDesfire_UpdateKeySchedules(key);
}

static void mifareDesfire_InitAesKey(BlueMifareDesfireKey_t *key, const uint8_t *value, uint8_t version)
{
    memcpy((void *)(key->data), (void *)value, 16);
    key->type = BlueMifareDesfireKeyType_Aes;
    key->aesVersion = version;
}

static void mifareDesfire_InitSessionKey(uint8_t *rnda, uint8_t *rndb, BlueMifareDesfireTag_t *tag)
{
    uint8_t buffer[24];

    if (tag->sessionKey.type == BlueMifareDesfireKeyType_Aes)
    {
        memcpy((void *)buffer, (void *)rnda, 4);
        memcpy((void *)&buffer[4], (void *)rndb, 4);
        memcpy((void *)&buffer[8], (void *)&rnda[12], 4);
        memcpy((void *)&buffer[12], (void *)&rndb[12], 4);
        memcpy((void *)tag->sessionKey.data, (void *)buffer, 16);
    }
    else if (tag->sessionKey.type == BlueMifareDesfireKeyType_3k3Des)
    {
        memcpy(buffer, rnda, 4);
        memcpy(&buffer[4], rndb, 4);
        memcpy(&buffer[8], &rnda[6], 4);
        memcpy(&buffer[12], &rndb[6], 4);
        memcpy(&buffer[16], &rnda[12], 4);
        memcpy(&buffer[20], &rndb[12], 4);
        mifareDesfire_Init3k3DesKey((BlueMifareDesfireKey_t *)&tag->sessionKey, buffer);
    }
    else if (tag->sessionKey.type == BlueMifareDesfireKeyType_2k3Des)
    {
        memcpy(buffer, rnda, 4);
        memcpy(buffer + 4, rndb, 4);
        memcpy(buffer + 8, rnda + 4, 4);
        memcpy(buffer + 12, rndb + 4, 4);
        mifareDesfire_Init2k3DesKey((BlueMifareDesfireKey_t *)&tag->sessionKey, buffer);
    }
    else if (tag->sessionKey.type == BlueMifareDesfireKeyType_Des)
    {
        memcpy(buffer, rnda, 4);
        memcpy(&buffer[4], rndb, 4);
        mifareDesfire_InitDesKey((BlueMifareDesfireKey_t *)&tag->sessionKey, buffer);
    }
}

//
// Authenticate
//

static BlueReturnCode_t mifareDesfire_AuthenticateCommand(BlueMifareDesfireTag_t *tag, uint8_t auth_cmd, uint8_t key_no, BlueMifareDesfireKey_t *key)
{
    uint8_t res_length;
    uint8_t key_length;
    uint8_t i;
    uint16_t rand_nr;
    uint8_t token[32];

    memset((void *)tag->ivect, 0, MAX_CRYPTO_BLOCK_SIZE);

    tag->authenticatedKeyNo = 255;
    memset((void *)&(tag->sessionKey), 0, sizeof(BlueMifareDesfireKey_t));

    tag->sessionKey.type = key->type;

    uint8_t cmd[64];
    uint8_t res[256];

    cmd[0] = auth_cmd;
    cmd[1] = key_no;

    BLUE_ERROR_CHECK(mifareDesfire_Command(2, cmd, &res_length, res));

    if (res_length < 10)
    {
        if (res_length < 1)
        {
            return BlueReturnCode_NfcTransponderNoResult;
        }
        else if (res[1] == AUTHENTICATION_ERROR)
        {
            return BlueReturnCode_MifareDesfireWrongKeyType;
        }
        else if (res[1])
        {
            BLUE_LOG_DEBUG("Authentication failed on request with %d", (uint32_t)(0x0C00 + res[1]));
            return BlueReturnCode_NfcTransponderCommandError;
        }
    }

    key_length = res_length - 2;

    memcpy((void *)picc_rnd_b, (void *)res, key_length);

    if (auth_cmd == AUTHENTICATE_AES)
    {
        mifareDesfire_cypherChainedBlocksAes(key->data, tag->ivect, picc_rnd_b, key_length, MCD_RECEIVE, MCO_DECYPHER);
    }
    else
    {
        mifareDesfire_cypherChainedBlocksDes(key, tag->ivect, picc_rnd_b, key_length, MCD_RECEIVE, MCO_DECYPHER);
    }

    for (i = 0; i < 8; i++)
    {
        blueUtils_RandomVector((uint8_t *)&rand_nr, 2);
        memcpy((void *)&pcd_rnd_a[i * 2], (void *)&rand_nr, 2);
    }

    memcpy((void *)pcd_r_rnd_b, (void *)picc_rnd_b, key_length);
    rol(pcd_r_rnd_b, key_length);

    memcpy((void *)token, (void *)pcd_rnd_a, key_length);
    memcpy((void *)(token + key_length), (void *)pcd_r_rnd_b, key_length);

    if (auth_cmd == AUTHENTICATE_AES)
    {
        mifareDesfire_cypherChainedBlocksAes(key->data, tag->ivect, token, 2 * key_length, MCD_SEND, MCO_ENCYPHER);
    }
    else if (auth_cmd == AUTHENTICATE_ISO)
    {
        mifareDesfire_cypherChainedBlocksDes(key, tag->ivect, token, 2 * key_length, MCD_SEND, MCO_ENCYPHER);
    }

    cmd[0] = 0xAF;
    memcpy((void *)&cmd[1], (void *)token, 2 * key_length);
    BLUE_ERROR_CHECK(mifareDesfire_Command(2 * key_length + 1, cmd, &res_length, res));

    if (res_length < 10)
    {
        if (res_length < 1)
        {
            return BlueReturnCode_NfcTransponderNoResult;
        }
        else if (res[1] == AUTHENTICATION_ERROR)
        {
            return BlueReturnCode_MifareDesfireWrongKey;
        }
        else if (res[1])
        {
            BLUE_LOG_DEBUG("Authentication failed on token with %d", (uint32_t)(0x0C00 + res[1]));
            return BlueReturnCode_NfcTransponderCommandError;
        }
    }

    memcpy((void *)picc_rnd_a_s, (void *)res, key_length);

    if (auth_cmd == AUTHENTICATE_AES)
    {
        mifareDesfire_cypherChainedBlocksAes((uint8_t *)key->data, tag->ivect, picc_rnd_a_s, key_length, MCD_RECEIVE, MCO_DECYPHER);
    }
    else
    {
        mifareDesfire_cypherChainedBlocksDes(key, tag->ivect, picc_rnd_a_s, key_length, MCD_RECEIVE, MCO_DECYPHER);
    }

    memcpy((void *)pcd_rnd_a_s, (void *)pcd_rnd_a, key_length);
    rol(pcd_rnd_a_s, key_length);

    if (0 != memcmp((void *)pcd_rnd_a_s, (void *)picc_rnd_a_s, key_length))
    {
        return BlueReturnCode_MifareDesfireWrongKey;
    }

    tag->authenticatedKeyNo = key_no;

    mifareDesfire_InitSessionKey(pcd_rnd_a, picc_rnd_b, tag);

    memset((void *)tag->ivect, 0, MAX_CRYPTO_BLOCK_SIZE);

    if (auth_cmd != AUTHENTICATE_DES)
    {
        mifareDesfire_CmacGenerateSubkeys((BlueMifareDesfireKey_t *)&(tag->sessionKey));
    }

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t mifareDesfire_Authenticate(BlueMifareDesfireTag_t *const pTag, BlueMifareDesfireKeyType_t keyType, const uint8_t *const pKeyValue, uint8_t keyNo)
{
    BlueMifareDesfireKey_t key;

    switch (keyType)
    {
    case BlueMifareDesfireKeyType_3k3Des:
        mifareDesfire_Init3k3DesKey(&key, pKeyValue);
        return mifareDesfire_AuthenticateCommand(pTag, AUTHENTICATE_ISO, keyNo, &key);

    case BlueMifareDesfireKeyType_2k3Des:
        mifareDesfire_Init2k3DesKey(&key, pKeyValue);
        return mifareDesfire_AuthenticateCommand(pTag, AUTHENTICATE_ISO, keyNo, &key);

    case BlueMifareDesfireKeyType_Des:
        mifareDesfire_InitDesKey(&key, pKeyValue);
        return mifareDesfire_AuthenticateCommand(pTag, AUTHENTICATE_ISO, keyNo, &key);

    case BlueMifareDesfireKeyType_Aes:
        mifareDesfire_InitAesKey(&key, pKeyValue, 0x00);
        return mifareDesfire_AuthenticateCommand(pTag, AUTHENTICATE_AES, keyNo, &key);

    default:
        return BlueReturnCode_InvalidArguments;
    }
}

BlueReturnCode_t blueMifareDesfire_SelectMaster(BlueMifareDesfireTag_t *const pTag, BlueMifareDesfireKeyType_t keyType, const uint8_t *const pKeyValue)
{
    return blueMifareDesfire_SelectApplication(pTag, 0, keyType, pKeyValue, 0);
}

BlueReturnCode_t blueMifareDesfire_SelectMasterAutoProvision(BlueMifareDesfireTag_t *const pTag, BlueMifareDesfireKeyType_t keyType, const uint8_t *const pKeyValue)
{
    BlueReturnCode_t returnCode = blueMifareDesfire_SelectMaster(pTag, keyType, pKeyValue);

    //
    // If our error was wrong key type we'll try to authenticate now with the mifare desfire default des key.
    // If that succeeds we'll try to change the master key then to the desired picc master aes key.
    //
    if (returnCode == BlueReturnCode_MifareDesfireWrongKeyType)
    {
        BLUE_LOG_DEBUG("Try to authenticate with default des master picc key");

        memset(pTag, 0, sizeof(BlueMifareDesfireTag_t));

        const uint8_t desDefaultKey[16] = {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};

        BLUE_ERROR_CHECK_DEBUG(blueMifareDesfire_SelectMaster(pTag, BlueMifareDesfireKeyType_Des, desDefaultKey), "Use default des picc master key");

        //
        // Coming here means we've been able to get in with the picc master key so try to change to our aes picc master key now
        //
        BLUE_ERROR_CHECK_DEBUG(blueMifareDesfire_ChangeApplicationKey(pTag, keyType, pKeyValue, desDefaultKey, 0), "Change to new picc master key");

        //
        // Now try to authenticate again on picc master
        //
        memset(pTag, 0, sizeof(BlueMifareDesfireTag_t));

        BLUE_ERROR_CHECK_DEBUG(blueMifareDesfire_SelectMaster(pTag, keyType, pKeyValue), "Authenticate via new picc master key");

        return BlueReturnCode_Ok;
    }

    return returnCode;
}

BlueReturnCode_t blueMifareDesfire_SelectApplication(BlueMifareDesfireTag_t *const pTag, uint32_t aid, BlueMifareDesfireKeyType_t keyType, const uint8_t *const pKeyValue, uint8_t keyNo)
{
    memset(pTag, 0, sizeof(BlueMifareDesfireTag_t));

    uint8_t res[256];
    uint8_t resLen;

    uint8_t cmd[4] =
        {
            DES_SELECT_APPLICATION,
            0,
            0,
            0,
        };

    memcpy((void *)&cmd[1], (void *)&aid, 3);

    BLUE_ERROR_CHECK(mifareDesfire_Command(sizeof(cmd), cmd, &resLen, res));

    if (resLen > 0 && res[1])
    {
        BLUE_LOG_ERROR("Select application command failed with %d", (uint32_t)(0x0C00 + res[1]));

        if (res[1] == APPLICATION_NOT_FOUND)
        {
            return BlueReturnCode_NotFound;
        }

        return BlueReturnCode_NfcTransponderCommandError;
    }

    memset((void *)&(pTag->sessionKey), 0, sizeof(BlueMifareDesfireKey_t));

    pTag->aid = aid;
    pTag->hasAid = true;

    if (pKeyValue)
    {
        BLUE_ERROR_CHECK(mifareDesfire_Authenticate(pTag, keyType, pKeyValue, keyNo));
    }

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueMifareDesfire_ChangeApplicationKey(BlueMifareDesfireTag_t *const pTag, BlueMifareDesfireKeyType_t newKeyType, const uint8_t *const pNewKeyValue, const uint8_t *const pOldKeyValue, uint8_t keyNo)
{
    uint8_t cmdLen;
    uint8_t resLen;
    uint8_t sn;
    uint8_t cmd[42];
    uint8_t res[256];
    uint8_t newKeyLength;
    uint8_t commandBuffer[256];

    if (!pTag->hasAid)
    {
        return BlueReturnCode_MifareDesfireNoneOrInvalidAid;
    }

    keyNo &= 0x0F;

    cmd[0] = DES_CHANGE_KEY;

    if (pTag->aid == 0)
    {
        // card master key AID = 0x000000
        if (newKeyType == BlueMifareDesfireKeyType_Aes)
        {
            cmd[1] = 0x80;
        }
        else if (newKeyType == BlueMifareDesfireKeyType_3k3Des)
        {
            cmd[1] = 0x40;
        }
        else
        {
            cmd[1] = 0x00;
        }
    }
    else
    {
        cmd[1] = keyNo; // Application key number
    }

    if (newKeyType == BlueMifareDesfireKeyType_3k3Des)
    {
        newKeyLength = 24;
    }
    else
    {
        newKeyLength = 16;
    }

    cmdLen = 2 + newKeyLength;

    memcpy((void *)&cmd[2], (void *)pNewKeyValue, newKeyLength);

    if (newKeyType == BlueMifareDesfireKeyType_Aes)
    {
        cmd[cmdLen] = 0x42;
        cmdLen++;
    }

    resLen = pTag->authenticatedKeyNo;
    if (resLen != keyNo)
    {
        for (sn = 0; sn < newKeyLength; sn++)
        {
            cmd[2 + sn] ^= pOldKeyValue[sn];
        }
    }

    crc32_append(cmd, cmdLen);

    cmdLen += 4;

    if (resLen != keyNo)
    {
        crc32(pNewKeyValue, newKeyLength, &cmd[cmdLen], true);
        cmdLen += 4;
    }

    BLUE_ERROR_CHECK(mifareDesfire_cryptoPreprocessData(pTag, cmd, &cmdLen, 2, MDCM_ENCIPHERED | ENC_COMMAND | NO_CRC, commandBuffer));
    BLUE_ERROR_CHECK(mifareDesfire_Command(cmdLen, commandBuffer, &resLen, res));

    if (resLen == 2)
    {
        if (res[1])
        {
            BLUE_LOG_DEBUG("Change app key command failed with %d", (uint32_t)(0x0C00 + res[1]));
            return BlueReturnCode_NfcTransponderCommandError;
        }
    }

    res[resLen - 2] = 0x00;
    sn = resLen - 1;

    BLUE_ERROR_CHECK(mifareDesfire_cryptoPostprocessData(pTag, res, &sn, MDCM_PLAIN | CMAC_COMMAND | CMAC_VERIFY, commandBuffer));

    return BlueReturnCode_Ok;
}

//
// Utils
//

uint16_t blueMifareDesfire_GetFileAccessRights(int8_t readKeyNo, uint8_t writeKeyNo, uint8_t readWriteKeyNo, uint8_t changeKeyNo)
{
    return (uint16_t)(readKeyNo & 0x0F) << 12 | (uint16_t)(writeKeyNo & 0x0F) << 8 | (uint16_t)(readWriteKeyNo & 0x0F) << 4 | (changeKeyNo & 0x0F);
}

uint8_t blueMifareDesfire_GetKeySize(BlueMifareDesfireKeyType_t keyType)
{
    switch (keyType)
    {
    case BlueMifareDesfireKeyType_Des:
        return 8;
    case BlueMifareDesfireKeyType_2k3Des:
        return 16;
    case BlueMifareDesfireKeyType_3k3Des:
        return 24;
    case BlueMifareDesfireKeyType_Aes:
        return 16;
    default:
        return 0;
    }
}

BlueReturnCode_t blueMifareDesfire_ReadFreeMemory(BlueMifareDesfireTag_t *const pTag, uint32_t *const pFreeMemory)
{
    BlueMifareDesfireTag_t tag;
    uint8_t commandBuffer[256];
    uint8_t cmdLen;
    uint8_t resLen;
    uint8_t sn;
    uint8_t cmd[1];
    uint8_t res[6 + CMAC_LENGTH];

    cmd[0] = DES_FREE_MEM;
    cmdLen = 1;

    memset((void *)&tag, 0, sizeof(BlueMifareDesfireTag_t));
    BLUE_ERROR_CHECK(mifareDesfire_cryptoPreprocessData(pTag, cmd, &cmdLen, 0, MDCM_PLAIN | CMAC_COMMAND, commandBuffer));

    BLUE_ERROR_CHECK(mifareDesfire_Command(cmdLen, cmd, &resLen, res));

    res[resLen - 2] = 0x00;
    sn = resLen - 1;

    BLUE_ERROR_CHECK(mifareDesfire_cryptoPostprocessData(pTag, res, &sn, MDCM_PLAIN | CMAC_COMMAND | CMAC_VERIFY | MAC_VERIFY, commandBuffer));

    *pFreeMemory = 0;
    memcpy((void *)pFreeMemory, (void *)res, 3);

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueMifareDesfire_Format(BlueMifareDesfireTag_t *const pTag)
{
    if (!pTag->hasAid || pTag->aid != 0)
    {
        return BlueReturnCode_MifareDesfireNoneOrInvalidAid;
    }

    uint8_t cmdLen;
    uint8_t resLen;
    uint8_t sn;
    uint8_t cmd[1 + CMAC_LENGTH];
    uint8_t res[256];
    uint8_t commandBuffer[256];

    cmd[0] = DES_FORMAT_CARD;
    cmdLen = 1;

    BLUE_ERROR_CHECK(mifareDesfire_cryptoPreprocessData(pTag, cmd, &cmdLen, 0, MDCM_PLAIN | CMAC_COMMAND, commandBuffer));
    BLUE_ERROR_CHECK(mifareDesfire_Command(cmdLen, commandBuffer, &resLen, res));

    if (resLen == 2)
    {
        if (res[1])
        {
            BLUE_LOG_DEBUG("Format command failed with %d", (uint32_t)(0x0C00 + res[1]));
            return BlueReturnCode_NfcTransponderCommandError;
        }
    }

    res[resLen - 2] = 0x00;
    sn = resLen - 1;

    BLUE_ERROR_CHECK(mifareDesfire_cryptoPostprocessData(pTag, res, &sn, MDCM_PLAIN | CMAC_COMMAND | CMAC_VERIFY, commandBuffer));

    return BlueReturnCode_Ok;
}

//
// Application + File handling
//
BlueReturnCode_t blueMifareDesfire_CreateApplication(BlueMifareDesfireTag_t *pTag, uint32_t aid, uint8_t settings, BlueMifareDesfireKeyType_t keysType, uint8_t numberOfKeys)
{
    if (!pTag->hasAid || pTag->aid != 0)
    {
        return BlueReturnCode_MifareDesfireNoneOrInvalidAid;
    }

    // Prepare command to create application
    uint8_t commandBuffer[256];
    uint8_t cmd[22];
    uint8_t res[3 + CMAC_LENGTH];
    uint8_t cmdLen;
    uint8_t resLen;
    uint8_t sn;

    cmd[0] = DES_CREATE_APPLICATION;
    memcpy((void *)&cmd[1], (void *)&aid, 3);
    cmd[4] = settings & 0x0F;

    switch (keysType)
    {
    case BlueMifareDesfireKeyType_Des:
        cmd[5] = 0x00 | numberOfKeys;
        break;

    case BlueMifareDesfireKeyType_3k3Des:
        cmd[5] = 0x40 | numberOfKeys;
        break;

    case BlueMifareDesfireKeyType_Aes:
        cmd[5] = 0x80 | numberOfKeys;
        break;

    default:
        return BlueReturnCode_InvalidArguments;
    }

    cmdLen = 6;

    BLUE_ERROR_CHECK(mifareDesfire_cryptoPreprocessData(pTag, cmd, &cmdLen, 0, MDCM_PLAIN | CMAC_COMMAND, commandBuffer));
    BLUE_ERROR_CHECK(mifareDesfire_Command(cmdLen, commandBuffer, &resLen, res));

    if (resLen < 10)
    {
        if (res[1])
        {
            BLUE_LOG_DEBUG("Create application with aid=%d command failed with %d", aid, (uint32_t)(0x0C00 + res[1]));
            return BlueReturnCode_NfcTransponderCommandError;
        }
    }

    res[resLen - 2] = 0x00;
    sn = resLen - 1;

    BLUE_ERROR_CHECK(mifareDesfire_cryptoPostprocessData(pTag, res, &sn, MDCM_PLAIN | CMAC_COMMAND | CMAC_VERIFY | MAC_VERIFY, commandBuffer));

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueMifareDesfire_DeleteApplication(BlueMifareDesfireTag_t *pTag, uint32_t aid)
{
    if (aid == 0)
    {
        return BlueReturnCode_MifareDesfireNoneOrInvalidAid;
    }

    uint8_t commandBuffer[256];
    uint8_t cmd[4 + CMAC_LENGTH];
    uint8_t res[3 + CMAC_LENGTH];
    uint8_t cmdLen;
    uint8_t resLen;
    uint8_t sn = 0;

    cmd[0] = DES_DELETE_APPLICATION;
    memcpy((void *)&cmd[1], &aid, 3);

    cmdLen = 4;

    BLUE_ERROR_CHECK(mifareDesfire_cryptoPreprocessData(pTag, cmd, &cmdLen, 0, MDCM_PLAIN | CMAC_COMMAND, commandBuffer));
    BLUE_ERROR_CHECK(mifareDesfire_Command(cmdLen, commandBuffer, &resLen, res));

    if (resLen == 2)
    {
        if (res[1])
        {
            BLUE_LOG_DEBUG("Delete application with AID=%d command failed with %d", pTag->aid, (uint32_t)(0x0C00 + res[1]));
            return BlueReturnCode_NfcTransponderCommandError;
        }
    }

    res[resLen - 2] = 0x00;
    sn = resLen - 1;

    BLUE_ERROR_CHECK(mifareDesfire_cryptoPostprocessData(pTag, res, &sn, MDCM_PLAIN | CMAC_COMMAND | CMAC_VERIFY, commandBuffer));

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueMifareDesfire_CreateFile(BlueMifareDesfireTag_t *const pTag, uint8_t fileId, uint32_t fileSize, uint8_t communicationSettings, uint16_t accessRights)
{
    if (!pTag->hasAid || pTag->aid == 0)
    {
        return BlueReturnCode_MifareDesfireNoneOrInvalidAid;
    }

    uint8_t commandBuffer[256];
    uint8_t cmd[10 + CMAC_LENGTH];
    uint8_t res[3 + CMAC_LENGTH];
    uint8_t cmdLen;
    uint8_t resLen;
    uint8_t sn = 0;

    cmd[0] = DES_CREATE_STD_DATA_FILE;
    cmd[1] = fileId;
    cmd[2 + sn] = communicationSettings;

    memcpy((void *)&cmd[3 + sn], (void *)&accessRights, 2);
    memcpy((void *)&cmd[5 + sn], (void *)&fileSize, 3);

    cmdLen = 8 + sn;

    BLUE_ERROR_CHECK(mifareDesfire_cryptoPreprocessData(pTag, cmd, &cmdLen, 0, MDCM_PLAIN | CMAC_COMMAND, commandBuffer));
    BLUE_ERROR_CHECK(mifareDesfire_Command(cmdLen, commandBuffer, &resLen, res));

    if (resLen == 2)
    {
        if (res[1])
        {
            BLUE_LOG_DEBUG("Create std file with fileId=%d command failed with %d", fileId, (uint32_t)(0x0C00 + res[1]));
            return BlueReturnCode_NfcTransponderCommandError;
        }
    }

    res[resLen - 2] = 0x00;
    sn = resLen - 1;

    BLUE_ERROR_CHECK(mifareDesfire_cryptoPostprocessData(pTag, res, &sn, MDCM_PLAIN | CMAC_COMMAND | CMAC_VERIFY, commandBuffer));

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t mifareDesfire_WriteFileDataChunk(BlueMifareDesfireTag_t *const pTag, uint8_t command, uint8_t fileId, uint32_t offset, const uint8_t *const pData, uint32_t size, uint32_t communicationSettings)
{
    if (!pTag->hasAid || pTag->aid == 0)
    {
        return BlueReturnCode_MifareDesfireNoneOrInvalidAid;
    }

    uint8_t commandBuffer[256];
    uint8_t cmd[8 + 44 + CMAC_LENGTH];
    uint8_t res[64];
    uint32_t l_cmd_len;
    uint8_t cmdLen;
    uint8_t resLen;
    uint8_t sn;
    uint8_t bytes_sent, frame_length;

    l_cmd_len = 8 + size;

    if (l_cmd_len > sizeof(commandBuffer))
    {
        return BlueReturnCode_Overflow;
    }

    cmdLen = (uint8_t)l_cmd_len;

    if (size > MAX_BUFFER_SIZE_CRYPT)
    {
        return BlueReturnCode_Overflow;
    }

    commandBuffer[0] = command;
    commandBuffer[1] = fileId;
    memcpy((void *)&commandBuffer[2], (void *)&offset, 3);
    memcpy((void *)&commandBuffer[5], (void *)&size, 3);
    memcpy((void *)&commandBuffer[8], (void *)pData, (uint16_t)size);

    BLUE_ERROR_CHECK(mifareDesfire_cryptoPreprocessData(pTag, commandBuffer, &cmdLen, 8, communicationSettings | MAC_COMMAND | CMAC_COMMAND | ENC_COMMAND, commandBuffer));

    if (cmdLen <= 44)
    {
        frame_length = cmdLen;
        size = 0;
    }
    else
    {
        frame_length = 44;
        size = cmdLen - frame_length;
    }

    memcpy((void *)cmd, (void *)commandBuffer, frame_length);
    cmdLen = frame_length;
    bytes_sent = 0;
    while (1)
    {
        BLUE_ERROR_CHECK(mifareDesfire_Command(cmdLen, cmd, &resLen, res));

        bytes_sent += frame_length;

        if (resLen == 2)
        {
            if ((res[1] != OPERATION_OK) && (res[1] != ADDITIONAL_FRAME))
            {
                BLUE_LOG_DEBUG("Write file failed with %d at size=%d, bytes_sent=%d", (uint32_t)(0x0C00 + res[1]), size, bytes_sent);
                return BlueReturnCode_NfcTransponderCommandError;
            }
        }

        if (size == 0)
        {
            break;
        }

        if (size <= 44)
        {
            frame_length = (uint8_t)size;
            size = 0;
        }
        else
        {
            frame_length = 44;
            size -= frame_length;
        }

        cmd[0] = ADDITIONAL_FRAME;

        memcpy((void *)&cmd[1], (void *)(commandBuffer + bytes_sent), frame_length);
        cmdLen = 1 + frame_length;
    }

    res[resLen - 2] = 0x00;
    sn = resLen - 1;

    BLUE_ERROR_CHECK(mifareDesfire_cryptoPostprocessData(pTag, res, &sn, MDCM_PLAIN | CMAC_COMMAND | CMAC_VERIFY, commandBuffer));

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t mifareDesfire_WriteFileData(BlueMifareDesfireTag_t *const pTag, uint8_t command, uint8_t fileId, uint16_t offset, const uint8_t *const pData, uint16_t size, uint8_t communicationSettings)
{
    uint16_t written_data;
    uint16_t address;
    uint16_t bytes_to_write;

    address = offset;

    written_data = 0;

    if (command == DES_WRITE_DATA)
    {
        while (size > 0)
        {
            if (size > DATA_TRANSFER_CHUNK_SIZE)
            {
                bytes_to_write = DATA_TRANSFER_CHUNK_SIZE;
            }
            else
            {
                bytes_to_write = size;
            }

            BLUE_ERROR_CHECK(mifareDesfire_WriteFileDataChunk(pTag, command, fileId, address, pData + written_data, bytes_to_write, communicationSettings));

            written_data += bytes_to_write;
            address += bytes_to_write;
            size -= bytes_to_write;
        }

        return BlueReturnCode_Ok;
    }

    return BlueReturnCode_InvalidArguments;
}

BlueReturnCode_t blueMifareDesfire_WriteFile(BlueMifareDesfireTag_t *const pTag, uint8_t fileId, uint16_t offset, const uint8_t *const pData, uint16_t size, uint8_t communicationSettings)
{
    return mifareDesfire_WriteFileData(pTag, DES_WRITE_DATA, fileId, offset, pData, size, communicationSettings);
}

BlueReturnCode_t blueMifareDesfire_DeleteFile(BlueMifareDesfireTag_t *const pTag, uint8_t fileId)
{
    if (!pTag->hasAid || pTag->aid == 0)
    {
        return BlueReturnCode_MifareDesfireNoneOrInvalidAid;
    }

    uint8_t commandBuffer[256];
    uint8_t cmd[2 + CMAC_LENGTH];
    uint8_t res[3 + CMAC_LENGTH];
    uint8_t cmdLen;
    uint8_t resLen;
    uint8_t sn = 0;

    cmd[0] = DES_DELETE_FILE;
    cmd[1] = fileId;
    cmdLen = 2;

    BLUE_ERROR_CHECK(mifareDesfire_cryptoPreprocessData(pTag, cmd, &cmdLen, 0, MDCM_PLAIN | CMAC_COMMAND, commandBuffer));
    BLUE_ERROR_CHECK(mifareDesfire_Command(cmdLen, commandBuffer, &resLen, res));

    if (resLen == 2)
    {
        if (res[1])
        {
            BLUE_LOG_DEBUG("Delete std file with fileId=%d command failed with %d", fileId, (uint32_t)(0x0C00 + res[1]));
            return BlueReturnCode_NfcTransponderCommandError;
        }
    }

    res[resLen - 2] = 0x00;
    sn = resLen - 1;

    BLUE_ERROR_CHECK(mifareDesfire_cryptoPostprocessData(pTag, res, &sn, MDCM_PLAIN | CMAC_COMMAND | CMAC_VERIFY, commandBuffer));

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t mifareDesfire_ReadFileDataChunk(BlueMifareDesfireTag_t *const pTag, uint8_t command, uint8_t fileId, uint32_t offset, uint8_t *const pData, uint32_t size, uint32_t communicationSettings, uint16_t recordSize)
{
    if (!pTag->hasAid || pTag->aid == 0)
    {
        return BlueReturnCode_MifareDesfireNoneOrInvalidAid;
    }

    uint8_t commandBuffer[256];
    uint8_t cmd[8 + 44 + CMAC_LENGTH];
    uint8_t cmdLen;
    uint8_t cmd_2[34];
    uint8_t resLen;
    uint8_t sn;
    uint8_t cryptoStatus;
    uint8_t bytesReceived;
    bool firstFrame = true;

    if (size > MAX_BUFFER_SIZE_CRYPT)
    {
        return BlueReturnCode_Overflow;
    }

    cmd[0] = command;
    cmd[1] = fileId;
    memcpy((void *)&cmd[2], (void *)&offset, 3);
    memcpy((void *)&cmd[5], (void *)&size, 3);
    cmdLen = 8;

    memset(commandBuffer, 0, sizeof(commandBuffer));
    memset(cmd_2, 0, sizeof(cmd_2));

    if (command == DES_READ_RECORDS)
    {
        size *= recordSize;
        crc32_global = 0xFFFFFFFF;
        // crc16_global = 0x6363;
        crc_found = false;
    }

    BLUE_ERROR_CHECK(mifareDesfire_cryptoPreprocessData(pTag, cmd, &cmdLen, 8, MDCM_PLAIN | CMAC_COMMAND, cmd_2));

    bytesReceived = 0;

    if (recordSize % 16)
    {
        cmac_way = 1;
    }
    else
    {
        cmac_way = 2;
    }

    do
    {

        if (command == DES_READ_DATA)
        {
            cryptoStatus = bytesReceived;
        }
        else
        {
            cryptoStatus = 0;
        }

        BLUE_ERROR_CHECK(mifareDesfire_Command(cmdLen, cmd_2, &resLen, &commandBuffer[cryptoStatus]));

        cmd_2[0] = commandBuffer[cryptoStatus + resLen - 1];

        switch (cmd_2[0])
        {
        case OPERATION_OK:
        {
            cmdLen = 0;
            if (firstFrame)
            {
                cmac_way = 0;
            }
            else if (cmac_way == 1)
            {
                cmac_way = 3;
            }
            break;
        }
        case ADDITIONAL_FRAME:
        {
            cmdLen = 1;
            break;
        }
        default:
        {
            cmac_way = 0;
            BLUE_LOG_DEBUG("Read file pData failed with %d", (uint32_t)(0x0C00 + cmd_2[0]));
            return BlueReturnCode_NfcTransponderCommandError;
        }
        }

        resLen -= 2;
        sn = cryptoStatus;

        if (command == DES_READ_RECORDS)
        {
            if (cmd_2[0] == ADDITIONAL_FRAME)
            {
                firstFrame = false;
                communicationSettings |= CMAC_COMMAND | NO_CRC;

                if (bytesReceived + resLen > size)
                {
                    crc_32_f[4] = (uint8_t)(bytesReceived + resLen - size);
                    crc_found = true;
                }
                resLen++;

                int error = mifareDesfire_cryptoPostprocessData(pTag, &commandBuffer[2], &resLen, communicationSettings, commandBuffer);
                if (error < 0)
                {
                    cmac_way = 0;
                    return error;
                }
            }
        }
        else
        {
            memmove(&commandBuffer[bytesReceived], (void *)&commandBuffer[sn], resLen);
        }

        bytesReceived += resLen;

    } while (cmdLen);

    if (command == DES_READ_RECORDS)
    {
        bytesReceived = resLen;
    }

    commandBuffer[bytesReceived] = 0x00;
    sn = bytesReceived + 1;

    communicationSettings &= 0x03;
    communicationSettings |= CMAC_COMMAND | CMAC_VERIFY | MAC_VERIFY;

    if (command == DES_READ_RECORDS)
    {
        communicationSettings |= CRC_GLOBAL;
    }

    int error = mifareDesfire_cryptoPostprocessData(pTag, commandBuffer, &sn, communicationSettings, commandBuffer);

    cmac_way = 0;

    if (error < 0)
    {
        return error;
    }

    if (command == DES_READ_RECORDS)
    {
        return BlueReturnCode_Ok;
    }

    if (sn < size)
    {
        return BlueReturnCode_EOF;
    }

    memcpy(pData, (void *)commandBuffer, size);

    return BlueReturnCode_Ok;
}

static BlueReturnCode_t mifareDesfire_ReadFileData(BlueMifareDesfireTag_t *const pTag, uint8_t command, uint8_t fileId, uint16_t offset, uint8_t *const pData, uint16_t size, uint8_t communicationSettings)
{
    uint16_t address;
    uint16_t bytes_to_read;
    uint16_t read_data = 0;

    address = offset;

    if (command == DES_READ_DATA)
    {
        while (size > 0)
        {
            if (size > DATA_TRANSFER_CHUNK_SIZE)
            {
                bytes_to_read = DATA_TRANSFER_CHUNK_SIZE;
            }
            else
            {
                bytes_to_read = size;
            }

            BLUE_ERROR_CHECK(mifareDesfire_ReadFileDataChunk(pTag, command, fileId, address, pData + read_data, bytes_to_read, communicationSettings, 0));

            read_data += bytes_to_read;
            address += bytes_to_read;
            size -= bytes_to_read;
        }

        return BlueReturnCode_Ok;
    }

    return BlueReturnCode_InvalidArguments;
}

BlueReturnCode_t blueMifareDesfire_ReadFile(BlueMifareDesfireTag_t *const pTag, uint8_t fileId, uint16_t offset, uint8_t *const pData, uint16_t size, uint8_t communicationSettings)
{
    return mifareDesfire_ReadFileData(pTag, DES_READ_DATA, fileId, offset, pData, size, communicationSettings);
}

BlueReturnCode_t blueMifareDesfire_GetFileSettings(BlueMifareDesfireTag_t *const pTag, uint8_t fileId, BlueMifareDesfireFileSettings_t *const pFileSettings)
{
    if (!pTag->hasAid || pTag->aid == 0)
    {
        return BlueReturnCode_MifareDesfireNoneOrInvalidAid;
    }

    uint8_t cmdLen;
    uint8_t resLen;
    uint8_t sn;
    uint8_t cmd[2 + CMAC_LENGTH];
    uint8_t res[20 + CMAC_LENGTH];
    uint8_t commandBuffer[256];

    cmd[0] = DES_GET_FILE_SETTINGS;
    cmd[1] = fileId;
    cmdLen = 2;

    BLUE_ERROR_CHECK(mifareDesfire_cryptoPreprocessData(pTag, cmd, &cmdLen, 0, MDCM_PLAIN | CMAC_COMMAND, commandBuffer));

    BLUE_ERROR_CHECK(mifareDesfire_Command(cmdLen, commandBuffer, &resLen, res));

    if (resLen == 2)
    {
        if (res[1])
        {
            BLUE_LOG_DEBUG("Get file settings with fileId=%d command failed with %d", fileId, (uint32_t)(0x0C00 + res[1]));
            return BlueReturnCode_NfcTransponderCommandError;
        }
    }

    res[resLen - 2] = 0x00;
    sn = resLen - 1;

    BLUE_ERROR_CHECK(mifareDesfire_cryptoPostprocessData(pTag, res, &sn, MDCM_PLAIN | CMAC_COMMAND | CMAC_VERIFY, commandBuffer));

    memset(pFileSettings, 0, sizeof(BlueMifareDesfireFileSettings_t));

    memcpy(&pFileSettings->fileSize, &commandBuffer[4], 3);

    return BlueReturnCode_Ok;
}

BlueReturnCode_t blueMifareDesfire_ChangeFileSettings(BlueMifareDesfireTag_t *const pTag, uint8_t fileId, uint8_t communicationSettings, uint16_t accessRights)
{
    if (!pTag->hasAid || pTag->aid == 0)
    {
        return BlueReturnCode_MifareDesfireNoneOrInvalidAid;
    }

    uint8_t cmdLen = 0;
    uint8_t resLen = 0;
    uint8_t sn = 0;
    uint8_t cmd[2 + CMAC_LENGTH];
    uint8_t res[20 + CMAC_LENGTH];
    uint8_t commandBuffer[256];

    cmd[0] = DES_CHANGE_FILE_SETTINGS;
    cmd[1] = fileId;
    cmd[2 + sn] = communicationSettings;
    memcpy((void *)&cmd[3 + sn], (void *)&accessRights, 2);

    cmdLen = 5 + sn;

    BLUE_ERROR_CHECK(mifareDesfire_cryptoPreprocessData(pTag, cmd, &cmdLen, 2, MDCM_ENCIPHERED | ENC_COMMAND, commandBuffer));

    BLUE_ERROR_CHECK(mifareDesfire_Command(cmdLen, commandBuffer, &resLen, res));

    if (resLen == 2)
    {
        if (res[1])
        {
            BLUE_LOG_DEBUG("Get file settings with fileId=%d command failed with %d", fileId, (uint32_t)(0x0C00 + res[1]));
            return BlueReturnCode_NfcTransponderCommandError;
        }
    }

    res[resLen - 2] = 0x00;
    sn = resLen - 1;

    BLUE_ERROR_CHECK(mifareDesfire_cryptoPostprocessData(pTag, res, &sn, MDCM_PLAIN | CMAC_COMMAND | CMAC_VERIFY, commandBuffer));

    return BlueReturnCode_Ok;
}
