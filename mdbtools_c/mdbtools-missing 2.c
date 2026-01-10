/*
 * mdbtools-missing.c - Missing function implementations for iOS
 * 
 * Provides minimal implementations of mdbtools utility functions
 * that aren't critical for basic parsing functionality.
 */

#include "mdbtools.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

/* Global options - minimal implementation */
static unsigned long mdb_options = 0;

/* Debug function - matches mdbtools.h signature */
void mdb_debug(int klass, char *fmt, ...)
{
#if MDB_DEBUG
    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    fprintf(stderr, "\n");
    va_end(args);
#else
    // Suppress unused parameter warnings
    (void)klass;
    (void)fmt;
#endif
}

/* Get option value */
int mdb_get_option(unsigned long optnum)
{
    return (mdb_options & optnum) ? 1 : 0;
}

/* Buffer dump for debugging - minimal implementation */
void mdb_buffer_dump(const void *buf, off_t start, size_t len)
{
#if MDB_DEBUG
    const unsigned char *p = (const unsigned char *)buf + start;
    size_t i, j;
    
    for (i = 0; i < len; i += 16) {
        fprintf(stderr, "%08lx: ", (unsigned long)(start + i));
        
        // Hex dump
        for (j = 0; j < 16 && (i + j) < len; j++) {
            fprintf(stderr, "%02x ", p[i + j]);
        }
        
        // Padding
        for (; j < 16; j++) {
            fprintf(stderr, "   ");
        }
        
        fprintf(stderr, " ");
        
        // ASCII dump
        for (j = 0; j < 16 && (i + j) < len; j++) {
            unsigned char c = p[i + j];
            fprintf(stderr, "%c", (c >= 32 && c < 127) ? c : '.');
        }
        
        fprintf(stderr, "\n");
    }
#else
    (void)buf;
    (void)start;
    (void)len;
#endif
}

/* Character encoding conversion - simplified for iOS */

/* Global target charset (default UTF-8) */
static const char *target_charset = "UTF-8";

const char *mdb_target_charset(MdbHandle *mdb)
{
    (void)mdb;
    return target_charset;
}

/* Initialize character conversion - minimal implementation for iOS */
void mdb_iconv_init(MdbHandle *mdb)
{
    // On iOS, we'll just use UTF-8
    // No actual iconv initialization needed since we'll do simple conversion
    (void)mdb;
}

/* Close character conversion */
void mdb_iconv_close(MdbHandle *mdb)
{
    // Nothing to clean up in our simple implementation
    (void)mdb;
}

/* Convert Unicode (UTF-16LE) to ASCII/UTF-8 - matches mdbtools.h signature */
int mdb_unicode2ascii(MdbHandle *mdb, const char *src, size_t slen, char *dest, size_t dlen)
{
    size_t i, j = 0;
    
    (void)mdb; // unused in simple implementation
    
    if (!src || !dest || dlen == 0) {
        if (dest && dlen > 0) dest[0] = '\0';
        return 0;
    }
    
    // Simple conversion: Microsoft Access uses UTF-16LE (little-endian)
    // For basic ASCII compatibility, just take the low byte of each character
    for (i = 0; i < slen && j < dlen - 1; i += 2) {
        unsigned char low = (unsigned char)src[i];
        unsigned char high = (i + 1 < slen) ? (unsigned char)src[i + 1] : 0;
        
        // If it's a simple ASCII character (high byte is 0)
        if (high == 0 && low < 128) {
            dest[j++] = low;
        } else if (high == 0 && low != 0) {
            // Extended ASCII - keep it
            dest[j++] = low;
        } else {
            // Unicode character - replace with '?'
            dest[j++] = '?';
        }
    }
    
    dest[j] = '\0';
    return (int)j;
}

/* ASCII to Unicode conversion - stub */
int mdb_ascii2unicode(MdbHandle *mdb, const char *src, size_t slen, char *dest, size_t dlen)
{
    size_t i, j = 0;
    
    (void)mdb;
    
    if (!src || !dest || dlen == 0) {
        return 0;
    }
    
    // Convert ASCII to UTF-16LE (add null high byte)
    for (i = 0; i < slen && j < dlen - 1; i++) {
        if (j + 1 < dlen) {
            dest[j++] = src[i];   // Low byte
            dest[j++] = 0;        // High byte (0 for ASCII)
        }
    }
    
    return (int)j;
}

/* RC4 encryption - based on usage in file.c */
void mdbi_rc4(unsigned char *key, size_t key_len, unsigned char *data, size_t data_len)
{
    // Simple RC4 implementation for database decryption
    unsigned char s[256];
    unsigned int i, j, k, t;
    
    // Key-scheduling algorithm (KSA)
    for (i = 0; i < 256; i++) {
        s[i] = (unsigned char)i;
    }
    
    j = 0;
    for (i = 0; i < 256; i++) {
        j = (j + s[i] + key[i % key_len]) % 256;
        // Swap s[i] and s[j]
        t = s[i];
        s[i] = s[j];
        s[j] = (unsigned char)t;
    }
    
    // Pseudo-random generation algorithm (PRGA)
    i = j = 0;
    for (k = 0; k < data_len; k++) {
        i = (i + 1) % 256;
        j = (j + s[i]) % 256;
        // Swap s[i] and s[j]
        t = s[i];
        s[i] = s[j];
        s[j] = (unsigned char)t;
        
        // XOR with keystream
        data[k] ^= s[(s[i] + s[j]) % 256];
    }
}
