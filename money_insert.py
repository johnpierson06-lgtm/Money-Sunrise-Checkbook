#!/usr/bin/env python3
"""
Money Inserter using Java/Jackcess
Wrapper script that calls Java to properly insert data into Money files
"""

import subprocess
import sys
import json
import os

# UPDATE THIS PATH to point to your sunrise JAR file!
# First try environment variable, then same directory as script, then home directory
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SUNRISE_JAR = os.environ.get("SUNRISE_JAR", 
                             os.path.join(SCRIPT_DIR, "sunriise-0.0.2-SNAPSHOT-jar-with-dependencies.jar"))

# If not in script dir, try current working directory
if not os.path.exists(SUNRISE_JAR):
    SUNRISE_JAR = os.path.join(os.getcwd(), "sunriise-0.0.2-SNAPSHOT-jar-with-dependencies.jar")

# If still not found, try home directory
if not os.path.exists(SUNRISE_JAR):
    SUNRISE_JAR = os.path.expanduser("~/sunriise-0.0.2-SNAPSHOT-jar-with-dependencies.jar")

# Check if JAR exists
if not os.path.exists(SUNRISE_JAR):
    print(f"ERROR: Cannot find Sunrise JAR at: {SUNRISE_JAR}")
    print("Please update SUNRISE_JAR path in the script or set environment variable:")
    print("  export SUNRISE_JAR=/path/to/your/sunrise.jar")
    sys.exit(1)

print(f"Using Sunrise JAR: {SUNRISE_JAR}")
print()

def insert_payee_java(mdb_path, payee_id, payee_name, password=""):
    """
    Insert a payee using Java/Jackcess
    This properly updates indexes and maintains database integrity
    
    Args:
        mdb_path: Path to the Money database file
        payee_id: The payee ID to insert
        payee_name: The payee name
        password: The Money file password (empty string if no password)
    """
    
    # Escape the payee name for Java strings
    escaped_payee_name = payee_name.replace("\\", "\\\\").replace("\"", "\\\"")
    
    # Also escape the path for Java strings  
    escaped_mdb_path = mdb_path.replace("\\", "\\\\").replace("\"", "\\\"")
    
    # Escape the password for Java strings
    escaped_password = password.replace("\\", "\\\\").replace("\"", "\\\"")
    
    # Determine if this is a .mdb (decrypted) or .mny (encrypted) file
    is_mdb = mdb_path.lower().endswith('.mdb')
    
    java_code = f"""
import com.healthmarketscience.jackcess.*;
import java.io.File;
import java.io.RandomAccessFile;
import java.math.BigDecimal;
import java.util.Date;

public class QuickInsert {{
    public static void main(String[] args) throws Exception {{
        File mdbFile = new File("{escaped_mdb_path}");
        String password = "{escaped_password}";
        boolean isMdb = {str(is_mdb).lower()};
        
        System.out.println("=== Inserting Payee ===");
        
        Database db = null;
        try {{
            // Open database - use codec only if password is provided or it's .mny file
            if (isMdb && password.isEmpty()) {{
                db = Database.open(mdbFile);
            }} else {{
                CryptCodecProvider codec = new CryptCodecProvider(password);
                db = Database.open(mdbFile, false, true, null, null, codec);
            }}
            
            // Insert into PAY table
            Table payTable = db.getTable("PAY");
            
            Object[] payRow = new Object[payTable.getColumnCount()];
            for (int i = 0; i < payTable.getColumnCount(); i++) {{
                Column col = payTable.getColumns().get(i);
                String colName = col.getName();
                
                if ("hpay".equals(colName)) {{
                    payRow[i] = {payee_id};
                }} else if ("szFull".equals(colName)) {{
                    payRow[i] = "{escaped_payee_name}";
                }} else if ("dtSerial".equals(colName)) {{
                    payRow[i] = new Date();
                }} else if ("fUpdated".equals(colName)) {{
                    payRow[i] = Boolean.TRUE;
                }} else if ("fLocal".equals(colName)) {{
                    payRow[i] = Boolean.TRUE;
                }} else {{
                    payRow[i] = null;
                }}
            }}
            
            payTable.addRow(payRow);
            System.out.println("✓ Inserted payee " + {payee_id} + " into PAY table");
            
            // Insert into XPAY table  
            Table xpayTable = db.getTable("XPAY");
            
            Object[] xpayRow = new Object[xpayTable.getColumnCount()];
            for (int i = 0; i < xpayTable.getColumnCount(); i++) {{
                Column col = xpayTable.getColumns().get(i);
                String colName = col.getName();
                
                if ("hpay".equals(colName)) {{
                    xpayRow[i] = {payee_id};
                }} else if ("amtBal".equals(colName)) {{
                    xpayRow[i] = BigDecimal.ZERO;
                }} else {{
                    xpayRow[i] = null;
                }}
            }}
            
            xpayTable.addRow(xpayRow);
            System.out.println("✓ Inserted payee " + {payee_id} + " into XPAY table");
            
            System.out.println("SUCCESS");
        }} finally {{
            if (db != null) {{
                db.close();
            }}
        }}
    }}
}}
"""
    
    # Write Java file
    with open("/tmp/QuickInsert.java", "w") as f:
        f.write(java_code)
    
    # Compile
    compile_result = subprocess.run([
        "javac",
        "-cp", SUNRISE_JAR,
        "/tmp/QuickInsert.java"
    ], capture_output=True, text=True)
    
    if compile_result.returncode != 0:
        raise Exception(f"Java compile failed: {compile_result.stderr}")
    
    # Run
    run_result = subprocess.run([
        "java",
        "-cp", f"{SUNRISE_JAR}:/tmp",
        "QuickInsert"
    ], capture_output=True, text=True)
    
    if run_result.stdout:
        print(run_result.stdout)
    
    if run_result.returncode != 0:
        if run_result.stderr:
            print(run_result.stderr, file=sys.stderr)
        raise Exception(f"Java failed with return code {run_result.returncode}")
    
    if "SUCCESS" not in run_result.stdout:
        raise Exception(f"Insert failed")
    
    return True


