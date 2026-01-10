import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

#if canImport(mdbtools_c)
import mdbtools_c
#endif

// Public errors to match existing string-based mapping in callers
public enum MoneyDecryptorBridgeError: Error {
    case unsupportedFormat
    case badPassword
    case moduleUnavailable
}

// Internal core decryptor implementing MSISAM RC4 blank-password decryption
private enum MoneyDecryptorCore {
    private static let debug = true
    private static func dbg(_ msg: String) { if debug { print("[MoneyDecryptor] \(msg)") } }

    // Constants inferred/observed from Money/Jet format and DA2CodecParams
    private static let saltOffset = 114
    private static let saltLength = 4
    private static let encryptionFlagsOffset = 664
    private static let cryptCheckStart = 745
    private static let maxEncryptedPage = 14
    private static let pageSize = 4096

    static func decryptIfNeeded(inputPath: String, password: String?) throws -> String {
        dbg("Entered decryptIfNeeded for path: \(inputPath)")
        // For now, support only blank/nil password variant (Money Plus Sunset)
        if let pwd = password, !pwd.isEmpty {
            throw MoneyDecryptorBridgeError.badPassword
        }

        let url = URL(fileURLWithPath: inputPath)
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        if data.count % pageSize != 0 {
            dbg("Page size mismatch: size % \(data.count) not multiple of \(pageSize)")
            throw MoneyDecryptorBridgeError.unsupportedFormat
        }
        let totalPages = data.count / pageSize
        if totalPages <= maxEncryptedPage {
            dbg("Too few pages: \(totalPages) <= maxEncryptedPage \(maxEncryptedPage)")
            throw MoneyDecryptorBridgeError.unsupportedFormat
        }
        dbg("Input path: \(inputPath)")
        dbg("Size: \(data.count) bytes, pages: \(totalPages), pageSize: \(pageSize)")

        var bytes = [UInt8](data)
        if bytes.count < encryptionFlagsOffset + 4 || bytes.count < saltOffset + saltLength {
            dbg("Header too small for offsets: bytes=\(bytes.count)")
            throw MoneyDecryptorBridgeError.unsupportedFormat
        }
        let salt = Array(bytes[saltOffset..<(saltOffset + saltLength)])
        let flagsLE = UInt32(bytes[encryptionFlagsOffset]) |
                      (UInt32(bytes[encryptionFlagsOffset + 1]) << 8) |
                      (UInt32(bytes[encryptionFlagsOffset + 2]) << 16) |
                      (UInt32(bytes[encryptionFlagsOffset + 3]) << 24)
        dbg(String(format: "SALT: %@", hex(salt)))
        dbg(String(format: "FLAGS (LE int): %u, FLAGS (hex): %@", flagsLE, hex(Array(bytes[encryptionFlagsOffset..<(encryptionFlagsOffset+4)]))))
        dbg("cryptCheckStart: \(cryptCheckStart), maxEncryptedPage: \(maxEncryptedPage)")

        // Require USE_SHA1 flag
        let USE_SHA1: UInt32 = 32
        if (flagsLE & USE_SHA1) == 0 {
            dbg("USE_SHA1 not set in flags: \(flagsLE)")
            throw MoneyDecryptorBridgeError.unsupportedFormat
        }

        let candidateKeys = makeCandidateKeysBlankPassword(salt: salt)
        dbg("Candidate key count: \(candidateKeys.count)")
        for (idx, key) in candidateKeys.enumerated() {
            dbg("Trying candidate #\(idx) key: \(hex(key, max: 20))")
            var dec = bytes
            for pageIndex in 0...maxEncryptedPage {
                let start = pageIndex * pageSize
                let end = start + pageSize
                if end > dec.count { break }
                var page = Array(dec[start..<end])
                var rc4 = MoneyRC4Bridge(key: key)
                if cryptCheckStart < page.count {
                    rc4.apply(to: &page, offset: cryptCheckStart)
                }
                dec.replaceSubrange(start..<end, with: page)
            }
            // Clear encryption flags and salt in header
            for i in 0..<4 { dec[encryptionFlagsOffset + i] = 0 }
            for i in 0..<saltLength { dec[saltOffset + i] = 0 }

            let tmpURL = try writeTempMDB(buffer: dec, originalURL: url)
            dbg("Wrote temp decrypted MDB: \(tmpURL.path)")

            #if canImport(mdbtools_c)
            if let mdb = money_mdb_open(tmpURL.path) {
                defer { money_mdb_close(mdb) }
                if let _ = money_mdb_open_acct(mdb) {
                    dbg("Validation succeeded with candidate #\(idx)")
                    return tmpURL.path
                } else {
                    dbg("money_mdb_open_acct failed for candidate #\(idx)")
                }
            } else {
                dbg("money_mdb_open failed for candidate #\(idx)")
            }
            #else
            // No mdbtools; return decrypted path without validation
            dbg("mdbtools_c not available; returning decrypted path without validation")
            return tmpURL.path
            #endif
        }

        dbg("All candidate keys failed to validate")
        throw MoneyDecryptorBridgeError.unsupportedFormat
    }

