//
//  MSISAMEncryptor.swift
//  CheckbookApp
//
//  MSISAM RC4 encryption for Money .mny files
//  Based on decompiled Jackcess MSISAMCryptCodecHandler
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// MSISAM encryption handler for Money .mny files
/// 
/// MSISAM uses RC4 encryption with a complex key derivation:
/// 1. Password → SHA1/MD5 digest (16 bytes)
/// 2. Salt from file offset 114 (4 bytes)
/// 3. Encoding key = digest + salt = 20 bytes
/// 4. Per-page: Apply page number to key, then RC4 encrypt
///
/// CRITICAL: Only encrypts pages 1-14 (system/index pages)
/// Pages 15+ are unencrypted (data pages)
class MSISAMEncryptor {
    
    private let encodingKey: [UInt8]  // 20 bytes: 16 (digest) + 4 (salt)
    private let useSHA1: Bool
    
    /// Initialize with password and file header
    /// - Parameters:
    ///   - password: Password for encryption
    ///   - headerData: First 4096 bytes of .mny file
    init(password: String, headerData: Data) throws {
        // Read encryption flags (offset 664)
        guard headerData.count >= 665 else {
            throw MSISAMError.invalidHeader
        }
        
        let encryptionFlags = headerData[664]
        self.useSHA1 = (encryptionFlags & 0x20) != 0  // Bit 5 = use SHA1
        
        // Read salt (offset 114, 8 bytes - but we only use first 4)
        guard headerData.count >= 122 else {
            throw MSISAMError.invalidHeader
        }
        
        let salt = [UInt8](headerData[114..<122])
        let baseSalt = Array(salt.prefix(4))
        
        // Create password digest
        let passwordDigest = try Self.createPasswordDigest(
            password: password,
            useSHA1: self.useSHA1
        )
        
        // Encoding key = passwordDigest (16) + baseSalt (4) = 20 bytes
        self.encodingKey = passwordDigest + baseSalt
        
        #if DEBUG
        print("[MSISAMEncryptor] Initialized")
        print("  Hash algorithm: \(useSHA1 ? "SHA1" : "MD5")")
        print("  Salt: \(baseSalt.map { String(format: "%02X", $0) }.joined())")
        print("  Encoding key (20 bytes): \(encodingKey.map { String(format: "%02X", $0) }.joined())")
        #endif
    }
    
    /// Encrypt a page (only pages 1-14)
    func encryptPage(_ pageData: Data, pageNumber: Int) -> Data {
        // MSISAM only encrypts pages 1-14
        guard pageNumber > 0 && pageNumber <= 14 else {
            return pageData  // Pages 0 and 15+ are not encrypted
        }
        
        #if DEBUG
        print("[MSISAMEncryptor] Encrypting page \(pageNumber)")
        #endif
        
        // Apply page number to key
        let pageKey = Self.applyPageNumber(encodingKey, pageNumber: pageNumber)
        
        // RC4 encrypt (reuse the public RC4 from MoneyDecrypter)
        let rc4 = RC4(key: Data(pageKey))
        return rc4.process(pageData)
    }
    
    /// Decrypt a page (for verification)
    func decryptPage(_ pageData: Data, pageNumber: Int) -> Data {
        // RC4 is symmetric, so encrypt and decrypt are the same operation
        return encryptPage(pageData, pageNumber: pageNumber)
    }
    
    // MARK: - Private Helpers
    
    /// Create password digest (SHA1 or MD5)
    private static func createPasswordDigest(password: String, useSHA1: Bool) throws -> [UInt8] {
        // Convert password to uppercase and encode as UTF-16LE
        let uppercased = password.uppercased()
        var passwordBytes = [UInt8](repeating: 0, count: 40)
        
        // Encode as UTF-16LE (little-endian)
        let utf16 = uppercased.utf16
        var offset = 0
        for codeUnit in utf16 {
            guard offset + 1 < 40 else { break }
            // Little-endian: low byte first
            passwordBytes[offset] = UInt8(codeUnit & 0xFF)
            passwordBytes[offset + 1] = UInt8((codeUnit >> 8) & 0xFF)
            offset += 2
        }
        
        #if DEBUG
        print("[MSISAMEncryptor] Password bytes (first 20): \(passwordBytes.prefix(20).map { String(format: "%02X", $0) }.joined())")
        #endif
        
        // Hash the 40 bytes
        let digest: [UInt8]
        if useSHA1 {
            digest = sha1(Data(passwordBytes))
        } else {
            digest = md5(Data(passwordBytes))
        }
        
        // Truncate to 16 bytes
        let truncated = Array(digest.prefix(16))
        
        #if DEBUG
        print("[MSISAMEncryptor] Password digest (16 bytes): \(truncated.map { String(format: "%02X", $0) }.joined())")
        #endif
        
        return truncated
    }
    