def insert_transaction_java(mdb_path, transaction_data, password=""):
    """
    Insert a transaction using Java/Jackcess
    
    Args:
        mdb_path: Path to the Money database file
        transaction_data: Dict with transaction fields (htrn, dtTrn, hcat, hpay, amt, etc.)
        password: The Money file password
    """
    
    # Escape the path for Java strings  
    escaped_mdb_path = mdb_path.replace("\\", "\\\\").replace("\"", "\\\"")
    
    # Escape the password for Java strings
    escaped_password = password.replace("\\", "\\\\").replace("\"", "\\\"")
    
    # Extract transaction data
    htrn = transaction_data.get('htrn', 0)
    hact = transaction_data.get('hact', 0)
    hcat = transaction_data.get('hcat')  # Can be None
    hpay = transaction_data.get('hpay', 0)
    amt = transaction_data.get('amt', 0.0)
    memo = transaction_data.get('szMemo', '').replace("\\", "\\\\").replace("\"", "\\\"")
    num = transaction_data.get('szNum', '').replace("\\", "\\\\").replace("\"", "\\\"")
    
    # Convert None to "null" for Java
    hcat_value = "null" if hcat is None else str(hcat)
    
    # Determine if this is a .mdb (decrypted) or .mny (encrypted) file
    is_mdb = mdb_path.lower().endswith('.mdb')
    
    java_code = f"""
import com.healthmarketscience.jackcess.*;
import java.io.File;
import java.math.BigDecimal;
import java.util.Date;
import java.util.Calendar;
import java.util.UUID;
import java.text.SimpleDateFormat;

public class QuickInsertTransaction {{
    public static void main(String[] args) throws Exception {{
        File mdbFile = new File("{escaped_mdb_path}");
        String password = "{escaped_password}";
        boolean isMdb = {str(is_mdb).lower()};
        
        System.out.println("=== Inserting Transaction ===");
        System.out.println("File type: " + (isMdb ? "MDB (decrypted)" : "MNY (encrypted)"));
        System.out.println("File size: " + mdbFile.length() + " bytes");
        System.out.println("htrn: {htrn}");
        System.out.println("hact: {hact}");
        System.out.println("amt: {amt}");
        System.out.println("hpay: {hpay}");
        System.out.println("hcat: {hcat_value}");
        
        Database db = null;
        try {{
            // Open database - use codec only if password is provided or it's .mny file
            if (isMdb && password.isEmpty()) {{
                System.out.println("Opening decrypted MDB file without codec...");
                db = Database.open(mdbFile);
            }} else {{
                System.out.println("Opening with password/codec...");
                CryptCodecProvider codec = new CryptCodecProvider(password);
                db = Database.open(mdbFile, false, true, null, null, codec);
            }}
            
            System.out.println("✓ Database opened successfully");
            
            // Insert into TRN table
            Table trnTable = db.getTable("TRN");
            
            System.out.println("\\nTRN table columns:");
            int colIndex = 1;
            for (Column col : trnTable.getColumns()) {{
                System.out.println("  [" + colIndex + "] " + col.getName() + " (" + col.getType() + ")");
                colIndex++;
            }}
            
            // Create the null date for Money database (February 28, 2000 - Money's standard null date)
            Calendar nullDateCal = Calendar.getInstance();
            nullDateCal.set(2000, Calendar.FEBRUARY, 28, 0, 0, 0);
            nullDateCal.set(Calendar.MILLISECOND, 0);
            Date nullDate = nullDateCal.getTime();
            
            Object[] trnRow = new Object[trnTable.getColumnCount()];
            for (int i = 0; i < trnTable.getColumnCount(); i++) {{
                Column col = trnTable.getColumns().get(i);
                String colName = col.getName();
                
                // Core identification fields [1-3]
                if ("htrn".equals(colName)) {{
                    trnRow[i] = {htrn};
                    System.out.println("[1] Setting htrn = " + {htrn});
                }} else if ("hacct".equals(colName)) {{
                    trnRow[i] = {hact};
                    System.out.println("[2] Setting hacct = " + {hact});
                }} else if ("hacctLink".equals(colName)) {{
                    trnRow[i] = null;  // [3] Only for transfers
                    
                // Date fields [4-7]
                }} else if ("dt".equals(colName)) {{
                    trnRow[i] = new Date();
                    System.out.println("[4] Setting dt = now");
                }} else if ("dtSent".equals(colName)) {{
                    trnRow[i] = nullDate;  // [5]
                }} else if ("dtCleared".equals(colName)) {{
                    trnRow[i] = nullDate;  // [6]
                }} else if ("dtPost".equals(colName)) {{
                    trnRow[i] = nullDate;  // [7]
                    
                // Status and core fields [8-12]
                }} else if ("cs".equals(colName)) {{
                    trnRow[i] = 0;  // [8] Cleared status
                }} else if ("hsec".equals(colName)) {{
                    trnRow[i] = null;  // [9] Security ID
                }} else if ("amt".equals(colName)) {{
                    trnRow[i] = new BigDecimal("{amt}");  // [10]
                    System.out.println("[10] Setting amt = " + "{amt}");
                }} else if ("szId".equals(colName)) {{
                    trnRow[i] = "{num}";  // [11] Check number
                }} else if ("hcat".equals(colName)) {{
                    trnRow[i] = {hcat_value};  // [12]
                    System.out.println("[12] Setting hcat = " + {hcat_value});
                    
                // CRITICAL FIELDS [13-20]
                }} else if ("frq".equals(colName)) {{
                    trnRow[i] = -1;  // [13] CRITICAL: Posted transaction
                    System.out.println("[13] Setting frq = -1 (CRITICAL: posted)");
                }} else if ("fDefPmt".equals(colName)) {{
                    trnRow[i] = Boolean.FALSE;  // [14]
                }} else if ("mMemo".equals(colName)) {{
                    trnRow[i] = "{memo}";  // [15]
                }} else if ("oltt".equals(colName)) {{
                    trnRow[i] = -1;  // [16]
                }} else if ("grfEntryMethods".equals(colName)) {{
                    trnRow[i] = 1;  // [17]
                }} else if ("ps".equals(colName)) {{
                    trnRow[i] = 0;  // [18]
                }} else if ("amtVat".equals(colName)) {{
                    trnRow[i] = new BigDecimal("0.0000");  // [19]
                }} else if ("grftt".equals(colName)) {{
                    trnRow[i] = 0;  // [20] CRITICAL: Normal transaction
                    System.out.println("[20] Setting grftt = 0 (CRITICAL: normal transaction)");
                    
                // More fields [21-32]
                }} else if ("act".equals(colName)) {{
                    trnRow[i] = -1;  // [21]
                }} else if ("cFrqInst".equals(colName)) {{
                    trnRow[i] = null;  // [22]
                }} else if ("fPrint".equals(colName)) {{
                    trnRow[i] = Boolean.FALSE;  // [23]
                }} else if ("mFiStmtId".equals(colName)) {{
                    trnRow[i] = null;  // [24]
                }} else if ("olst".equals(colName)) {{
                    trnRow[i] = -1;  // [25]
                }} else if ("fDebtPlan".equals(colName)) {{
                    trnRow[i] = Boolean.FALSE;  // [26]
                }} else if ("grfstem".equals(colName)) {{
                    trnRow[i] = 0;  // [27] Should be 0, not -1
                }} else if ("cpmtsRemaining".equals(colName)) {{
                    trnRow[i] = -1;  // [28]
                }} else if ("instt".equals(colName)) {{
                    trnRow[i] = -1;  // [29]
                }} else if ("htrnSrc".equals(colName)) {{
                    trnRow[i] = null;  // [30]
                }} else if ("payt".equals(colName)) {{
                    trnRow[i] = -1;  // [31]
                }} else if ("grftf".equals(colName)) {{
                    trnRow[i] = 0;  // [32]
                    
                // Currency and amounts [33-36]
                }} else if ("lHtxsrc".equals(colName)) {{
                    trnRow[i] = -1;  // [33]
                }} else if ("lHcrncUser".equals(colName)) {{
                    trnRow[i] = 45;  // [34] CRITICAL: USD
                    System.out.println("[34] Setting lHcrncUser = 45 (CRITICAL: USD)");
                }} else if ("amtUser".equals(colName)) {{
                    trnRow[i] = new BigDecimal("{amt}");  // [35]
                }} else if ("amtVATUser".equals(colName)) {{
                    trnRow[i] = new BigDecimal("0.0000");  // [36]
                    
                // More flags [37-44]
                }} else if ("tef".equals(colName)) {{
                    trnRow[i] = -1;  // [37]
                }} else if ("fRefund".equals(colName)) {{
                    trnRow[i] = Boolean.FALSE;  // [38]
                }} else if ("fReimburse".equals(colName)) {{
                    trnRow[i] = Boolean.FALSE;  // [39]
                }} else if ("dtSerial".equals(colName)) {{
                    trnRow[i] = new Date();  // [40]
                }} else if ("fUpdated".equals(colName)) {{
                    trnRow[i] = Boolean.TRUE;  // [41] CRITICAL!
                    System.out.println("[41] Setting fUpdated = TRUE (CRITICAL!)");
                }} else if ("fCCPmt".equals(colName)) {{
                    trnRow[i] = Boolean.FALSE;  // [42]
                }} else if ("fDefBillAmt".equals(colName)) {{
                    trnRow[i] = Boolean.FALSE;  // [43]
                }} else if ("fDefBillDate".equals(colName)) {{
                    trnRow[i] = Boolean.FALSE;  // [44]
                    
                // Classification and dates [45-49]
                }} else if ("lHclsKak".equals(colName)) {{
                    trnRow[i] = -1;  // [45] Only the first one is -1
                }} else if ("lHclsKak2".equals(colName)) {{
                    trnRow[i] = null;  // [46] null, not -1
                }} else if ("lHclsKak3".equals(colName)) {{
                    trnRow[i] = null;  // [47] null, not -1
                }} else if ("dtCloseOffYear".equals(colName)) {{
                    trnRow[i] = nullDate;  // [48]
                }} else if ("dtOldRel".equals(colName)) {{
                    trnRow[i] = nullDate;  // [49]
                    
                // Final fields [50-61]
                }} else if ("hbillHead".equals(colName)) {{
                    trnRow[i] = null;  // [50]
                }} else if ("iinst".equals(colName)) {{
                    trnRow[i] = -1;  // [51] CRITICAL!
                    System.out.println("[51] Setting iinst = -1 (CRITICAL!)");
                }} else if ("amtBase".equals(colName)) {{
                    trnRow[i] = null;  // [52]
                }} else if ("rt".equals(colName)) {{
                    trnRow[i] = -1;  // [53]
                }} else if ("amtPreRec".equals(colName) || "amtPreRec2".equals(colName)) {{
                    trnRow[i] = null;  // [54-55]
                }} else if ("hstmtRel".equals(colName)) {{
                    trnRow[i] = null;  // [56]
                }} else if ("dRateToBase".equals(colName)) {{
                    trnRow[i] = null;  // [57]
                }} else if ("lHpay".equals(colName)) {{
                    trnRow[i] = {hpay};  // [58]
                    System.out.println("[58] Setting lHpay = " + {hpay});
                }} else if ("sguid".equals(colName)) {{
                    String guid = "{{" + UUID.randomUUID().toString().toUpperCase() + "}}";
                    trnRow[i] = guid;  // [59]
                    System.out.println("[59] Setting sguid = " + guid);
                }} else if ("szAggTrnId".equals(colName)) {{
                    trnRow[i] = null;  // [60]
                }} else if ("rgbDigest".equals(colName)) {{
                    trnRow[i] = null;  // [61]
                }} else {{
                    trnRow[i] = null;
                    System.out.println("WARNING: Unknown column: " + colName + " - setting to null");
                }}
            }}
            
            System.out.println("\\nAdding row to TRN table...");
            trnTable.addRow(trnRow);
            System.out.println("✓ Inserted transaction " + {htrn} + " into TRN table");
            
            // Verify the insert
            System.out.println("\\n=== Verifying Insert ===");
            SimpleDateFormat dateFormat = new SimpleDateFormat("MM/dd/yy HH:mm:ss");
            int count = 0;
            for (java.util.Map<String, Object> row : trnTable) {{
                if (row.get("htrn").equals({htrn})) {{
                    count++;
                    System.out.println("✓ Found inserted transaction:");
                    System.out.println("  [1]  htrn: " + row.get("htrn"));
                    System.out.println("  [2]  hacct: " + row.get("hacct"));
                    System.out.println("  [10] amt: " + row.get("amt"));
                    System.out.println("  [12] hcat: " + row.get("hcat"));
                    System.out.println("  [13] frq: " + row.get("frq") + " (should be -1)");
                    System.out.println("  [15] mMemo: " + row.get("mMemo"));
                    System.out.println("  [20] grftt: " + row.get("grftt") + " (should be 0)");
                    System.out.println("  [34] lHcrncUser: " + row.get("lHcrncUser") + " (should be 45)");
                    System.out.println("  [41] fUpdated: " + row.get("fUpdated") + " (should be TRUE)");
                    System.out.println("  [51] iinst: " + row.get("iinst") + " (should be -1)");
                    System.out.println("  [58] lHpay: " + row.get("lHpay"));
                    System.out.println("  [59] sguid: " + row.get("sguid"));
                    
                    Object dt = row.get("dt");
                    System.out.println("  [4]  dt: " + (dt != null ? dateFormat.format(dt) : "null"));
                }}
            }}
            if (count == 0) {{
                System.err.println("⚠️  WARNING: Could not find inserted transaction!");
            }}
            
            System.out.println("SUCCESS");
        }} finally {{
            if (db != null) {{
                db.close();
            }}
        }}
    }}
}}
"""
    
    # Write Java file
    with open("/tmp/QuickInsertTransaction.java", "w") as f:
        f.write(java_code)
    
    # Compile
    compile_result = subprocess.run([
        "javac",
        "-cp", SUNRISE_JAR,
        "/tmp/QuickInsertTransaction.java"
    ], capture_output=True, text=True)
    
    if compile_result.returncode != 0:
        raise Exception(f"Java compile failed: {compile_result.stderr}")
    
    # Run
    run_result = subprocess.run([
        "java",
        "-cp", f"{SUNRISE_JAR}:/tmp",
        "QuickInsertTransaction"
    ], capture_output=True, text=True)
    
    if run_result.stdout:
        print(run_result.stdout)
    
    if run_result.returncode != 0:
        if run_result.stderr:
            print(run_result.stderr, file=sys.stderr)
        raise Exception(f"Java failed with return code {run_result.returncode}")
    
    if "SUCCESS" not in run_result.stdout:
        raise Exception(f"Insert failed")
    
    return True


