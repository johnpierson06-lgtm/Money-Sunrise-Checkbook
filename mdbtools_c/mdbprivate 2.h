/*
 * mdbprivate.h - Internal mdbtools header
 * Private definitions used by mdbtools internally
 */

#ifndef _mdbprivate_h_
#define _mdbprivate_h_

#include "mdbtools.h"

/* Internal format constants */
extern MdbFormatConstants MdbJet3Constants;
extern MdbFormatConstants MdbJet4Constants;

/* Internal helper functions */
#ifdef __cplusplus
extern "C" {
#endif

/* These are internal functions used by mdbtools */
void mdb_buffer_dump(const void *buf, off_t start, size_t len);
int mdb_get_option(unsigned long optnum);
void mdb_debug(int klass, const char *fmt, ...);

#ifdef __cplusplus
}
#endif

#endif /* _mdbprivate_h_ */