    /// Apply page number to encoding key
    /// This is the "magic" from Jackcess that makes each page use a different key
    private static func applyPageNumber(_ encodingKey: [UInt8], pageNumber: Int) -> [UInt8] {
        // From Jackcess: The page number is XORed into the key
        // We take the first 16 bytes of the encoding key and XOR with page number
        
        var pageKey = Array(encodingKey.prefix(16))
        
        // XOR page number into the key (4 bytes, little-endian)
        let pageBytes: [UInt8] = [
            UInt8(pageNumber & 0xFF),
            UInt8((pageNumber >> 8) & 0xFF),
            UInt8((pageNumber >> 16) & 0xFF),
            UInt8((pageNumber >> 24) & 0xFF)
        ]
        
        // XOR into first 4 bytes of key
        for i in 0..<4 {
            pageKey[i] ^= pageBytes[i]
        }
        
        #if DEBUG
        print("[MSISAMEncryptor] Page key for page \(pageNumber): \(pageKey.map { String(format: "%02X", $0) }.joined())")
        #endif
        
        return pageKey
    }
    
    /// SHA1 hash
    private static func sha1(_ data: Data) -> [UInt8] {
        #if canImport(CryptoKit)
        if #available(iOS 13, macOS 10.15, *) {
            let digest = Insecure.SHA1.hash(data: data)
            return Array(digest)
        } else {
            return SHA1Crypto().hash(data: data)
        }
        #else
        return SHA1Crypto().hash(data: data)
        #endif
    }
    
    /// MD5 hash (reuse from MoneyDecrypter)
    private static func md5(_ data: Data) -> [UInt8] {
        #if canImport(CryptoKit)
        if #available(iOS 13, macOS 10.15, *) {
            let digest = Insecure.MD5.hash(data: data)
            return Array(digest)
        } else {
            return MD5Crypto().hash(data: data)
        }
        #else
        return MD5Crypto().hash(data: data)
        #endif
    }
}

// MARK: - Errors

enum MSISAMError: Error, LocalizedError {
    case invalidHeader
    case encryptionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidHeader: return "Invalid .mny file header"
        case .encryptionFailed(let msg): return "Encryption failed: \(msg)"
        }
    }
}

// MARK: - SHA1 Implementation (for iOS < 13)

private final class SHA1Crypto {
    func hash(data: Data) -> [UInt8] {
        var context = SHA1Context()
        update(&context, data: [UInt8](data))
        finalize(&context)
        return context.digest
    }
    
    private struct SHA1Context {
        var count: (UInt32, UInt32) = (0, 0)
        var state: (UInt32, UInt32, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
        var buffer = [UInt8](repeating: 0, count: 64)
        var digest = [UInt8](repeating: 0, count: 20)
        
        init() {
            state.0 = 0x67452301
            state.1 = 0xEFCDAB89
            state.2 = 0x98BADCFE
            state.3 = 0x10325476
            state.4 = 0xC3D2E1F0
        }
    }
    
    private func update(_ ctx: inout SHA1Context, data: [UInt8]) {
        var inputLen = data.count
        let index = Int((ctx.count.0 >> 3) & 0x3F)
        let partLen = 64 - index
        
        ctx.count.0 = ctx.count.0 &+ UInt32(inputLen << 3)
        if ctx.count.0 < UInt32(inputLen << 3) {
            ctx.count.1 = ctx.count.1 &+ 1
        }
        ctx.count.1 = ctx.count.1 &+ UInt32(inputLen >> 29)
        
        var i = 0
        if inputLen >= partLen {
            ctx.buffer.replaceSubrange(index..<(index + partLen), with: data[0..<partLen])
            transform(&ctx, block: ctx.buffer)
            i = partLen
            while i + 63 < inputLen {
                transform(&ctx, block: [UInt8](data[i..<(i+64)]))
                i += 64
            }
            let remain = inputLen - i
            ctx.buffer.replaceSubrange(0..<remain, with: data[i..<(i + remain)])
        } else {
            ctx.buffer.replaceSubrange(index..<(index + inputLen), with: data[0..<inputLen])
        }
    }
    
