#if os(Windows)
import Foundation

/// Minimal, dependency-free PNG encoder for 32bpp BGRA top-down pixel buffers
/// (the layout GetDIBits hands us). Uses stored (uncompressed) DEFLATE blocks so
/// we need neither WIC/COM nor a zlib dependency. Files are larger than a
/// compressed PNG but are valid everywhere (Windows.Media.Ocr, Vision, browsers).
enum WinPng {
    /// `bgra` is width*height*4 bytes, top-down, byte order B,G,R,A.
    static func encode(bgra: [UInt8], width: Int, height: Int) -> Data {
        // Build filtered raw stream: each row prefixed with filter byte 0 (None),
        // pixels converted BGRA -> RGBA for PNG color type 6.
        let rowBytes = width * 4
        var raw = [UInt8]()
        raw.reserveCapacity((rowBytes + 1) * height)
        for y in 0..<height {
            raw.append(0) // filter: None
            let base = y * rowBytes
            var x = 0
            while x < rowBytes {
                let b = bgra[base + x]
                let g = bgra[base + x + 1]
                let r = bgra[base + x + 2]
                let a = bgra[base + x + 3]
                raw.append(r); raw.append(g); raw.append(b); raw.append(a)
                x += 4
            }
        }

        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        // IHDR
        var ihdr = [UInt8]()
        ihdr.append(contentsOf: be32(UInt32(width)))
        ihdr.append(contentsOf: be32(UInt32(height)))
        ihdr.append(8)  // bit depth
        ihdr.append(6)  // color type: RGBA
        ihdr.append(0)  // compression
        ihdr.append(0)  // filter
        ihdr.append(0)  // interlace
        png.append(chunk("IHDR", ihdr))
        // IDAT: zlib(stored deflate(raw))
        png.append(chunk("IDAT", zlibStored(raw)))
        // IEND
        png.append(chunk("IEND", []))
        return png
    }

    // zlib stream: 2-byte header, stored DEFLATE blocks, adler32 trailer.
    private static func zlibStored(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x78, 0x01] // CMF/FLG (32K window, no dict, fastest)
        let maxBlock = 0xFFFF
        var i = 0
        if data.isEmpty {
            out.append(contentsOf: [0x01, 0x00, 0x00, 0xFF, 0xFF])
        }
        while i < data.count {
            let len = min(maxBlock, data.count - i)
            let final: UInt8 = (i + len >= data.count) ? 1 : 0
            out.append(final) // BFINAL + BTYPE=00
            out.append(UInt8(len & 0xFF))
            out.append(UInt8((len >> 8) & 0xFF))
            let nlen = ~UInt16(len) & 0xFFFF
            out.append(UInt8(nlen & 0xFF))
            out.append(UInt8((nlen >> 8) & 0xFF))
            out.append(contentsOf: data[i..<(i + len)])
            i += len
        }
        out.append(contentsOf: be32(adler32(data)))
        return out
    }

    private static func chunk(_ type: String, _ payload: [UInt8]) -> Data {
        var d = Data()
        d.append(contentsOf: be32(UInt32(payload.count)))
        let typeBytes = Array(type.utf8)
        d.append(contentsOf: typeBytes)
        d.append(contentsOf: payload)
        d.append(contentsOf: be32(crc32(typeBytes + payload)))
        return d
    }

    private static func be32(_ v: UInt32) -> [UInt8] {
        [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    private static func adler32(_ data: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        let mod: UInt32 = 65521
        for byte in data {
            a = (a + UInt32(byte)) % mod
            b = (b + a) % mod
        }
        return (b << 16) | a
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1
            }
            return c
        }
    }()

    private static func crc32(_ data: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for byte in data {
            c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8)
        }
        return c ^ 0xFFFFFFFF
    }
}
#endif