def list_transactions_java(mdb_path, password="", verbose=False):
    """
    List all transactions from the database for comparison
    
    Args:
        mdb_path: Path to the Money database file
        password: The Money file password
        verbose: If True, show ALL fields for each transaction
    
    Returns:
        List of transaction dictionaries
    """
    
    # Escape the path for Java strings  
    escaped_mdb_path = mdb_path.replace("\\", "\\\\").replace("\"", "\\\"")
    
    # Escape the password for Java strings
    escaped_password = password.replace("\\", "\\\\").replace("\"", "\\\"")
    
    # Determine if this is a .mdb (decrypted) or .mny (encrypted) file
    is_mdb = mdb_path.lower().endswith('.mdb')
    
    verbose_flag = "true" if verbose else "false"
    
    java_code = f"""
import com.healthmarketscience.jackcess.*;
import java.io.File;
import java.math.BigDecimal;
import java.util.Date;
import java.text.SimpleDateFormat;

public class ListTransactions {{
    public static void main(String[] args) throws Exception {{
        File mdbFile = new File("{escaped_mdb_path}");
        String password = "{escaped_password}";
        boolean verbose = {verbose_flag};
        boolean isMdb = {str(is_mdb).lower()};
        
        System.out.println("=== Listing Transactions ===");
        
        Database db = null;
        try {{
            // Open database - use codec only if password is provided or it's .mny file
            if (isMdb && password.isEmpty()) {{
                db = Database.open(mdbFile);
            }} else {{
                CryptCodecProvider codec = new CryptCodecProvider(password);
                db = Database.open(mdbFile, false, true, null, null, codec);
            }}
            
            // Read TRN table
            Table trnTable = db.getTable("TRN");
            
            System.out.println("Total transactions: " + trnTable.getRowCount());
            System.out.println("\\nAll Column names and positions:");
            int colIndex = 1;
            for (Column col : trnTable.getColumns()) {{
                System.out.println("  [" + colIndex + "] " + col.getName() + " (" + col.getType() + ")");
                colIndex++;
            }}
            
            System.out.println("\\n=== Transaction Data ===");
            SimpleDateFormat dateFormat = new SimpleDateFormat("MM/dd/yy HH:mm:ss");
            
            int count = 0;
            for (java.util.Map<String, Object> row : trnTable) {{
                count++;
                System.out.println("\\n========================================");
                System.out.println("Transaction #" + count + ":");
                System.out.println("========================================");
                
                // Core identification fields
                System.out.println("  [1]  htrn: " + row.get("htrn"));
                System.out.println("  [2]  hacct: " + row.get("hacct"));
                System.out.println("  [3]  hacctLink: " + row.get("hacctLink"));
                
                // Date fields
                Object dt = row.get("dt");
                System.out.println("  [4]  dt: " + (dt != null ? dateFormat.format(dt) : "null"));
                Object dtSent = row.get("dtSent");
                System.out.println("  [5]  dtSent: " + (dtSent != null ? dateFormat.format(dtSent) : "null"));
                Object dtCleared = row.get("dtCleared");
                System.out.println("  [6]  dtCleared: " + (dtCleared != null ? dateFormat.format(dtCleared) : "null"));
                Object dtPost = row.get("dtPost");
                System.out.println("  [7]  dtPost: " + (dtPost != null ? dateFormat.format(dtPost) : "null"));
                
                // Status and core fields
                System.out.println("  [8]  cs: " + row.get("cs"));
                System.out.println("  [9]  hsec: " + row.get("hsec"));
                System.out.println("  [10] amt: " + row.get("amt"));
                System.out.println("  [11] szId: " + row.get("szId"));
                System.out.println("  [12] hcat: " + row.get("hcat"));
                
                // CRITICAL fields for new transactions
                System.out.println("  [13] frq: " + row.get("frq") + " (CRITICAL: should be -1 for posted)");
                System.out.println("  [14] fDefPmt: " + row.get("fDefPmt"));
                System.out.println("  [15] mMemo: " + row.get("mMemo"));
                System.out.println("  [16] oltt: " + row.get("oltt"));
                System.out.println("  [17] grfEntryMethods: " + row.get("grfEntryMethods"));
                System.out.println("  [18] ps: " + row.get("ps"));
                System.out.println("  [19] amtVat: " + row.get("amtVat"));
                System.out.println("  [20] grftt: " + row.get("grftt") + " (CRITICAL: should be 0 for normal)");
                System.out.println("  [21] act: " + row.get("act"));
                System.out.println("  [22] cFrqInst: " + row.get("cFrqInst"));
                System.out.println("  [23] fPrint: " + row.get("fPrint"));
                System.out.println("  [24] mFiStmtId: " + row.get("mFiStmtId"));
                System.out.println("  [25] olst: " + row.get("olst"));
                System.out.println("  [26] fDebtPlan: " + row.get("fDebtPlan"));
                System.out.println("  [27] grfstem: " + row.get("grfstem"));
                System.out.println("  [28] cpmtsRemaining: " + row.get("cpmtsRemaining"));
                System.out.println("  [29] instt: " + row.get("instt"));
                System.out.println("  [30] htrnSrc: " + row.get("htrnSrc"));
                System.out.println("  [31] payt: " + row.get("payt"));
                System.out.println("  [32] grftf: " + row.get("grftf"));
                System.out.println("  [33] lHtxsrc: " + row.get("lHtxsrc"));
                System.out.println("  [34] lHcrncUser: " + row.get("lHcrncUser") + " (CRITICAL: should be 45 for USD)");
                System.out.println("  [35] amtUser: " + row.get("amtUser"));
                System.out.println("  [36] amtVATUser: " + row.get("amtVATUser"));
                System.out.println("  [37] tef: " + row.get("tef"));
                System.out.println("  [38] fRefund: " + row.get("fRefund"));
                System.out.println("  [39] fReimburse: " + row.get("fReimburse"));
                
                Object dtSerial = row.get("dtSerial");
                System.out.println("  [40] dtSerial: " + (dtSerial != null ? dateFormat.format(dtSerial) : "null"));
                System.out.println("  [41] fUpdated: " + row.get("fUpdated") + " (CRITICAL: should be 1/TRUE)");
                System.out.println("  [42] fCCPmt: " + row.get("fCCPmt"));
                System.out.println("  [43] fDefBillAmt: " + row.get("fDefBillAmt"));
                System.out.println("  [44] fDefBillDate: " + row.get("fDefBillDate"));
                System.out.println("  [45] lHclsKak: " + row.get("lHclsKak"));
                System.out.println("  [46] lHclsKak2: " + row.get("lHclsKak2"));
                System.out.println("  [47] lHclsKak3: " + row.get("lHclsKak3"));
                
                Object dtCloseOffYear = row.get("dtCloseOffYear");
                System.out.println("  [48] dtCloseOffYear: " + (dtCloseOffYear != null ? dateFormat.format(dtCloseOffYear) : "null"));
                Object dtOldRel = row.get("dtOldRel");
                System.out.println("  [49] dtOldRel: " + (dtOldRel != null ? dateFormat.format(dtOldRel) : "null"));
                
                System.out.println("  [50] hbillHead: " + row.get("hbillHead"));
                System.out.println("  [51] iinst: " + row.get("iinst") + " (CRITICAL: should be -1)");
                System.out.println("  [52] amtBase: " + row.get("amtBase"));
                System.out.println("  [53] rt: " + row.get("rt"));
                System.out.println("  [54] amtPreRec: " + row.get("amtPreRec"));
                System.out.println("  [55] amtPreRec2: " + row.get("amtPreRec2"));
                System.out.println("  [56] hstmtRel: " + row.get("hstmtRel"));
                System.out.println("  [57] dRateToBase: " + row.get("dRateToBase"));
                System.out.println("  [58] lHpay: " + row.get("lHpay"));
                System.out.println("  [59] sguid: " + row.get("sguid"));
                System.out.println("  [60] szAggTrnId: " + row.get("szAggTrnId"));
                System.out.println("  [61] rgbDigest: " + row.get("rgbDigest"));
            }}
            
            System.out.println("\\n========================================");
            System.out.println("Total: " + count + " transactions");
            System.out.println("========================================");
            System.out.println("\\nSUCCESS");
        }} finally {{
            if (db != null) {{
                db.close();
            }}
        }}
    }}
}}
"""
    
    # Write Java file
    with open("/tmp/ListTransactions.java", "w") as f:
        f.write(java_code)
    
    # Compile
    compile_result = subprocess.run([
        "javac",
        "-cp", SUNRISE_JAR,
        "/tmp/ListTransactions.java"
    ], capture_output=True, text=True)
    
    if compile_result.returncode != 0:
        raise Exception(f"Java compile failed: {compile_result.stderr}")
    
    # Run
    run_result = subprocess.run([
        "java",
        "-cp", f"{SUNRISE_JAR}:/tmp",
        "ListTransactions"
    ], capture_output=True, text=True)
    
    if run_result.stdout:
        print(run_result.stdout)
    
    if run_result.returncode != 0:
        if run_result.stderr:
            print(run_result.stderr, file=sys.stderr)
        raise Exception(f"Java failed with return code {run_result.returncode}")
    
    if "SUCCESS" not in run_result.stdout:
        raise Exception(f"List failed")
    
    return True