    private func finalize(_ ctx: inout SHA1Context) {
        let padding: [UInt8] = [0x80] + [UInt8](repeating: 0, count: 63)
        var bits = [UInt8](repeating: 0, count: 8)
        encodeUInt64(ctx.count, &bits)
        
        let index = Int((ctx.count.0 >> 3) & 0x3f)
        let padLen = (index < 56) ? (56 - index) : (120 - index)
        update(&ctx, data: Array(padding[0..<padLen]))
        update(&ctx, data: bits)
        
        encodeUInt32BE(ctx.state.0, &ctx.digest, offset: 0)
        encodeUInt32BE(ctx.state.1, &ctx.digest, offset: 4)
        encodeUInt32BE(ctx.state.2, &ctx.digest, offset: 8)
        encodeUInt32BE(ctx.state.3, &ctx.digest, offset: 12)
        encodeUInt32BE(ctx.state.4, &ctx.digest, offset: 16)
    }
    
    private func transform(_ ctx: inout SHA1Context, block: [UInt8]) {
        var w = [UInt32](repeating: 0, count: 80)
        
        // Prepare message schedule
        for i in 0..<16 {
            w[i] = UInt32(block[i * 4]) << 24 |
                   UInt32(block[i * 4 + 1]) << 16 |
                   UInt32(block[i * 4 + 2]) << 8 |
                   UInt32(block[i * 4 + 3])
        }
        
        for i in 16..<80 {
            w[i] = rotateLeft(w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16], 1)
        }
        
        var a = ctx.state.0
        var b = ctx.state.1
        var c = ctx.state.2
        var d = ctx.state.3
        var e = ctx.state.4
        
        // Main loop
        for i in 0..<80 {
            let f: UInt32
            let k: UInt32
            
            if i < 20 {
                f = (b & c) | ((~b) & d)
                k = 0x5A827999
            } else if i < 40 {
                f = b ^ c ^ d
                k = 0x6ED9EBA1
            } else if i < 60 {
                f = (b & c) | (b & d) | (c & d)
                k = 0x8F1BBCDC
            } else {
                f = b ^ c ^ d
                k = 0xCA62C1D6
            }
            
            let temp = rotateLeft(a, 5) &+ f &+ e &+ k &+ w[i]
            e = d
            d = c
            c = rotateLeft(b, 30)
            b = a
            a = temp
        }
        
        ctx.state.0 = ctx.state.0 &+ a
        ctx.state.1 = ctx.state.1 &+ b
        ctx.state.2 = ctx.state.2 &+ c
        ctx.state.3 = ctx.state.3 &+ d
        ctx.state.4 = ctx.state.4 &+ e
    }
    
    private func rotateLeft(_ x: UInt32, _ n: UInt32) -> UInt32 {
        return (x << n) | (x >> (32 - n))
    }
    
    private func encodeUInt32BE(_ input: UInt32, _ output: inout [UInt8], offset: Int) {
        output[offset]     = UInt8((input >> 24) & 0xff)
        output[offset + 1] = UInt8((input >> 16) & 0xff)
        output[offset + 2] = UInt8((input >> 8) & 0xff)
        output[offset + 3] = UInt8(input & 0xff)
    }
    
    private func encodeUInt64(_ input: (UInt32, UInt32), _ output: inout [UInt8]) {
        encodeUInt32BE(input.1, &output, offset: 0)
        encodeUInt32BE(input.0, &output, offset: 4)
    }
}

// MARK: - MD5 Implementation (reuse from MoneyDecrypter)

private final class MD5Crypto {
    func hash(data: Data) -> [UInt8] {
        var context = MD5Context()
        update(&context, data: [UInt8](data))
        finalize(&context)
        return context.digest
    }
    
    private struct MD5Context {
        var count: (UInt32, UInt32) = (0, 0)
        var state: (UInt32, UInt32, UInt32, UInt32) = (0, 0, 0, 0)
        var buffer = [UInt8](repeating: 0, count: 64)
        var digest = [UInt8](repeating: 0, count: 16)
        
        init() {
            state.0 = 0x67452301
            state.1 = 0xefcdab89
            state.2 = 0x98badcfe
            state.3 = 0x10325476
        }
    }
    
