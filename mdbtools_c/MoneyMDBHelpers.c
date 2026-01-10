#include "MoneyMDBHelpers.h"
#include <stdlib.h>

MdbHandle* money_mdb_open(const char* path) {
    return mdb_open(path, MDB_NOFLAGS);
}

void money_mdb_close(MdbHandle* mdb) {
    if (mdb) mdb_close(mdb);
}

MdbTableDef* money_mdb_open_acct(MdbHandle* mdb) {
    return mdb_read_table_by_name(mdb, "ACCT", MDB_TABLE);
}

int money_mdb_num_columns(MdbTableDef* table) {
    return table ? table->num_cols : 0;
}

MdbSQL* money_mdb_run_query(const char* sql) {
    MdbSQL *sqlh = mdb_sql_init();   // no args in 1.0.1
    if (!sqlh) return NULL;
    MdbSQL *result = mdb_sql_run_query(sqlh, sql);
    // Note: don’t call mdb_sql_exit(sqlh) here if you want to use result
    return result;
}
/* ========== Missing mdbtools functions implementation ========== */

#include <stdio.h>
#include <stdarg.h>
#include <string.h>

/* Global options */
static unsigned long mdb_options = 0;

void mdb_debug(int klass, char *fmt, ...) {
#if MDB_DEBUG
    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    fprintf(stderr, "\n");
    va_end(args);
#else
    (void)klass; (void)fmt;
#endif
}

int mdb_get_option(unsigned long optnum) {
    return (mdb_options & optnum) ? 1 : 0;
}

void mdb_buffer_dump(const void *buf, off_t start, size_t len) {
#if MDB_DEBUG
    const unsigned char *p = (const unsigned char *)buf + start;
    size_t i, j;
    for (i = 0; i < len; i += 16) {
        fprintf(stderr, "%08lx: ", (unsigned long)(start + i));
        for (j = 0; j < 16 && (i + j) < len; j++)
            fprintf(stderr, "%02x ", p[i + j]);
        for (; j < 16; j++)
            fprintf(stderr, "   ");
        fprintf(stderr, " ");
        for (j = 0; j < 16 && (i + j) < len; j++) {
            unsigned char c = p[i + j];
            fprintf(stderr, "%c", (c >= 32 && c < 127) ? c : '.');
        }
        fprintf(stderr, "\n");
    }
#else
    (void)buf; (void)start; (void)len;
#endif
}

static const char *target_charset = "UTF-8";

const char *mdb_target_charset(MdbHandle *mdb) {
    (void)mdb;
    return target_charset;
}

void mdb_iconv_init(MdbHandle *mdb) {
    (void)mdb;
}

void mdb_iconv_close(MdbHandle *mdb) {
    (void)mdb;
}

int mdb_unicode2ascii(MdbHandle *mdb, const char *src, size_t slen, char *dest, size_t dlen) {
    size_t i, j = 0;
    (void)mdb;
    if (!src || !dest || dlen == 0) {
        if (dest && dlen > 0) dest[0] = '\0';
        return 0;
    }
    for (i = 0; i < slen && j < dlen - 1; i += 2) {
        unsigned char low = (unsigned char)src[i];
        unsigned char high = (i + 1 < slen) ? (unsigned char)src[i + 1] : 0;
        if (high == 0 && low < 128) {
            dest[j++] = low;
        } else if (high == 0 && low != 0) {
            dest[j++] = low;
        } else {
            dest[j++] = '?';
        }
    }
    dest[j] = '\0';
    return (int)j;
}

int mdb_ascii2unicode(MdbHandle *mdb, const char *src, size_t slen, char *dest, size_t dlen) {
    size_t i, j = 0;
    (void)mdb;
    if (!src || !dest || dlen == 0) return 0;
    for (i = 0; i < slen && j < dlen - 1; i++) {
        if (j + 1 < dlen) {
            dest[j++] = src[i];
            dest[j++] = 0;
        }
    }
    return (int)j;
}

void mdbi_rc4(unsigned char *key, size_t key_len, unsigned char *data, size_t data_len) {
    unsigned char s[256];
    unsigned int i, j, k, t;
    for (i = 0; i < 256; i++) s[i] = (unsigned char)i;
    j = 0;
    for (i = 0; i < 256; i++) {
        j = (j + s[i] + key[i % key_len]) % 256;
        t = s[i]; s[i] = s[j]; s[j] = (unsigned char)t;
    }
    i = j = 0;
    for (k = 0; k < data_len; k++) {
        i = (i + 1) % 256;
        j = (j + s[i]) % 256;
        t = s[i]; s[i] = s[j]; s[j] = (unsigned char)t;
        data[k] ^= s[(s[i] + s[j]) % 256];
    }
}