def list_accounts_java(mdb_path, password=""):
    """
    List all accounts from the database
    
    Args:
        mdb_path: Path to the Money database file
        password: The Money file password
    """
    
    # Escape the path for Java strings  
    escaped_mdb_path = mdb_path.replace("\\", "\\\\").replace("\"", "\\\"")
    
    # Escape the password for Java strings
    escaped_password = password.replace("\\", "\\\\").replace("\"", "\\\"")
    
    # Determine if this is a .mdb (decrypted) or .mny (encrypted) file
    is_mdb = mdb_path.lower().endswith('.mdb')
    
    java_code = f"""
import com.healthmarketscience.jackcess.*;
import java.io.File;
import java.math.BigDecimal;

public class ListAccounts {{
    public static void main(String[] args) throws Exception {{
        File mdbFile = new File("{escaped_mdb_path}");
        String password = "{escaped_password}";
        boolean isMdb = {str(is_mdb).lower()};
        
        System.out.println("=== Listing Accounts ===");
        
        Database db = null;
        try {{
            // Open database
            if (isMdb && password.isEmpty()) {{
                db = Database.open(mdbFile);
            }} else {{
                CryptCodecProvider codec = new CryptCodecProvider(password);
                db = Database.open(mdbFile, false, true, null, null, codec);
            }}
            
            // Read ACCT table
            Table acctTable = db.getTable("ACCT");
            
            System.out.println("Total accounts: " + acctTable.getRowCount());
            System.out.println("\\nAll Column names:");
            int colIndex = 1;
            for (Column col : acctTable.getColumns()) {{
                System.out.println("  [" + colIndex + "] " + col.getName() + " (" + col.getType() + ")");
                colIndex++;
            }}
            
            System.out.println("\\n=== Account Data ===");
            
            int count = 0;
            for (java.util.Map<String, Object> row : acctTable) {{
                count++;
                System.out.println("\\n========================================");
                System.out.println("Account #" + count + ":");
                System.out.println("========================================");
                System.out.println("  hacct: " + row.get("hacct"));
                System.out.println("  szFull: " + row.get("szFull"));
                System.out.println("  at: " + row.get("at") + " (account type)");
                System.out.println("  ast: " + row.get("ast") + " (account sub-type)");
                System.out.println("  fClosed: " + row.get("fClosed"));
                System.out.println("  amtBalanceSLOTH: " + row.get("amtBalanceSLOTH") + " (CRITICAL: current balance)");
                System.out.println("  amtOpen: " + row.get("amtOpen"));
                System.out.println("  hcrnc: " + row.get("hcrnc") + " (currency)");
                System.out.println("  fUpdated: " + row.get("fUpdated"));
                System.out.println("  sguid: " + row.get("sguid"));
                
                // Show all fields for debugging
                System.out.println("\\n  All fields:");
                for (Column col : acctTable.getColumns()) {{
                    Object value = row.get(col.getName());
                    if (value != null) {{
                        System.out.println("    " + col.getName() + ": " + value);
                    }}
                }}
            }}
            
            System.out.println("\\n========================================");
            System.out.println("Total: " + count + " accounts");
            System.out.println("========================================");
            System.out.println("\\nSUCCESS");
        }} finally {{
            if (db != null) {{
                db.close();
            }}
        }}
    }}
}}
"""
    
    # Write Java file
    with open("/tmp/ListAccounts.java", "w") as f:
        f.write(java_code)
    
    # Compile
    compile_result = subprocess.run([
        "javac",
        "-cp", SUNRISE_JAR,
        "/tmp/ListAccounts.java"
    ], capture_output=True, text=True)
    
    if compile_result.returncode != 0:
        raise Exception(f"Java compile failed: {compile_result.stderr}")
    
    # Run
    run_result = subprocess.run([
        "java",
        "-cp", f"{SUNRISE_JAR}:/tmp",
        "ListAccounts"
    ], capture_output=True, text=True)
    
    if run_result.stdout:
        print(run_result.stdout)
    
    if run_result.returncode != 0:
        if run_result.stderr:
            print(run_result.stderr, file=sys.stderr)
        raise Exception(f"Java failed with return code {run_result.returncode}")
    
    if "SUCCESS" not in run_result.stdout:
        raise Exception(f"Failed to list accounts")
    
    return True