    private static func writeTempMDB(buffer: [UInt8], originalURL: URL) throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
        let base = originalURL.deletingPathExtension().lastPathComponent
        let tmpURL = tmpDir.appendingPathComponent("\(base)-decrypted-\(UUID().uuidString).mdb")
        try Data(buffer).write(to: tmpURL, options: .atomic)
        return tmpURL
    }

    // Candidate keys for blank password variant (USE_SHA1)
    private static func makeCandidateKeysBlankPassword(salt: [UInt8]) -> [[UInt8]] {
        var keys: [[UInt8]] = []
        let pwdBuf40 = [UInt8](repeating: 0, count: 40)
        let trailing20 = Array(pwdBuf40.suffix(20))
        let md5Pwd40 = md5(pwdBuf40)
        let zeros20 = [UInt8](repeating: 0, count: 20)
        let md5z40 = md5([UInt8](repeating: 0, count: 40))
        let md5z20 = md5(zeros20)
        let saltLE = salt
        let saltBE = Array(salt.reversed())

        // Likely recipes
        keys.append(sha1(saltLE + md5Pwd40 + trailing20))
        keys.append(sha1(saltLE + md5Pwd40))
        keys.append(sha1(md5Pwd40 + saltLE))
        keys.append(sha1(saltLE + trailing20 + md5Pwd40))
        // BE salt variants
        keys.append(sha1(saltBE + md5Pwd40 + trailing20))
        keys.append(sha1(saltBE + md5Pwd40))
        keys.append(sha1(md5Pwd40 + saltBE))
        keys.append(sha1(saltBE + trailing20 + md5Pwd40))
        // Fallbacks
        keys.append(sha1(saltLE + [UInt8](repeating: 0, count: 40)))
        keys.append(sha1([UInt8](repeating: 0, count: 40) + saltLE))
        keys.append(sha1(saltLE + md5z40))
        keys.append(sha1(md5z40 + saltLE))
        keys.append(sha1(saltLE + zeros20))
        keys.append(sha1(zeros20 + saltLE))
        keys.append(sha1(saltLE + md5z20))
        keys.append(sha1(md5z20 + saltLE))

        var seen = Set<String>()
        var uniq: [[UInt8]] = []
        for k in keys {
            let hx = k.map { String(format: "%02x", $0) }.joined()
            if !seen.contains(hx) { seen.insert(hx); uniq.append(k) }
        }
        return uniq
    }

    // Hash helpers and hex
    #if canImport(CryptoKit)
    private static func sha1(_ bytes: [UInt8]) -> [UInt8] {
        let digest = Insecure.SHA1.hash(data: Data(bytes))
        return Array(digest)
    }
    private static func md5(_ bytes: [UInt8]) -> [UInt8] {
        let digest = Insecure.MD5.hash(data: Data(bytes))
        return Array(digest)
    }
    #else
    private static func sha1(_ bytes: [UInt8]) -> [UInt8] { return [] }
    private static func md5(_ bytes: [UInt8]) -> [UInt8] { return [] }
    #endif

    private static func hex(_ bytes: [UInt8], max: Int? = nil) -> String {
        let n = max.map { min($0, bytes.count) } ?? bytes.count
        var s = ""
        for i in 0..<n { s += String(format: "%02x", bytes[i]) }
        if n < bytes.count { s += "..." }
        return s
    }
}

// Simple RC4 implementation used by the decryptor
private struct MoneyRC4Bridge {
    private var s: [UInt8] = Array(0...255)
    private var i: UInt8 = 0
    private var j: UInt8 = 0

    init(key: [UInt8]) {
        var j: UInt8 = 0
        for i in 0..<256 {
            j = j &+ s[i] &+ key[i % key.count]
            s.swapAt(i, Int(j))
        }
        self.i = 0
        self.j = 0
    }

    mutating func apply(to data: inout [UInt8], offset: Int = 0) {
        var i = self.i
        var j = self.j
        let start = max(0, offset)
        if start >= data.count { return }
        for idx in start..<data.count {
            i = i &+ 1
            j = j &+ s[Int(i)]
            s.swapAt(Int(i), Int(j))
            let k = s[Int((s[Int(i)] &+ s[Int(j)]) & 0xFF)]
            data[idx] ^= k
        }
        self.i = i
        self.j = j
    }
}

// Public bridge exposing decrypt-to-temp API for the app target
public struct MoneyDecryptorBridge {
    /// Decrypts an encrypted Microsoft Money file (.mny/.mdb) to a temporary MDB path.
    /// - Parameters:
    ///   - fromFile: Filesystem path to the encrypted file.
    ///   - password: Optional password (blank/nil for Money Plus Sunset blank-password variant).
    /// - Returns: Filesystem path to a temporary decrypted MDB file.
    public static func decryptToTempFile(fromFile path: String, password: String? = "") throws -> String {
        return try MoneyDecryptorCore.decryptIfNeeded(inputPath: path, password: password)
    }
}

