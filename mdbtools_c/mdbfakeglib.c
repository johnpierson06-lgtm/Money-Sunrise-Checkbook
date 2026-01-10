/*
 * mdbfakeglib.c - Minimal GLib implementation for mdbtools on iOS
 * 
 * This provides just enough GLib functionality to make mdbtools work
 * without requiring the full GLib library.
 *
 * Copyright (C) 2020 Evan Miller
 * Adapted for iOS
 */

#include "mdbfakeglib.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <ctype.h>

/* Memory allocation */
void *g_memdup(const void *src, size_t len) {
    void *dest = malloc(len);
    if (dest) {
        memcpy(dest, src, len);
    }
    return dest;
}

/* String functions */
int g_str_equal(const void *str1, const void *str2) {
    return strcmp((const char *)str1, (const char *)str2) == 0;
}

char *g_strdup(const char *src) {
    if (!src) return NULL;
    size_t len = strlen(src) + 1;
    char *dest = malloc(len);
    if (dest) {
        memcpy(dest, src, len);
    }
    return dest;
}

char *g_strndup(const char *src, size_t len) {
    if (!src) return NULL;
    char *dest = malloc(len + 1);
    if (dest) {
        memcpy(dest, src, len);
        dest[len] = '\0';
    }
    return dest;
}

char *g_strdup_printf(const char *format, ...) {
    va_list args;
    va_start(args, format);
    
    // First, determine the length
    va_list args_copy;
    va_copy(args_copy, args);
    int len = vsnprintf(NULL, 0, format, args_copy);
    va_end(args_copy);
    
    if (len < 0) {
        va_end(args);
        return NULL;
    }
    
    // Allocate and format
    char *result = malloc(len + 1);
    if (result) {
        vsnprintf(result, len + 1, format, args);
    }
    
    va_end(args);
    return result;
}

char *g_strconcat(const char *first, ...) {
    if (!first) return NULL;
    
    // Calculate total length
    size_t total_len = strlen(first);
    va_list args;
    va_start(args, first);
    const char *str;
    while ((str = va_arg(args, const char *)) != NULL) {
        total_len += strlen(str);
    }
    va_end(args);
    
    // Allocate
    char *result = malloc(total_len + 1);
    if (!result) return NULL;
    
    // Concatenate
    strcpy(result, first);
    va_start(args, first);
    while ((str = va_arg(args, const char *)) != NULL) {
        strcat(result, str);
    }
    va_end(args);
    
    return result;
}

char **g_strsplit(const char *haystack, const char *needle, int max_tokens) {
    if (!haystack || !needle) return NULL;
    
    int needle_len = (int)strlen(needle);
    if (needle_len == 0) return NULL;
    
    // Count tokens
    int count = 1;
    const char *p = haystack;
    while ((p = strstr(p, needle)) != NULL && (max_tokens <= 0 || count < max_tokens)) {
        count++;
        p += needle_len;
    }
    
    // Allocate array
    char **result = calloc(count + 1, sizeof(char *));
    if (!result) return NULL;
    
    // Split
    p = haystack;
    for (int i = 0; i < count; i++) {
        const char *next = strstr(p, needle);
        if (!next || (max_tokens > 0 && i == max_tokens - 1)) {
            result[i] = g_strdup(p);
            break;
        }
        result[i] = g_strndup(p, next - p);
        p = next + needle_len;
    }
    
    return result;
}

void g_strfreev(char **str_array) {
    if (!str_array) return;
    for (int i = 0; str_array[i]; i++) {
        free(str_array[i]);
    }
    free(str_array);
}

gchar *g_strdelimit(gchar *string, const gchar *delimiters, gchar new_delimiter) {
    if (!string) return NULL;
    
    const gchar *default_delimiters = G_STR_DELIMITERS;
    if (!delimiters) delimiters = default_delimiters;
    
    for (gchar *p = string; *p; p++) {
        if (strchr(delimiters, *p)) {
            *p = new_delimiter;
        }
    }
    
    return string;
}

void g_printerr(const gchar *format, ...) {
    va_list args;
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);
}

/* UTF-8 conversion - simplified for ASCII */
gchar *g_locale_to_utf8(const gchar *opsysstring, size_t len, 
                        size_t *bytes_read, size_t *bytes_written, GError **error) {
    if (!opsysstring) return NULL;
    if (len == (size_t)-1) len = strlen(opsysstring);
    
    gchar *result = g_strndup(opsysstring, len);
    if (bytes_read) *bytes_read = len;
    if (bytes_written) *bytes_written = len;
    return result;
}

gchar *g_utf8_casefold(const gchar *str, gssize len) {
    if (!str) return NULL;
    if (len < 0) len = strlen(str);
    
    gchar *result = malloc(len + 1);
    if (!result) return NULL;
    
    for (gssize i = 0; i < len; i++) {
        result[i] = tolower((unsigned char)str[i]);
    }
    result[len] = '\0';
    
    return result;
}

gchar *g_utf8_strdown(const gchar *str, gssize len) {
    return g_utf8_casefold(str, len);
}

