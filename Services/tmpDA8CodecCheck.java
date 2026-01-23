// DA8CodecCheck.java  
// Determine exactly which codec Java is using and why

import com.healthmarketscience.jackcess.Database;
import com.healthmarketscience.jackcess.CryptCodecProvider;

import java.io.File;
import java.io.RandomAccessFile;
import java.lang.reflect.Field;

public class DA8CodecCheck {

  public static void main(String[] args) throws Exception {
    if (args.length < 1) {
      System.err.println("Usage: java -cp .:<deps> DA8CodecCheck <moneyFile.mny> [password]");
      System.exit(1);
    }

    File moneyFile = new File(args[0]);
    String password = args.length > 1 ? args[1] : "";  // Default to blank password
    
    System.out.println("╔════════════════════════════════════════════════════════════════════╗");
    System.out.println("║              DA8CodecCheck - Determine Codec Selection             ║");
    System.out.println("╚════════════════════════════════════════════════════════════════════╝");
    System.out.println();
    System.out.println("File: " + moneyFile.getName());
    System.out.println("Password: " + (password.isEmpty() ? "(blank)" : "'" + password + "'"));
    System.out.println();
    
    // Read the flags directly to see what SHOULD be selected
    System.out.println("═══ STEP 1: Check Encryption Flags ═══");
    try (RandomAccessFile raf = new RandomAccessFile(moneyFile, "r")) {
      byte[] flags = new byte[4];
      raf.seek(664);
      raf.readFully(flags);
      
      int flagValue = ((flags[0] & 0xFF)) | 
                      ((flags[1] & 0xFF) << 8) | 
                      ((flags[2] & 0xFF) << 16) | 
                      ((flags[3] & 0xFF) << 24);
      
      System.out.println("Flags at offset 664:");
      System.out.println("  Bytes: " + bytesToHex(flags));
      System.out.println("  LE Int: " + flagValue + " (0x" + Integer.toHexString(flagValue) + ")");
      System.out.println("  Binary: " + Integer.toBinaryString(flagValue));
      System.out.println();
      
      // Check NEW_ENCRYPTION flag (bit 1 and 2)
      int NEW_ENCRYPTION = 6;  // 0x06 = bits 1 and 2
      boolean hasNewEncryption = (flagValue & NEW_ENCRYPTION) != 0;
      
      System.out.println("Flag Analysis:");
      System.out.println("  NEW_ENCRYPTION (bits 1&2): " + hasNewEncryption);
      System.out.println("  (flags & 0x06) = 0x" + Integer.toHexString(flagValue & NEW_ENCRYPTION));
      System.out.println();
      
      if (hasNewEncryption) {
        System.out.println("✓ Should use MSISAM codec");
      } else {
        System.out.println("✓ Should use old Jet codec");
      }
      
      // Check USE_SHA1 flag (bit 5)
      int USE_SHA1 = 32;  // 0x20
      boolean useSHA1 = (flagValue & USE_SHA1) != 0;
      System.out.println("  USE_SHA1 (bit 5): " + useSHA1);
      System.out.println();
      
      // Read salt
      System.out.println("═══ Salt Information ═══");
      byte[] salt = new byte[8];
      raf.seek(114);
      raf.readFully(salt);
      System.out.println("Salt at offset 114 (8 bytes): " + bytesToHex(salt));
      System.out.println("  First 4 bytes: " + bytesToHex(salt, 0, 4));
      System.out.println("  Last 4 bytes: " + bytesToHex(salt, 4, 4));
      System.out.println();
    }
    
    // Now open with Jackcess and see what it actually chooses
    System.out.println("═══ STEP 2: Open with Jackcess ═══");
    CryptCodecProvider codec = new CryptCodecProvider(password);  // ⬅️ PASS THE PASSWORD!
    
    try (Database db = Database.open(moneyFile, true, true, null, null, codec)) {
      Field pageChannelField = db.getClass().getDeclaredField("_pageChannel");
      pageChannelField.setAccessible(true);
      Object pageChannel = pageChannelField.get(db);
      
      Field codecField = pageChannel.getClass().getDeclaredField("_codecHandler");
      codecField.setAccessible(true);
      Object codecHandler = codecField.get(pageChannel);
      
      String codecClassName = codecHandler.getClass().getName();
      String codecSimpleName = codecHandler.getClass().getSimpleName();
      
      System.out.println("Actual codec used:");
      System.out.println("  Full name: " + codecClassName);
      System.out.println("  Simple name: " + codecSimpleName);
      System.out.println();
      
      if (codecClassName.contains("MSISAM")) {
        System.out.println("✓ Java chose MSISAM codec");
        
        Field keyField = codecHandler.getClass().getDeclaredField("_encodingKey");
        keyField.setAccessible(true);
        byte[] key = (byte[]) keyField.get(codecHandler);
        
        System.out.println("  Key length: " + key.length + " bytes");
        System.out.println("  Key: " + bytesToHex(key));
        System.out.println();
        
        // Break down the key
        System.out.println("Key breakdown:");
        System.out.println("  Password digest (first 16 bytes): " + bytesToHex(key, 0, 16));
        System.out.println("  Salt (last 4 bytes): " + bytesToHex(key, 16, 4));
        
      } else if (codecClassName.contains("Jet")) {
        System.out.println("✓ Java chose Jet codec");
        
        Field keyField = codecHandler.getClass().getDeclaredField("_encodingKey");
        keyField.setAccessible(true);
        byte[] key = (byte[]) keyField.get(codecHandler);
        
        System.out.println("  Key length: " + key.length + " bytes");
        System.out.println("  Key: " + bytesToHex(key));
      }
      
      System.out.println();
      System.out.println("✅ SUCCESS - Password is correct!");
      
    } catch (IllegalStateException e) {
      if (e.getMessage().contains("Incorrect password")) {
        System.out.println("❌ FAILED - Incorrect password!");
        System.out.println();
        System.out.println("The password you provided does not match.");
        System.out.println("Try running again with the correct password:");
        System.out.println("  java -cp ... DA8CodecCheck \"" + moneyFile.getName() + "\" \"YourPassword\"");
      } else {
        throw e;
      }
    }
    
    System.out.println();
    System.out.println("╔════════════════════════════════════════════════════════════════════╗");
    System.out.println("║                          End DA8CodecCheck                         ║");
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
