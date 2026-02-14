#ifndef ZIVPN_CRYPTO_H
#define ZIVPN_CRYPTO_H

#include <stddef.h>

void crypto_init(void);
int encrypt_packet(unsigned char *out, const unsigned char *in, size_t inlen, const unsigned char *key);
int decrypt_packet(unsigned char *out, const unsigned char *in, size_t inlen, const unsigned char *key);

#endif
