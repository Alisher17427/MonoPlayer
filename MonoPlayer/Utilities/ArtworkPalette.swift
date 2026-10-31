import ImageIO
import SwiftUI

/// Извлекает 2–3 доминантных цвета обложки (уменьшение до 32×32 + группировка по корзинам).
/// Считается один раз при сохранении обложки и хранится в `Track.paletteHex`.
enum ArtworkPalette {
    static func extractHex(from data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 32,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        struct Bucket { var count = 0; var r = 0, g = 0, b = 0 }
        var buckets: [Int: Bucket] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
            let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            buckets[key, default: Bucket()].count += 1
            buckets[key]!.r += r
            buckets[key]!.g += g
            buckets[key]!.b += b
        }

        let candidates: [(rgb: RGB, score: Double)] = buckets.values.map { bucket in
            let rgb = RGB(r: Double(bucket.r) / Double(bucket.count) / 255,
                          g: Double(bucket.g) / Double(bucket.count) / 255,
                          b: Double(bucket.b) / Double(bucket.count) / 255)
            return (rgb, Double(bucket.count) * (0.35 + rgb.saturation))
        }
        .sorted { $0.score > $1.score }

        var chosen: [RGB] = []
        for candidate in candidates where chosen.allSatisfy({ $0.distance(to: candidate.rgb) > 0.18 }) {
            chosen.append(candidate.rgb)
            if chosen.count == 3 { break }
        }
        if chosen.isEmpty, let first = candidates.first { chosen = [first.rgb] }
        return chosen.isEmpty ? nil : chosen.map(\.hex).joined(separator: ",")
    }

    static func colors(fromHex hex: String?) -> [Color] {
        guard let hex else { return [] }
        return hex.split(separator: ",").compactMap { Color(hex: String($0)) }
    }

    /// Средняя относительная яркость палитры (0…1) — для решения, нужен ли затемняющий слой.
    static func luminance(ofHex hex: String?) -> Double {
        guard let hex else { return 0 }
        let values = hex.split(separator: ",").compactMap { RGB(hex: String($0))?.luminance }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct RGB: Sendable {
    var r: Double, g: Double, b: Double

    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    init?(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard clean.count == 6, let value = Int(clean, radix: 16) else { return nil }
        r = Double((value >> 16) & 0xFF) / 255
        g = Double((value >> 8) & 0xFF) / 255
        b = Double(value & 0xFF) / 255
    }

    var hex: String {
        String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    var saturation: Double {
        let maxV = max(r, g, b), minV = min(r, g, b)
        return maxV == 0 ? 0 : (maxV - minV) / maxV
    }

    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    func distance(to other: RGB) -> Double {
        let dr = r - other.r, dg = g - other.g, db = b - other.b
        return (dr * dr + dg * dg + db * db).squareRoot()
    }
}

extension Color {
    init?(hex: String) {
        guard let rgb = RGB(hex: hex) else { return nil }
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}
