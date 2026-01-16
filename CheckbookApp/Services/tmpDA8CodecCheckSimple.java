// DA8CodecCheckSimple.java  
// Determine salt without needing jackcess-encrypt

import java.io.File;
import java.io.RandomAccessFile;

public class DA8CodecCheckSimple {

  public static void main(String[] args) throws Exception {
    if (args.length < 1) {
      System.err.println("Usage: java DA8CodecCheckSimple <moneyFile.mny>");
      System.exit(1);
    }

    File moneyFile = new File(args[0]);
    
    System.out.println("╔════════════════════════════════════════════════════════════════════╗");
    System.out.println("║            DA8CodecCheckSimple - Read Header Data                  ║");
    System.out.println("╚════════════════════════════════════════════════════════════════════╝");
    System.out.println();
    System.out.println("File: " + moneyFile.getName());
    System.out.println();
    
    try (RandomAccessFile raf = new RandomAccessFile(moneyFile, "r")) {
      
      // Read 8-byte salt at offset 114
      System.out.println("═══ Salt at offset 114 ═══");
      byte[] salt = new byte[8];
      raf.seek(114);
      raf.readFully(salt);
      System.out.println("  Full 8 bytes: " + bytesToHex(salt));
      System.out.println("  First 4 bytes: " + bytesToHex(salt, 0, 4));
      System.out.println("  Last 4 bytes: " + bytesToHex(salt, 4, 4));
      System.out.println();
      
      // XOR first and last
      byte[] xored = new byte[4];
      for (int i = 0; i < 4; i++) {
        xored[i] = (byte)(salt[i] ^ salt[i + 4]);
      }
      System.out.println("  XOR(first 4, last 4): " + bytesToHex(xored));
      System.out.println();
      
      // Read encryption flags at offset 664
      System.out.println("═══ Encryption Flags at offset 664 ═══");
      byte[] flags = new byte[4];
      raf.seek(664);
      raf.readFully(flags);
      
      int flagValue = ((flags[0] & 0xFF)) | 
                      ((flags[1] & 0xFF) << 8) | 
                      ((flags[2] & 0xFF) << 16) | 
                      ((flags[3] & 0xFF) << 24);
      
      System.out.println("  Bytes: " + bytesToHex(flags));
      System.out.println("  LE Int: " + flagValue + " (0x" + Integer.toHexString(flagValue) + ")");
      System.out.println();
      
      // Check flags
      int NEW_ENCRYPTION = 6;
      int USE_SHA1 = 32;
      boolean hasNewEncryption = (flagValue & NEW_ENCRYPTION) != 0;
      boolean useSHA1 = (flagValue & USE_SHA1) != 0;
      
      System.out.println("  NEW_ENCRYPTION (bits 1&2): " + hasNewEncryption);
      System.out.println("  USE_SHA1 (bit 5): " + useSHA1);
      System.out.println();
      
      if (hasNewEncryption) {
        System.out.println("✓ File uses MSISAM encryption");
      } else {
        System.out.println("✓ File uses old Jet encryption");
      }
      System.out.println();
      
      // Read date field at offset 24
      System.out.println("═══ Date field at offset 24 ═══");
      byte[] dateBytes = new byte[8];
      raf.seek(24);
      raf.readFully(dateBytes);
      System.out.println("  Date bytes: " + bytesToHex(dateBytes));
      
      // Try to interpret as double
      long dateLong = 0;
      for (int i = 0; i < 8; i++) {
        dateLong |= ((long)(dateBytes[i] & 0xFF)) << (i * 8);
      }
      double dateValue = Double.longBitsToDouble(dateLong);
      System.out.println("  As double: " + dateValue);
      System.out.println();
      
      // Read surrounding header data
      System.out.println("═══ Header Context ═══");
      byte[] header100 = new byte[100];
      raf.seek(0);
      raf.readFully(header100);
      
      System.out.println("  Offset 0-31 (version + signature + date):");
      System.out.println("    " + bytesToHex(header100, 0, 32));
      System.out.println();
      
      System.out.println("  Offset 106-129 (around salt):");
      byte[] aroundSalt = new byte[24];
      raf.seek(106);
      raf.readFully(aroundSalt);
      System.out.println("    " + bytesToHex(aroundSalt));
      System.out.println();
      
      // Try to find patterns
      System.out.println("═══ Pattern Analysis ═══");
      
      // Check if there's a relationship between salt bytes
      System.out.println("Salt byte relationships:");
      for (int i = 0; i < 4; i++) {
        System.out.println("  salt[" + i + "] = 0x" + String.format("%02x", salt[i] & 0xFF) + 
                         ", salt[" + (i+4) + "] = 0x" + String.format("%02x", salt[i+4] & 0xFF) +
                         ", XOR = 0x" + String.format("%02x", (salt[i] ^ salt[i+4]) & 0xFF));
      }
      System.out.println();
      
      // Check if last 2 bytes are constant
      System.out.println("Last 2 bytes of salt: " + bytesToHex(salt, 6, 2));
      System.out.println("  (checking if this is constant across files)");
      System.out.println();
    }
    
    System.out.println("╔════════════════════════════════════════════════════════════════════╗");
    System.out.println("║                    End DA8CodecCheckSimple                         ║");
    System.out.println("╚════════════════════════════════════════════════════════════════════╝");
  }
  
  private static String bytesToHex(byte[] bytes) {
    return bytesToHex(bytes, 0, bytes.length);
  }
  
  private static String bytesToHex(byte[] bytes, int offset, int length) {
    StringBuilder sb = new StringBuilder();
    for (int i = 0; i < length; i++) {
      sb.append(String.format("%02x", bytes[offset + i] & 0xFF));
    }
    return sb.toString();
  }
}
