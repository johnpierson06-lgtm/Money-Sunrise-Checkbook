import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// Experimental Jet 4 page-level decrypter. This is a first pass and may require
// adjustments to match Jackcess' CryptCodecProvider behavior precisely.
struct Jet4Decrypter {
    private let clearHeaderBytesPerPage = 24 // bytes left unencrypted at start of each page (typical for Jet 4)

    func decryptDatabase(raw: Data, password: String) throws -> Data {
        let pageSize = guessPageSize(fileSize: raw.count)
        guard pageSize > 0, raw.count % pageSize == 0 else {
            throw MoneyDecrypterError.unsupportedFormat("Unable to determine Jet page size")
        }

        let pageCount = raw.count / pageSize
        let pwData = utf16LE(password)
        var output = Data(capacity: raw.count)

        for pageIndex in 0..<pageCount {
            let pageOffset = pageIndex * pageSize
            let page = raw.subdata(in: pageOffset..<(pageOffset + pageSize))

            // Copy clear header bytes (if any)
            let headerLen = min(clearHeaderBytesPerPage, page.count)
            var decryptedPage = Data()
            decryptedPage.append(page.prefix(headerLen))

            // Decrypt the remainder of the page using RC4 with a per-page key
            if page.count > headerLen {
                let cipherText = page.subdata(in: headerLen..<page.count)
                let key = derivePageKey(passwordData: pwData, pageIndex: pageIndex)
                let rc4 = RC4(key: key)
                let plain = rc4.process(cipherText)
                decryptedPage.append(plain)
            }

            output.append(decryptedPage)
        }

        return output
    }

    // MARK: - Helpers

    private func guessPageSize(fileSize: Int) -> Int {
        // Prefer 4096 for Jet 4; fall back to 2048, then 1024 if divisible
        if fileSize % 4096 == 0 { return 4096 }
        if fileSize % 2048 == 0 { return 2048 }
        if fileSize % 1024 == 0 { return 1024 }
        return 0
    }

    private func derivePageKey(passwordData: Data, pageIndex: Int) -> Data {
        // Tentative per-page key derivation: MD5(passwordUTF16LE + pageIndexLE)
        // NOTE: This may require additional salt/concatenation to match Jet 4 exactly.
        var le = withUnsafeBytes(of: UInt32(pageIndex).littleEndian, Array.init)
        let pageIndexData = Data(le)
        let combined = passwordData + pageIndexData
        return md5(combined)
    }

    private func utf16LE(_ s: String) -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(s.utf16.count * 2)
        for u16 in s.utf16 {
            bytes.append(UInt8(u16 & 0xFF))
            bytes.append(UInt8((u16 >> 8) & 0xFF))
        }
        return Data(bytes)
    }

    private func md5(_ data: Data) -> Data {
        #if canImport(CryptoKit)
        if #available(iOS 13, macOS 10.15, *) {
            let digest = Insecure.MD5.hash(data: data)
            return Data(digest)
        } else {
            return MD5Crypto().hash(data: data)
        }
        #else
        return MD5Crypto().hash(data: data)
        #endif
    }
}