def list_xacct_java(mdb_path, password=""):
    """
    List all extended account data (XACCT table) including balances
    
    Args:
        mdb_path: Path to the Money database file
        password: The Money file password
    """
    
    # Escape the path for Java strings  
    escaped_mdb_path = mdb_path.replace("\\", "\\\\").replace("\"", "\\\"")
    
    # Escape the password for Java strings
    escaped_password = password.replace("\\", "\\\\").replace("\"", "\\\"")
    
    # Determine if this is a .mdb (decrypted) or .mny (encrypted) file
    is_mdb = mdb_path.lower().endswith('.mdb')
    
    java_code = f"""
import com.healthmarketscience.jackcess.*;
import java.io.File;
import java.math.BigDecimal;

public class ListXACCT {{
    public static void main(String[] args) throws Exception {{
        File mdbFile = new File("{escaped_mdb_path}");
        String password = "{escaped_password}";
        boolean isMdb = {str(is_mdb).lower()};
        
        System.out.println("=== Listing XACCT Table ===");
        
        Database db = null;
        try {{
            // Open database
            if (isMdb && password.isEmpty()) {{
                db = Database.open(mdbFile);
            }} else {{
                CryptCodecProvider codec = new CryptCodecProvider(password);
                db = Database.open(mdbFile, false, true, null, null, codec);
            }}
            
            // Read XACCT table
            Table xacctTable = db.getTable("XACCT");
            
            System.out.println("Total XACCT records: " + xacctTable.getRowCount());
            System.out.println("\\nAll Column names and types:");
            int colIndex = 1;
            for (Column col : xacctTable.getColumns()) {{
                System.out.println("  [" + colIndex + "] " + col.getName() + " (" + col.getType() + ")");
                colIndex++;
            }}
            
            System.out.println("\\n=== XACCT Data ===");
            
            int count = 0;
            for (java.util.Map<String, Object> row : xacctTable) {{
                count++;
                System.out.println("\\n========================================");
                System.out.println("XACCT Record #" + count + ":");
                System.out.println("========================================");
                
                // Show ALL fields
                for (Column col : xacctTable.getColumns()) {{
                    Object value = row.get(col.getName());
                    String displayValue = (value != null) ? value.toString() : "null";
                    
                    // Highlight important fields
                    if ("hacct".equals(col.getName())) {{
                        System.out.println("  >>> hacct (Account ID): " + displayValue);
                    }} else if (col.getName().toLowerCase().contains("balance")) {{
                        System.out.println("  >>> " + col.getName() + " (BALANCE): " + displayValue + " (" + col.getType() + ")");
                    }} else {{
                        System.out.println("  " + col.getName() + ": " + displayValue);
                    }}
                }}
            }}
            
            System.out.println("\\n========================================");
            System.out.println("Total: " + count + " XACCT records");
            System.out.println("========================================");
            System.out.println("\\nSUCCESS");
        }} finally {{
            if (db != null) {{
                db.close();
            }}
        }}
    }}
}}
"""
    
    # Write Java file
    with open("/tmp/ListXACCT.java", "w") as f:
        f.write(java_code)
    
    # Compile
    compile_result = subprocess.run([
        "javac",
        "-cp", SUNRISE_JAR,
        "/tmp/ListXACCT.java"
    ], capture_output=True, text=True)
    
    if compile_result.returncode != 0:
        raise Exception(f"Java compile failed: {compile_result.stderr}")
    
    # Run
    run_result = subprocess.run([
        "java",
        "-cp", f"{SUNRISE_JAR}:/tmp",
        "ListXACCT"
    ], capture_output=True, text=True)
    
    if run_result.stdout:
        print(run_result.stdout)
    
    if run_result.returncode != 0:
        if run_result.stderr:
            print(run_result.stderr, file=sys.stderr)
        raise Exception(f"Java failed with return code {run_result.returncode}")
    
    if "SUCCESS" not in run_result.stdout:
        raise Exception(f"Failed to list XACCT")
    
    return True