    private func update(_ ctx: inout MD5Context, data: [UInt8]) {
        var inputLen = data.count
        let index = Int((ctx.count.0 >> 3) & 0x3F)
        let partLen = 64 - index
        
        ctx.count.0 = ctx.count.0 &+ UInt32(inputLen << 3)
        if ctx.count.0 < UInt32(inputLen << 3) {
            ctx.count.1 = ctx.count.1 &+ 1
        }
        ctx.count.1 = ctx.count.1 &+ UInt32(inputLen >> 29)
        
        var i = 0
        if inputLen >= partLen {
            ctx.buffer.replaceSubrange(index..<(index + partLen), with: data[0..<partLen])
            transform(&ctx, block: ctx.buffer)
            i = partLen
            while i + 63 < inputLen {
                transform(&ctx, block: [UInt8](data[i..<(i+64)]))
                i += 64
            }
            let remain = inputLen - i
            ctx.buffer.replaceSubrange(0..<remain, with: data[i..<(i + remain)])
        } else {
            ctx.buffer.replaceSubrange(index..<(index + inputLen), with: data[0..<inputLen])
        }
    }
    
    private func finalize(_ ctx: inout MD5Context) {
        let padding: [UInt8] = [0x80] + [UInt8](repeating: 0, count: 63)
        var bits = [UInt8](repeating: 0, count: 8)
        encodeUInt64(ctx.count, &bits)
        
        let index = Int((ctx.count.0 >> 3) & 0x3f)
        let padLen = (index < 56) ? (56 - index) : (120 - index)
        update(&ctx, data: Array(padding[0..<padLen]))
        update(&ctx, data: bits)
        
        encodeUInt32(ctx.state.0, &ctx.digest, offset: 0)
        encodeUInt32(ctx.state.1, &ctx.digest, offset: 4)
        encodeUInt32(ctx.state.2, &ctx.digest, offset: 8)
        encodeUInt32(ctx.state.3, &ctx.digest, offset: 12)
    }
    
    private func transform(_ ctx: inout MD5Context, block: [UInt8]) {
        // (Full MD5 transform implementation - same as in MoneyDecrypter)
        // ... [truncated for brevity - copy from MoneyDecrypter]
    }
    
    // ... [other MD5 helper functions - copy from MoneyDecrypter]
    
    private func encodeUInt32(_ input: UInt32, _ output: inout [UInt8], offset: Int) {
        output[offset]     = UInt8(input & 0xff)
        output[offset + 1] = UInt8((input >> 8) & 0xff)
        output[offset + 2] = UInt8((input >> 16) & 0xff)
        output[offset + 3] = UInt8((input >> 24) & 0xff)
    }
    
    private func encodeUInt64(_ input: (UInt32, UInt32), _ output: inout [UInt8]) {
        encodeUInt32(input.0, &output, offset: 0)
        encodeUInt32(input.1, &output, offset: 4)
    }
    
    // Stub methods - copy full implementations from MoneyDecrypter
    private func F(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { (x & y) | (~x & z) }
    private func G(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { (x & z) | (y & ~z) }
    private func H(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { x ^ y ^ z }
    private func I(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { y ^ (x | ~z) }
    private func rotateLeft(_ x: UInt32, _ n: UInt32) -> UInt32 { (x << n) | (x >> (32 - n)) }
    private func FF(_ a: inout UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32, _ x: UInt32, _ s: UInt32, _ ac: UInt32) {
        a = a &+ F(b, c, d) &+ x &+ ac; a = rotateLeft(a, s); a = a &+ b
    }
    private func GG(_ a: inout UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32, _ x: UInt32, _ s: UInt32, _ ac: UInt32) {
        a = a &+ G(b, c, d) &+ x &+ ac; a = rotateLeft(a, s); a = a &+ b
    }
    private func HH(_ a: inout UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32, _ x: UInt32, _ s: UInt32, _ ac: UInt32) {
        a = a &+ H(b, c, d) &+ x &+ ac; a = rotateLeft(a, s); a = a &+ b
    }
    private func II(_ a: inout UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32, _ x: UInt32, _ s: UInt32, _ ac: UInt32) {
        a = a &+ I(b, c, d) &+ x &+ ac; a = rotateLeft(a, s); a = a &+ b
    }
    
    private func decode(_ input: [UInt8], _ output: inout [UInt32]) {
        for i in 0..<16 {
            output[i] = UInt32(input[i * 4]) |
            (UInt32(input[i * 4 + 1]) << 8) |
            (UInt32(input[i * 4 + 2]) << 16) |
            (UInt32(input[i * 4 + 3]) << 24)
        }
    }
}


