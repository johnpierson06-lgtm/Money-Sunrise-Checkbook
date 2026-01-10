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
