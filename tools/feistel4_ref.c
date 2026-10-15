/* feistel4_ref.c - Implementacion de referencia de Feistel4 (Fig. 1 del enunciado)
 * con una CLI para cifrar/descifrar archivos y generar vectores de prueba.
 *
 *   feistel4_ref enc|dec <llave_hex_32> <entrada> <salida>
 *   feistel4_ref vectors <n> <llave_hex_32>      (imprime n lineas "L R cL cR")
 *
 * Convencion de bloque: L = bytes 0..3, R = bytes 4..7 (big-endian). El archivo
 * se rellena con ceros hasta un multiplo de 8 bytes.
 * La llave son 32 digitos hex = 4 subllaves de 32 bits (K0..K3, big-endian). */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ROL32(x, r) (((x) << (r)) | ((x) >> (32 - (r))))

/* Funcion de ronda F: rotacion + suma modular 2^32, combinada con XOR */
static uint32_t feistel4_F(uint32_t x, uint32_t k) {
    uint32_t t = ROL32(x, 5) + k;
    return t ^ ROL32(x, 13);
}

/* Cifrado de un bloque de 64 bits (L, R) con red Feistel de 4 rondas */
static void feistel4_encrypt(uint32_t *L, uint32_t *R, const uint32_t key[4]) {
    for (int i = 0; i < 4; ++i) {
        uint32_t temp = *R;
        *R = *L ^ feistel4_F(*R, key[i]);
        *L = temp;
    }
}

/* Descifrado: se recorren las mismas 4 subllaves en orden inverso */
static void feistel4_decrypt(uint32_t *L, uint32_t *R, const uint32_t key[4]) {
    for (int i = 3; i >= 0; --i) {
        uint32_t temp = *L;
        *L = *R ^ feistel4_F(*L, key[i]);
        *R = temp;
    }
}

static int parse_key(const char *s, uint32_t key[4]) {
    if (strlen(s) != 32) return -1;
    for (int i = 0; i < 4; i++) {
        char buf[9];
        memcpy(buf, s + 8 * i, 8);
        buf[8] = 0;
        char *end;
        key[i] = (uint32_t)strtoul(buf, &end, 16);
        if (*end) return -1;
    }
    return 0;
}

static uint32_t be32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}
static void put_be32(uint8_t *p, uint32_t v) {
    p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v;
}

int main(int argc, char **argv) {
    uint32_t key[4];
    if (argc >= 4 && strcmp(argv[1], "vectors") == 0) {
        int n = atoi(argv[2]);
        if (parse_key(argv[3], key)) { fprintf(stderr, "llave invalida\n"); return 2; }
        uint32_t s = 0x12345678u;
        for (int i = 0; i < n; i++) {
            s = s * 1664525u + 1013904223u; uint32_t L = s;
            s = s * 1664525u + 1013904223u; uint32_t R = s;
            if (i == 0) { L = 0; R = 0; }
            uint32_t cl = L, cr = R;
            feistel4_encrypt(&cl, &cr, key);
            printf("%08x%08x%08x%08x\n", L, R, cl, cr);
        }
        return 0;
    }
    if (argc != 5 || (strcmp(argv[1], "enc") && strcmp(argv[1], "dec"))) {
        fprintf(stderr, "uso: %s enc|dec <llave_hex_32> <in> <out>\n       %s vectors <n> <llave_hex_32>\n", argv[0], argv[0]);
        return 2;
    }
    if (parse_key(argv[2], key)) { fprintf(stderr, "llave invalida\n"); return 2; }
    FILE *in = fopen(argv[3], "rb");
    if (!in) { perror(argv[3]); return 1; }
    fseek(in, 0, SEEK_END); long n = ftell(in); fseek(in, 0, SEEK_SET);
    long padded = (n + 7) / 8 * 8;
    uint8_t *buf = calloc(padded ? padded : 8, 1);
    if (fread(buf, 1, n, in) != (size_t)n) { perror("lectura"); return 1; }
    fclose(in);
    for (long i = 0; i < padded; i += 8) {
        uint32_t L = be32(buf + i), R = be32(buf + i + 4);
        if (argv[1][0] == 'e') feistel4_encrypt(&L, &R, key); else feistel4_decrypt(&L, &R, key);
        put_be32(buf + i, L); put_be32(buf + i + 4, R);
    }
    FILE *out = fopen(argv[4], "wb");
    if (!out) { perror(argv[4]); return 1; }
    fwrite(buf, 1, padded, out);
    fclose(out); free(buf);
    return 0;
}
