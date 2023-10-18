#ifndef USER_SETTINGS_BASE_H
#define USER_SETTINGS_BASE_H

//
// -- WolfSSL / WolfCrypt setup
//

//
// General stuff
//
#define WOLFCRYPT_ONLY
#define SINGLE_THREADED
#define WOLFSSL_STATIC_MEMORY

// Encryption stuff
#define HAVE_ENCRYPT_THEN_MAC
#define HAVE_ECC
#define HAVE_ECC_SIGN
#define HAVE_ECC_VERIFY
#define HAVE_ECC_ENCRYPT
#define HAVE_ECC_CHECK_KEY
#define HAVE_ECC_DHE
#define HAVE_ECC_KEY_IMPORT
#define HAVE_ECC_KEY_EXPORT
#define ECC_SHAMIR
#define ECC_TIMING_RESISTANT
#define TFM_TIMING_RESISTANT
#define HAVE_HKDF
#define ECC_USER_CURVES
#define WOLFSSL_ECIES_ISO18033
#define WOLFSSL_DES_ECB
// #define HAVE_AES_ECB
// #define WOLFSSL_AES_DIRECT

#define DEFAULT_ECC_KEY_CURVE ECC_SECP256R1
#define DEFAULT_ECC_KEY_CURVE_SIZE 32

// Setup math stuff
#ifdef WOLFSSL_SP_MATH
#define WOLFSSL_SP_MATH_ALL
#define WOLFSSL_HAVE_SP_DH
#define WOLFSSL_HAVE_SP_ECC
#define WOLFSSL_SP_SMALL
#define WOLFSSL_SP_NO_MALLOC
#define WOLFSSL_SP_NO_2048
#define WOLFSSL_SP_NO_3072
#define SP_INT_BITS 256
#else
#define TFM_ECC256
#endif

// Remove unnecessary or not available features
#define NO_WOLFSSL_CLIENT
#define NO_WOLFSSL_SERVER
#define NO_FILESYSTEM
#define NO_ERROR_STRINGS
#define NO_DSA
#define NO_MD4
#define NO_MD5
#define NO_SHA
#define NO_PSK
#define NO_PWDBASED
#define NO_RC4
#define NO_SESSION_CACHE
#define NO_TLS
#define NO_RSA
#define NO_DH
#define NO_ASN_TIME
#define NO_AES_192
#define NO_AES_256
#define WC_NO_RSA_OAEP
#define NO_DEV_URANDOM
#define NO_WOLFSSL_DIR
#define NO_SESSION_CACHE
#define WOLFSSL_NO_SIGALG
#define NO_RESUME_SUITE_CHECK
#define NO_OLD_TLS
#define WOLFSSL_AEAD_ONLY
#define WOLFSSL_NO_TLS12
#define WOLFSSL_SP_NO_2048
#define WOLFSSL_SP_NO_3072

#define XTIME(t) NULL
#endif