// Minimal internal MD5 fallback (duplicated to keep this file self-contained)
private final class MD5Crypto {
    func hash(data: Data) -> Data {
        var context = MD5Context()
        update(&context, data: [UInt8](data))
        finalize(&context)
        return Data(context.digest)
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
        var a = ctx.state.0
        var b = ctx.state.1
        var c = ctx.state.2
        var d = ctx.state.3

        var x = [UInt32](repeating: 0, count: 16)
        decode(block, &x)

        // Round 1
        FF(&a, b, c, d, x[ 0], 7 , 0xd76aa478)
        FF(&d, a, b, c, x[ 1], 12, 0xe8c7b756)
        FF(&c, d, a, b, x[ 2], 17, 0x242070db)
        FF(&b, c, d, a, x[ 3], 22, 0xc1bdceee)
        FF(&a, b, c, d, x[ 4], 7 , 0xf57c0faf)
        FF(&d, a, b, c, x[ 5], 12, 0x4787c62a)
        FF(&c, d, a, b, x[ 6], 17, 0xa8304613)
        FF(&b, c, d, a, x[ 7], 22, 0xfd469501)
        FF(&a, b, c, d, x[ 8], 7 , 0x698098d8)
        FF(&d, a, b, c, x[ 9], 12, 0x8b44f7af)
        FF(&c, d, a, b, x[10], 17, 0xffff5bb1)
        FF(&b, c, d, a, x[11], 22, 0x895cd7be)
        FF(&a, b, c, d, x[12], 7 , 0x6b901122)
        FF(&d, a, b, c, x[13], 12, 0xfd987193)
        FF(&c, d, a, b, x[14], 17, 0xa679438e)
        FF(&b, c, d, a, x[15], 22, 0x49b40821)

        // Round 2
        GG(&a, b, c, d, x[ 1], 5 , 0xf61e2562)
        GG(&d, a, b, c, x[ 6], 9 , 0xc040b340)
        GG(&c, d, a, b, x[11], 14, 0x265e5a51)
        GG(&b, c, d, a, x[ 0], 20, 0xe9b6c7aa)
        GG(&a, b, c, d, x[ 5], 5 , 0xd62f105d)
        GG(&d, a, b, c, x[10], 9 , 0x02441453)
        GG(&c, d, a, b, x[15], 14, 0xd8a1e681)
        GG(&b, c, d, a, x[ 4], 20, 0xe7d3fbc8)
        GG(&a, b, c, d, x[ 9], 5 , 0x21e1cde6)
        GG(&d, a, b, c, x[14], 9 , 0xc33707d6)
        GG(&c, d, a, b, x[ 3], 14, 0xf4d50d87)
        GG(&b, c, d, a, x[ 8], 20, 0x455a14ed)
        GG(&a, b, c, d, x[13], 5 , 0xa9e3e905)
        GG(&d, a, b, c, x[ 2], 9 , 0xfcefa3f8)
        GG(&c, d, a, b, x[ 7], 14, 0x676f02d9)
        GG(&b, c, d, a, x[12], 20, 0x8d2a4c8a)

        // Round 3
        HH(&a, b, c, d, x[ 5], 4 , 0xfffa3942)
        HH(&d, a, b, c, x[ 8], 11, 0x8771f681)
        HH(&c, d, a, b, x[11], 16, 0x6d9d6122)
        HH(&b, c, d, a, x[14], 23, 0xfde5380c)
        HH(&a, b, c, d, x[ 1], 4 , 0xa4beea44)
        HH(&d, a, b, c, x[ 4], 11, 0x4bdecfa9)
        HH(&c, d, a, b, x[ 7], 16, 0xf6bb4b60)
        HH(&b, c, d, a, x[10], 23, 0xbebfbc70)
        HH(&a, b, c, d, x[13], 4 , 0x289b7ec6)
        HH(&d, a, b, c, x[ 0], 11, 0xeaa127fa)
        HH(&c, d, a, b, x[ 3], 16, 0xd4ef3085)
        HH(&b, c, d, a, x[ 6], 23, 0x04881d05)
        HH(&a, b, c, d, x[ 9], 4 , 0xd9d4d039)
        HH(&d, a, b, c, x[12], 11, 0xe6db99e5)
        HH(&c, d, a, b, x[15], 16, 0x1fa27cf8)
        HH(&b, c, d, a, x[ 2], 23, 0xc4ac5665)

        // Round 4
        II(&a, b, c, d, x[ 0], 6 , 0xf4292244)
        II(&d, a, b, c, x[ 7], 10, 0x432aff97)
        II(&c, d, a, b, x[14], 15, 0xab9423a7)
        II(&b, c, d, a, x[ 5], 21, 0xfc93a039)
        II(&a, b, c, d, x[12], 6 , 0x655b59c3)
        II(&d, a, b, c, x[ 3], 10, 0x8f0ccc92)
        II(&c, d, a, b, x[10], 15, 0xffeff47d)
        II(&b, c, d, a, x[ 1], 21, 0x85845dd1)
        II(&a, b, c, d, x[ 8], 6 , 0x6fa87e4f)
        II(&d, a, b, c, x[15], 10, 0xfe2ce6e0)
        II(&c, d, a, b, x[ 6], 15, 0xa3014314)
        II(&b, c, d, a, x[13], 21, 0x4e0811a1)
        II(&a, b, c, d, x[ 4], 6 , 0xf7537e82)
        II(&d, a, b, c, x[11], 10, 0xbd3af235)
        II(&c, d, a, b, x[ 2], 15, 0x2ad7d2bb)
        II(&b, c, d, a, x[ 9], 21, 0xeb86d391)

        ctx.state.0 = ctx.state.0 &+ a
        ctx.state.1 = ctx.state.1 &+ b
        ctx.state.2 = ctx.state.2 &+ c
        ctx.state.3 = ctx.state.3 &+ d
    }

    private func F(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { (x & y) | (~x & z) }
    private func G(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { (x & z) | (y & ~z) }
    private func H(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { x ^ y ^ z }
    private func I(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { y ^ (x | ~z) }

    private func rotateLeft(_ x: UInt32, _ n: UInt32) -> UInt32 { (x << n) | (x >> (32 - n)) }

    private func FF(_ a: inout UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32, _ x: UInt32, _ s: UInt32, _ ac: UInt32) {
        a = a &+ F(b, c, d) &+ x &+ ac
        a = rotateLeft(a, s)
        a = a &+ b
    }

    private func GG(_ a: inout UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32, _ x: UInt32, _ s: UInt32, _ ac: UInt32) {
        a = a &+ G(b, c, d) &+ x &+ ac
        a = rotateLeft(a, s)
        a = a &+ b
    }

    private func HH(_ a: inout UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32, _ x: UInt32, _ s: UInt32, _ ac: UInt32) {
        a = a &+ H(b, c, d) &+ x &+ ac
        a = rotateLeft(a, s)
        a = a &+ b
    }

    private func II(_ a: inout UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32, _ x: UInt32, _ s: UInt32, _ ac: UInt32) {
        a = a &+ I(b, c, d) &+ x &+ ac
        a = rotateLeft(a, s)
        a = a &+ b
    }

    private func decode(_ input: [UInt8], _ output: inout [UInt32]) {
        for i in 0..<16 {
            output[i] = UInt32(input[i * 4]) |
                        (UInt32(input[i * 4 + 1]) << 8) |
                        (UInt32(input[i * 4 + 2]) << 16) |
                        (UInt32(input[i * 4 + 3]) << 24)
        }
    }

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
}
