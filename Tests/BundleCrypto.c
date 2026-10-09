#include <openssl/provider.h>
#include <openssl/evp.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
    assert(argc == 2);
    assert(OSSL_PROVIDER_set_default_search_path(NULL, argv[1]));
    OSSL_PROVIDER *legacy = OSSL_PROVIDER_load(NULL, "legacy");
    assert(legacy);
    OSSL_PROVIDER *normal = OSSL_PROVIDER_load(NULL, "default");
    assert(normal);
    EVP_MD *md4 = EVP_MD_fetch(NULL, "MD4", NULL); assert(md4);
    const unsigned char expected[] = {0xa4,0x48,0x01,0x7a,0xaf,0x21,0xd8,0x52,0x5f,0xc1,0x0a,0xe8,0x7a,0xa6,0x72,0x9d};
    unsigned char result[32]; unsigned int count = 0;
    assert(EVP_Digest("abc", 3, result, &count, md4, NULL));
    assert(count == 16 && memcmp(result, expected, 16) == 0);
    EVP_MD_free(md4); OSSL_PROVIDER_unload(legacy); OSSL_PROVIDER_unload(normal);
    puts("Bundled OpenSSL provider and Windows NTLM digest primitive passed");
}
