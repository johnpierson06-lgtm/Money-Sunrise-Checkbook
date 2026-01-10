#pragma once
#include "mdbtools.h"
#include "mdbsql.h"

#ifdef __cplusplus
extern "C" {
#endif

// Basic MDB operations
MdbHandle* money_mdb_open(const char* path);
void money_mdb_close(MdbHandle* mdb);

// Table operations
MdbTableDef* money_mdb_read_table(MdbHandle* mdb, const char* table_name);
void money_mdb_free_table(MdbTableDef* table);
int money_mdb_read_columns(MdbTableDef* table);
int money_mdb_rewind_table(MdbTableDef* table);

// Row operations
int money_mdb_fetch_row(MdbTableDef* table);
char* money_mdb_col_to_string(MdbHandle* mdb, int col_num);

// Column information
int money_mdb_num_columns(MdbTableDef* table);
const char* money_mdb_col_name(MdbTableDef* table, int col_num);
int money_mdb_col_type(MdbTableDef* table, int col_num);
int money_mdb_col_size(MdbTableDef* table, int col_num);

// Type conversion helpers
int money_mdb_col_get_int(void* data, int col_type);
long long money_mdb_col_get_int64(void* data, int col_type);
double money_mdb_col_get_double(void* data, int col_type);
const char* money_mdb_col_get_string(void* data);

// Catalog operations
int money_mdb_read_catalog(MdbHandle* mdb, int obj_type);
MdbCatalogEntry* money_mdb_get_catalog_entry(MdbHandle* mdb, int idx);

#ifdef __cplusplus
}
#endif
