//
// mdbtools_stubs.c
// Stub implementations of mdbtools functions
// These are temporary implementations to allow linking
// Replace with actual mdbtools library for real functionality
//

#include "mdbtools.h"
#include "mdbsql.h"
#include <stdlib.h>
#include <string.h>

// Stub implementation of mdb_open
MdbHandle* mdb_open(const char* filename, MdbFileFlags flags) {
    // Return NULL for now - indicates failure
    // In real implementation, this would open and parse the MDB file
    return NULL;
}

// Stub implementation of mdb_close
void mdb_close(MdbHandle* mdb) {
    // In real implementation, this would free resources
    if (mdb) {
        free(mdb);
    }
}

// Stub implementation of mdb_read_table_by_name
MdbTableDef* mdb_read_table_by_name(MdbHandle* mdb, char* table_name, int obj_type) {
    // Return NULL - indicates table not found
    // Real implementation would search catalog and read table definition
    return NULL;
}

// Stub implementation of mdb_sql_init
MdbSQL* mdb_sql_init(void) {
    // Allocate a basic SQL handle
    MdbSQL* sql = (MdbSQL*)calloc(1, sizeof(MdbSQL));
    if (sql) {
        sql->error_msg[0] = '\0';
    }
    return sql;
}

// Stub implementation of mdb_sql_run_query
MdbSQL* mdb_sql_run_query(MdbSQL* sql, const char* query) {
    // Return the sql handle as-is for now
    // Real implementation would parse and execute the query
    if (sql && query) {
        snprintf(sql->error_msg, sizeof(sql->error_msg), "Stub implementation - query not executed: %s", query);
    }
    return sql;
}

// Additional stub functions that might be needed

void mdb_sql_exit(MdbSQL* sql) {
    if (sql) {
        free(sql);
    }
}

int mdb_sql_fetch_row(MdbSQL* sql, MdbTableDef* table) {
    return 0; // No rows
}

char* mdb_col_to_string(MdbHandle* mdb, void* buf, int col_num, int col_type, int col_size) {
    return NULL;
}

void mdb_free_tabledef(MdbTableDef* table) {
    if (table) {
        free(table);
    }
}
