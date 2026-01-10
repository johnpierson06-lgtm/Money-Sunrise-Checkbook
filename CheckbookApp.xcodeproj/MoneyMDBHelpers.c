#include "MoneyMDBHelpers.h"
#include <stdlib.h>
#include <string.h>

// Basic MDB operations
MdbHandle* money_mdb_open(const char* path) {
    if (!path) return NULL;
    
    MdbHandle* mdb = mdb_open(path, MDB_NOFLAGS);
    if (!mdb) return NULL;
    
    // Read the catalog to populate table list
    mdb_read_catalog(mdb, MDB_TABLE);
    
    return mdb;
}

void money_mdb_close(MdbHandle* mdb) {
    if (mdb) {
        mdb_close(mdb);
    }
}

// Table operations
MdbTableDef* money_mdb_read_table(MdbHandle* mdb, const char* table_name) {
    if (!mdb || !table_name) return NULL;
    
    MdbTableDef* table = mdb_read_table_by_name(mdb, (char*)table_name, MDB_TABLE);
    if (!table) return NULL;
    
    // Read column definitions
    mdb_read_columns(table);
    
    // Bind columns to internal buffers
    mdb_rewind_table(table);
    
    return table;
}

void money_mdb_free_table(MdbTableDef* table) {
    if (table) {
        mdb_free_tabledef(table);
    }
}

int money_mdb_read_columns(MdbTableDef* table) {
    if (!table) return 0;
    return mdb_read_columns(table);
}

int money_mdb_rewind_table(MdbTableDef* table) {
    if (!table) return 0;
    mdb_rewind_table(table);
    return 1;
}

// Row operations
int money_mdb_fetch_row(MdbTableDef* table) {
    if (!table) return 0;
    return mdb_fetch_row(table);
}

char* money_mdb_col_to_string(MdbHandle* mdb, int col_num) {
    if (!mdb) return NULL;
    
    // This is a simplified version - you'll need to track the current table
    // and column buffer in a more complete implementation
    return NULL;
}

// Column information
int money_mdb_num_columns(MdbTableDef* table) {
    return table ? table->num_cols : 0;
}

const char* money_mdb_col_name(MdbTableDef* table, int col_num) {
    if (!table || col_num < 0 || col_num >= table->num_cols) return NULL;
    
    MdbColumn* col = g_ptr_array_index(table->columns, col_num);
    return col ? col->name : NULL;
}

int money_mdb_col_type(MdbTableDef* table, int col_num) {
    if (!table || col_num < 0 || col_num >= table->num_cols) return 0;
    
    MdbColumn* col = g_ptr_array_index(table->columns, col_num);
    return col ? col->col_type : 0;
}

int money_mdb_col_size(MdbTableDef* table, int col_num) {
    if (!table || col_num < 0 || col_num >= table->num_cols) return 0;
    
    MdbColumn* col = g_ptr_array_index(table->columns, col_num);
    return col ? col->col_size : 0;
}

// Catalog operations
int money_mdb_read_catalog(MdbHandle* mdb, int obj_type) {
    if (!mdb) return 0;
    return mdb_read_catalog(mdb, obj_type);
}

MdbCatalogEntry* money_mdb_get_catalog_entry(MdbHandle* mdb, int idx) {
    if (!mdb || idx < 0) return NULL;
    return g_ptr_array_index(mdb->catalog, idx);
}
