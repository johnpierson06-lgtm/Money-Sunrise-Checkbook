//
//  CheckbookApp-Bridging-Header.h
//  CheckbookApp
//
//  Bridging header to expose C code (mdbtools) to Swift
//

#ifndef CheckbookApp_Bridging_Header_h
#define CheckbookApp_Bridging_Header_h

// First include mdbfakeglib to provide GLib types
#include "mdbfakeglib.h"

// Then include mdbtools (which now uses mdbfakeglib)
#include "mdbtools.h"

// Include SQL support
#include "mdbsql.h"

// Include helper wrappers
#include "MoneyMDBHelpers.h"

#endif /* CheckbookApp_Bridging_Header_h */