def update_account_balance_java(mdb_path, account_id, amount, password=""):
    """
    Update account balance after inserting a transaction
    This is CRITICAL for Money to correctly display the account
    
    Args:
        mdb_path: Path to the Money database file
        account_id: The account ID (hacct) to update
        amount: The transaction amount to add to the balance
        password: The Money file password
    """
    
    escaped_mdb_path = mdb_path.replace("\\", "\\\\").replace("\"", "\\\"")
    escaped_password = password.replace("\\", "\\\\").replace("\"", "\\\"")
    is_mdb = mdb_path.lower().endswith('.mdb')
    
    java_code = f"""
import com.healthmarketscience.jackcess.*;
import java.io.File;
import java.math.BigDecimal;
import java.util.Map;

public class UpdateAccountBalance {{
    public static void main(String[] args) throws Exception {{
        File mdbFile = new File("{escaped_mdb_path}");
        String password = "{escaped_password}";
        boolean isMdb = {str(is_mdb).lower()};
        
        System.out.println("=== Updating Account Balance ===");
        System.out.println("Account ID: {account_id}");
        System.out.println("Transaction amount: {amount}");
        
        Database db = null;
        try {{
            // Open database
            if (isMdb && password.isEmpty()) {{
                db = Database.open(mdbFile);
            }} else {{
                CryptCodecProvider codec = new CryptCodecProvider(password);
                db = Database.open(mdbFile, false, true, null, null, codec);
            }}
            
            // Find and update the XACCT row
            Table xacctTable = db.getTable("XACCT");
            
            System.out.println("\\nXACCT table columns:");
            for (Column col : xacctTable.getColumns()) {{
                System.out.println("  " + col.getName() + " (" + col.getType() + ")");
            }}
            
            boolean found = false;
            Cursor cursor = xacctTable.getDefaultCursor();
            cursor.beforeFirst();
            while (cursor.moveToNextRow()) {{
                Map<String, Object> row = cursor.getCurrentRow();{{
                Integer hacct = (Integer) row.get("hacct");
                if (hacct != null && hacct.equals({account_id})) {{
                    found = true;
                    
                    // Find the balance field (could be amtBalance or amtBalanceSLOTH)
                    Object balanceObj = null;
                    String balanceFieldName = null;
                    
                    if (row.containsKey("amtBalanceSLOTH")) {{
                        balanceObj = row.get("amtBalanceSLOTH");
                        balanceFieldName = "amtBalanceSLOTH";
                    }} else if (row.containsKey("amtBalance")) {{
                        balanceObj = row.get("amtBalance");
                        balanceFieldName = "amtBalance";
                    }}
                    
                    if (balanceFieldName == null) {{
                        System.err.println("ERROR: Could not find balance field in XACCT table");
                        System.exit(1);
                    }}
                    
                    System.out.println("\\nUsing balance field: " + balanceFieldName);
                    
                    // Get current balance
                    BigDecimal currentBalance = BigDecimal.ZERO;
                    if (balanceObj != null) {{
                        if (balanceObj instanceof BigDecimal) {{
                            currentBalance = (BigDecimal) balanceObj;
                        }} else if (balanceObj instanceof Double) {{
                            currentBalance = BigDecimal.valueOf((Double) balanceObj);
                        }} else if (balanceObj instanceof Float) {{
                            currentBalance = BigDecimal.valueOf((Float) balanceObj);
                        }} else {{
                            currentBalance = new BigDecimal(balanceObj.toString());
                        }}
                    }}
                    
                    System.out.println("Current balance: " + currentBalance);
                    
                    // Add the transaction amount
                    BigDecimal transactionAmount = new BigDecimal("{amount}");
                    BigDecimal newBalance = currentBalance.add(transactionAmount);
                    
                    System.out.println("Transaction amount: " + transactionAmount);
                    System.out.println("New balance: " + newBalance);
                    
                    // Update the row using cursor
                    cursor.setCurrentRowValue(xacctTable.getColumn(balanceFieldName), newBalance);
                    
                    System.out.println("\\n✓ Updated account " + {account_id} + " balance in " + balanceFieldName);
                    break;
                }}
            }}
            
            if (!found) {{
                System.err.println("ERROR: Account " + {account_id} + " not found in XACCT table");
                System.exit(1);
            }}
            
            System.out.println("SUCCESS");
        }} finally {{
            if (db != null) {{
                db.close();
            }}
        }}
    }}
}}
"""
    
    # Write Java file
    with open("/tmp/UpdateAccountBalance.java", "w") as f:
        f.write(java_code)
    
    # Compile
    compile_result = subprocess.run([
        "javac",
        "-cp", SUNRISE_JAR,
        "/tmp/UpdateAccountBalance.java"
    ], capture_output=True, text=True)
    
    if compile_result.returncode != 0:
        raise Exception(f"Java compile failed: {compile_result.stderr}")
    
    # Run
    run_result = subprocess.run([
        "java",
        "-cp", f"{SUNRISE_JAR}:/tmp",
        "UpdateAccountBalance"
    ], capture_output=True, text=True)
    
    if run_result.stdout:
        print(run_result.stdout)
    
    if run_result.returncode != 0:
        if run_result.stderr:
            print(run_result.stderr, file=sys.stderr)
        raise Exception(f"Java failed with return code {run_result.returncode}")
    
    if "SUCCESS" not in run_result.stdout:
        raise Exception(f"Balance update failed")
    
    return True