gint g_unichar_to_utf8(gunichar c, gchar *dst) {
    if (c < 0x80) {
        if (dst) dst[0] = c;
        return 1;
    }
    // Simplified - only handle ASCII
    if (dst) dst[0] = '?';
    return 1;
}

/* GString */
GString *g_string_new(const gchar *init) {
    GString *string = malloc(sizeof(GString));
    if (!string) return NULL;
    
    if (init) {
        string->len = strlen(init);
        string->allocated_len = string->len + 1;
        string->str = malloc(string->allocated_len);
        if (!string->str) {
            free(string);
            return NULL;
        }
        memcpy(string->str, init, string->len + 1);
    } else {
        string->len = 0;
        string->allocated_len = 16;
        string->str = malloc(string->allocated_len);
        if (!string->str) {
            free(string);
            return NULL;
        }
        string->str[0] = '\0';
    }
    
    return string;
}

GString *g_string_assign(GString *string, const gchar *rval) {
    if (!string) return NULL;
    
    size_t len = rval ? strlen(rval) : 0;
    if (len + 1 > string->allocated_len) {
        char *new_str = realloc(string->str, len + 1);
        if (!new_str) return NULL;
        string->str = new_str;
        string->allocated_len = len + 1;
    }
    
    if (rval) {
        memcpy(string->str, rval, len + 1);
    } else {
        string->str[0] = '\0';
    }
    string->len = len;
    
    return string;
}

GString *g_string_append(GString *string, const gchar *val) {
    if (!string || !val) return string;
    
    size_t val_len = strlen(val);
    size_t new_len = string->len + val_len;
    
    if (new_len + 1 > string->allocated_len) {
        size_t new_allocated = (new_len + 1) * 2;
        char *new_str = realloc(string->str, new_allocated);
        if (!new_str) return NULL;
        string->str = new_str;
        string->allocated_len = new_allocated;
    }
    
    memcpy(string->str + string->len, val, val_len + 1);
    string->len = new_len;
    
    return string;
}

gchar *g_string_free(GString *string, gboolean free_segment) {
    if (!string) return NULL;
    
    gchar *result = NULL;
    if (!free_segment) {
        result = string->str;
    } else {
        free(string->str);
    }
    free(string);
    
    return result;
}

/* GPtrArray */
GPtrArray *g_ptr_array_new(void) {
    GPtrArray *array = malloc(sizeof(GPtrArray));
    if (!array) return NULL;
    
    array->len = 0;
    array->pdata = NULL;
    
    return array;
}

void g_ptr_array_add(GPtrArray *array, void *entry) {
    if (!array) return;
    
    void **new_pdata = realloc(array->pdata, (array->len + 1) * sizeof(void *));
    if (!new_pdata) return;
    
    array->pdata = new_pdata;
    array->pdata[array->len] = entry;
    array->len++;
}

gboolean g_ptr_array_remove(GPtrArray *array, gpointer data) {
    if (!array) return FALSE;
    
    for (guint i = 0; i < array->len; i++) {
        if (array->pdata[i] == data) {
            // Shift remaining elements
            for (guint j = i; j < array->len - 1; j++) {
                array->pdata[j] = array->pdata[j + 1];
            }
            array->len--;
            return TRUE;
        }
    }
    
    return FALSE;
}

void g_ptr_array_foreach(GPtrArray *array, GFunc function, gpointer user_data) {
    if (!array || !function) return;
    
    for (guint i = 0; i < array->len; i++) {
        function(array->pdata[i], user_data);
    }
}

void g_ptr_array_sort(GPtrArray *array, GCompareFunc func) {
    if (!array || !func || array->len <= 1) return;
    
    // Simple bubble sort (good enough for small arrays)
    for (guint i = 0; i < array->len - 1; i++) {
        for (guint j = 0; j < array->len - i - 1; j++) {
            if (func(array->pdata[j], array->pdata[j + 1]) > 0) {
                void *temp = array->pdata[j];
                array->pdata[j] = array->pdata[j + 1];
                array->pdata[j + 1] = temp;
            }
        }
    }
}

void g_ptr_array_free(GPtrArray *array, gboolean free_elements) {
    if (!array) return;
    
    // IMPORTANT: In mdbtools, the boolean parameter doesn't mean "free the elements"
    // It means "free the segment" (the array itself) vs returning it
    // The actual elements are managed separately by mdbtools
    // So we should NEVER free the individual elements here
    
    // Just free the pointer array structure itself
    free(array->pdata);
    free(array);
    
    // Ignore the free_elements parameter - it's a GLib quirk that doesn't apply here
    (void)free_elements;
}

/* GList */
GList *g_list_append(GList *list, void *data) {
    GList *new_node = malloc(sizeof(GList));
    if (!new_node) return list;
    
    new_node->data = data;
    new_node->next = NULL;
    
    if (!list) {
        new_node->prev = NULL;
        return new_node;
    }
    
    GList *last = g_list_last(list);
    last->next = new_node;
    new_node->prev = last;
    
    return list;
}

