#include "crypto.h"
#include <string.h>
#include <android/log.h>

#define TAG "ZIVPN_Crypto"

#ifdef HAVE_SODIUM
#include <sodium.h>
#endif

void crypto_init(void) {
#ifdef HAVE_SODIUM
    if (sodium_init() < 0) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "libsodium initialization failed");
        return;
    }
    __android_log_print(ANDROID_LOG_INFO, TAG, "libsodium initialized");

    // Check for hardware crypto support
    #ifdef __ARM_FEATURE_CRYPTO
    __android_log_print(ANDROID_LOG_INFO, TAG, "ARM Crypto Extensions enabled");
    #endif

    #ifdef __ARM_NEON
    __android_log_print(ANDROID_LOG_INFO, TAG, "ARM NEON SIMD enabled");
    #endif
#else
    __android_log_print(ANDROID_LOG_WARN, TAG, "libsodium not enabled/linked");
#endif
}

int encrypt_packet(unsigned char *out, const unsigned char *in, size_t inlen, const unsigned char *key) {
#ifdef HAVE_SODIUM
    unsigned char nonce[crypto_aead_chacha20poly1305_ietf_NPUBBYTES];
    randombytes_buf(nonce, sizeof(nonce));

    // Prepend nonce to ciphertext
    memcpy(out, nonce, sizeof(nonce));

    unsigned long long outlen;
    int res = crypto_aead_chacha20poly1305_ietf_encrypt(
        out + sizeof(nonce), &outlen,
        in, inlen,
        NULL, 0,
        NULL, nonce, key
    );
    if (res != 0) return -1;

    return (int)(sizeof(nonce) + outlen);
#else
    return -1;
#endif
}

int decrypt_packet(unsigned char *out, const unsigned char *in, size_t inlen, const unsigned char *key) {
#ifdef HAVE_SODIUM
    if (inlen < crypto_aead_chacha20poly1305_ietf_NPUBBYTES + crypto_aead_chacha20poly1305_ietf_ABYTES) {
        return -1;
    }

    const unsigned char *nonce = in;
    const unsigned char *ciphertext = in + crypto_aead_chacha20poly1305_ietf_NPUBBYTES;
    unsigned long long ciphertext_len = inlen - crypto_aead_chacha20poly1305_ietf_NPUBBYTES;

    unsigned long long outlen;
    int res = crypto_aead_chacha20poly1305_ietf_decrypt(
        out, &outlen,
        NULL,
        ciphertext, ciphertext_len,
        NULL, 0,
        nonce, key
    );
    if (res != 0) return -1;

    return (int)outlen;
#else
    return -1;
#endif
}
