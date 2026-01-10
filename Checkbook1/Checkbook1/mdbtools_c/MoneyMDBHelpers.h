#pragma once
#include "mdbtools.h"
#include "mdbsql.h"

#ifdef __cplusplus
extern "C" {
#endif

MdbHandle* money_mdb_open(const char* path);
void money_mdb_close(MdbHandle* mdb);
MdbTableDef* money_mdb_open_acct(MdbHandle* mdb);
int money_mdb_num_columns(MdbTableDef* table);

// Return a SQL handle pointer instead of int
MdbSQL* money_mdb_run_query(const char* sql);

#ifdef __cplusplus
}
#endif