GList *g_list_last(GList *list) {
    if (!list) return NULL;
    
    while (list->next) {
        list = list->next;
    }
    
    return list;
}

GList *g_list_remove(GList *list, void *data) {
    GList *node = list;
    
    while (node) {
        if (node->data == data) {
            if (node->prev) {
                node->prev->next = node->next;
            }
            if (node->next) {
                node->next->prev = node->prev;
            }
            
            GList *result = (node == list) ? node->next : list;
            free(node);
            return result;
        }
        node = node->next;
    }
    
    return list;
}

void g_list_free(GList *list) {
    while (list) {
        GList *next = list->next;
        free(list);
        list = next;
    }
}

/* GHashTable - simplified implementation */
GHashTable *g_hash_table_new(GHashFunc hash_func, GEqualFunc equal_func) {
    GHashTable *table = malloc(sizeof(GHashTable));
    if (!table) return NULL;
    
    table->compare = equal_func;
    table->array = g_ptr_array_new();
    
    return table;
}

typedef struct {
    void *key;
    void *value;
} HashEntry;

void *g_hash_table_lookup(GHashTable *table, const void *key) {
    if (!table || !table->array) return NULL;
    
    for (guint i = 0; i < table->array->len; i++) {
        HashEntry *entry = table->array->pdata[i];
        if (entry && table->compare(entry->key, key)) {
            return entry->value;
        }
    }
    
    return NULL;
}

gboolean g_hash_table_lookup_extended(GHashTable *table, const void *lookup_key,
                                      void **orig_key, void **value) {
    if (!table || !table->array) return FALSE;
    
    for (guint i = 0; i < table->array->len; i++) {
        HashEntry *entry = table->array->pdata[i];
        if (entry && table->compare(entry->key, lookup_key)) {
            if (orig_key) *orig_key = entry->key;
            if (value) *value = entry->value;
            return TRUE;
        }
    }
    
    return FALSE;
}

void g_hash_table_insert(GHashTable *table, void *key, void *value) {
    if (!table || !table->array) return;
    
    // Check if key exists
    for (guint i = 0; i < table->array->len; i++) {
        HashEntry *entry = table->array->pdata[i];
        if (entry && table->compare(entry->key, key)) {
            entry->value = value;
            return;
        }
    }
    
    // Add new entry
    HashEntry *entry = malloc(sizeof(HashEntry));
    if (entry) {
        entry->key = key;
        entry->value = value;
        g_ptr_array_add(table->array, entry);
    }
}

gboolean g_hash_table_remove(GHashTable *table, const void *key) {
    if (!table || !table->array) return FALSE;
    
    for (guint i = 0; i < table->array->len; i++) {
        HashEntry *entry = table->array->pdata[i];
        if (entry && table->compare(entry->key, key)) {
            free(entry);
            // Shift remaining elements
            for (guint j = i; j < table->array->len - 1; j++) {
                table->array->pdata[j] = table->array->pdata[j + 1];
            }
            table->array->len--;
            return TRUE;
        }
    }
    
    return FALSE;
}

void g_hash_table_foreach(GHashTable *table, GHFunc function, void *user_data) {
    if (!table || !table->array || !function) return;
    
    for (guint i = 0; i < table->array->len; i++) {
        HashEntry *entry = table->array->pdata[i];
        if (entry) {
            function(entry->key, entry->value, user_data);
        }
    }
}

void g_hash_table_foreach_remove(GHashTable *table, GHRFunc function, void *user_data) {
    if (!table || !table->array || !function) return;
    
    for (guint i = 0; i < table->array->len; ) {
        HashEntry *entry = table->array->pdata[i];
        if (entry && function(entry->key, entry->value, user_data)) {
            free(entry);
            // Shift remaining elements
            for (guint j = i; j < table->array->len - 1; j++) {
                table->array->pdata[j] = table->array->pdata[j + 1];
            }
            table->array->len--;
        } else {
            i++;
        }
    }
}

void g_hash_table_destroy(GHashTable *table) {
    if (!table) return;
    
    if (table->array) {
        for (guint i = 0; i < table->array->len; i++) {
            free(table->array->pdata[i]);
        }
        g_ptr_array_free(table->array, FALSE);
    }
    
    free(table);
}

/* GOption - minimal implementation */
GOptionContext *g_option_context_new(const char *description) {
    GOptionContext *context = malloc(sizeof(GOptionContext));
    if (context) {
        context->desc = description;
        context->entries = NULL;
    }
    return context;
}

void g_option_context_add_main_entries(GOptionContext *context,
                                       const GOptionEntry *entries,
                                       const gchar *translation_domain) {
    if (context) {
        context->entries = entries;
    }
}

gchar *g_option_context_get_help(GOptionContext *context,
                                 gboolean main_help, void *group) {
    return g_strdup("Help not implemented in minimal glib");
}

gboolean g_option_context_parse(GOptionContext *context,
                                gint *argc, gchar ***argv, GError **error) {
    // Minimal implementation - just return success
    return TRUE;
}

void g_option_context_free(GOptionContext *context) {
    free(context);
}