def find_next_id_java(mdb_path, password=""):
    """
    Find the next available transaction ID
    
    Args:
        mdb_path: Path to the Money database file
        password: The Money file password
    """
    
    # Escape the path for Java strings  
    escaped_mdb_path = mdb_path.replace("\\", "\\\\").replace("\"", "\\\"")
    
    # Escape the password for Java strings
    escaped_password = password.replace("\\", "\\\\").replace("\"", "\\\"")
    
    # Determine if this is a .mdb (decrypted) or .mny (encrypted) file
    is_mdb = mdb_path.lower().endswith('.mdb')
    
    java_code = f"""
import com.healthmarketscience.jackcess.*;
import java.io.File;

public class FindNextID {{
    public static void main(String[] args) throws Exception {{
        File mdbFile = new File("{escaped_mdb_path}");
        String password = "{escaped_password}";
        boolean isMdb = {str(is_mdb).lower()};
        
        System.out.println("=== Finding Next Available Transaction ID ===");
        
        Database db = null;
        try {{
            // Open database
            if (isMdb && password.isEmpty()) {{
                db = Database.open(mdbFile);
            }} else {{
                CryptCodecProvider codec = new CryptCodecProvider(password);
                db = Database.open(mdbFile, false, true, null, null, codec);
            }}
            
            // Read TRN table
            Table trnTable = db.getTable("TRN");
            
            int maxId = 0;
            int count = 0;
            for (java.util.Map<String, Object> row : trnTable) {{
                Integer htrn = (Integer) row.get("htrn");
                if (htrn != null && htrn > maxId) {{
                    maxId = htrn;
                }}
                count++;
            }}
            
            int nextId = maxId + 1;
            
            System.out.println("\\nTotal transactions: " + count);
            System.out.println("Maximum transaction ID: " + maxId);
            System.out.println("Next available ID: " + nextId);
            System.out.println("\\n✓ Use this ID for your next transaction insertion");
            System.out.println("SUCCESS");
        }} finally {{
            if (db != null) {{
                db.close();
            }}
        }}
    }}
}}
"""
    
    # Write Java file
    with open("/tmp/FindNextID.java", "w") as f:
        f.write(java_code)
    
    # Compile
    compile_result = subprocess.run([
        "javac",
        "-cp", SUNRISE_JAR,
        "/tmp/FindNextID.java"
    ], capture_output=True, text=True)
    
    if compile_result.returncode != 0:
        raise Exception(f"Java compile failed: {compile_result.stderr}")
    
    # Run
    run_result = subprocess.run([
        "java",
        "-cp", f"{SUNRISE_JAR}:/tmp",
        "FindNextID"
    ], capture_output=True, text=True)
    
    if run_result.stdout:
        print(run_result.stdout)
    
    if run_result.returncode != 0:
        if run_result.stderr:
            print(run_result.stderr, file=sys.stderr)
        raise Exception(f"Java failed with return code {run_result.returncode}")
    
    if "SUCCESS" not in run_result.stdout:
        raise Exception(f"Failed to find next ID")
    
    return True

def main():
    if len(sys.argv) < 2:
        print("Usage:")
        print("  List:          money_insert.py <mny_file> list [password]")
        print("  Accounts:      money_insert.py <mny_file> accounts [password]")
        print("  XACCT:         money_insert.py <mny_file> xacct [password]")
        print("  Payee:         money_insert.py <mny_file> payee <payee_id> <payee_name> [password]")
        print("  Transaction:   money_insert.py <mny_file> transaction <htrn> <hact> <amt> <hpay> [memo] [password]")
        print("  Update Balance: money_insert.py <mny_file> updatebalance <hacct> <amt> [password]")
        print("  Compare:       money_insert.py <mny_file> compare <htrn> [password]")
        print("  Next ID:       money_insert.py <mny_file> nextid [password]")
        print()
        print("Examples:")
        print("  python3 money_insert.py file.mdb list")
        print("  python3 money_insert.py file.mdb accounts")
        print("  python3 money_insert.py file.mdb xacct  # View XACCT table with balances")
        print("  python3 money_insert.py file.mdb nextid")
        print("  python3 money_insert.py file.mdb payee 999 \"Test Payee\"")
        print("  python3 money_insert.py file.mdb transaction 500 2 -50.00 999 \"Grocery shopping\"")
        print("  python3 money_insert.py file.mdb updatebalance 2 -50.00  # Update account 2 balance")
        print("  python3 money_insert.py file.mdb compare 252")
        sys.exit(1)
    
    file_path = sys.argv[1]
    command = sys.argv[2] if len(sys.argv) > 2 else ""
    
    if command == "list":
        password = sys.argv[3] if len(sys.argv) > 3 else ""
        
        print(f"Listing transactions from: {file_path}")
        
        try:
            list_transactions_java(file_path, password)
            print(f"✓ Successfully listed transactions")
        except Exception as e:
            print(f"✗ Failed: {e}", file=sys.stderr)
            sys.exit(1)
    
    elif command == "accounts":
        password = sys.argv[3] if len(sys.argv) > 3 else ""
        
        print(f"Listing accounts from: {file_path}")
        
        try:
            list_accounts_java(file_path, password)
        except Exception as e:
            print(f"✗ Failed: {e}", file=sys.stderr)
            sys.exit(1)
    
    elif command == "xacct":
        password = sys.argv[3] if len(sys.argv) > 3 else ""
        
        print(f"Listing XACCT table from: {file_path}")
        
        try:
            list_xacct_java(file_path, password)
        except Exception as e:
            print(f"✗ Failed: {e}", file=sys.stderr)
            sys.exit(1)
    
    elif command == "updatebalance":
        if len(sys.argv) < 5:
            print("Error: updatebalance command requires: <hacct> <amt> [password]")
            sys.exit(1)
        
        account_id = int(sys.argv[3])
        amount = float(sys.argv[4])
        password = sys.argv[5] if len(sys.argv) > 5 else ""
        
        print(f"Updating balance for account {account_id}: {amount:+.2f}")
        print(f"File: {file_path}")
        
        try:
            update_account_balance_java(file_path, account_id, amount, password)
            print(f"✓ Successfully updated account balance")
        except Exception as e:
            print(f"✗ Failed: {e}", file=sys.stderr)
            sys.exit(1)
    
    elif command == "nextid":
        password = sys.argv[3] if len(sys.argv) > 3 else ""
        
        print(f"Finding next available transaction ID in: {file_path}")
        
        try:
            find_next_id_java(file_path, password)
        except Exception as e:
            print(f"✗ Failed: {e}", file=sys.stderr)
            sys.exit(1)
    
    elif command == "compare":
        if len(sys.argv) < 4:
            print("Error: compare command requires: <htrn> [password]")
            sys.exit(1)
        
        reference_htrn = int(sys.argv[3])
        password = sys.argv[4] if len(sys.argv) > 4 else ""
        
        print(f"Comparing new transaction format against htrn {reference_htrn}")
        print(f"File: {file_path}")
        print()
        print("This will show you exactly what fields match and what differs.")
        print()
        
        # This just runs the list command filtered to one transaction
        # You can manually compare, or we could enhance this further
        try:
            list_transactions_java(file_path, password)
            print(f"\n✓ Review the fields for transaction {reference_htrn} above")
            print(f"All CRITICAL fields should match:")
            print(f"  [13] frq = -1")
            print(f"  [20] grftt = 0")
            print(f"  [34] lHcrncUser = 45")
            print(f"  [41] fUpdated = true")
            print(f"  [51] iinst = -1")
        except Exception as e:
            print(f"✗ Failed: {e}", file=sys.stderr)
            sys.exit(1)
    
    elif command == "payee":
        if len(sys.argv) < 5:
            print("Error: payee command requires: <payee_id> <payee_name> [password]")
            sys.exit(1)
        
        payee_id = int(sys.argv[3])
        payee_name = sys.argv[4]
        password = sys.argv[5] if len(sys.argv) > 5 else ""
        
        print(f"Inserting payee {payee_id}: {payee_name}")
        print(f"File: {file_path}")
        
        try:
            insert_payee_java(file_path, payee_id, payee_name, password)
            print(f"✓ Successfully inserted payee")
        except Exception as e:
            print(f"✗ Failed: {e}", file=sys.stderr)
            sys.exit(1)
    
    elif command == "transaction":
        if len(sys.argv) < 7:
            print("Error: transaction command requires: <htrn> <hact> <amt> <hpay> [memo] [password]")
            sys.exit(1)
        
        htrn = int(sys.argv[3])
        hact = int(sys.argv[4])
        amt = float(sys.argv[5])
        hpay = int(sys.argv[6])
        memo = sys.argv[7] if len(sys.argv) > 7 and not sys.argv[7].startswith("-") else ""
        password = sys.argv[8] if len(sys.argv) > 8 else (sys.argv[7] if memo == "" else "")
        
        transaction_data = {
            'htrn': htrn,
            'hact': hact,
            'amt': amt,
            'hpay': hpay,
            'hcat': None,  # No category (will be null in database)
            'szMemo': memo,
            'szNum': ''
        }
        
        print(f"Inserting transaction {htrn}: ${amt}")
        print(f"File: {file_path}")
        
        try:
            # Step 1: Insert the transaction
            insert_transaction_java(file_path, transaction_data, password)
            print(f"✓ Successfully inserted transaction")
            
            # Step 2: Update the account balance (CRITICAL!)
            print(f"\nUpdating account {hact} balance by ${amt:+.2f}...")
            update_account_balance_java(file_path, hact, amt, password)
            print(f"✓ Successfully updated account balance")
            
            print(f"\n✅ Transaction {htrn} fully synced!")
        except Exception as e:
            print(f"✗ Failed: {e}", file=sys.stderr)
            sys.exit(1)
    
    else:
        print(f"Error: Unknown command '{command}'")
        print("Valid commands: list, accounts, xacct, payee, transaction, updatebalance, compare, nextid")
        sys.exit(1)

if __name__ == '__main__':
    main()
