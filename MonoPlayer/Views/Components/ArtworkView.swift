import ImageIO
import SwiftUI
import UIKit

/// Цветная обложка трека (никогда не обесцвечивается) с плейсхолдером и плавным появлением.
struct ArtworkView: View {
    let fileName: String?
    let size: CGFloat
    var cornerRadius: CGFloat = Theme.Radius.rowArtwork
    var isLoading = false

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Theme.Colors.bgSecondary
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4, weight: .regular))
                    .foregroundStyle(Theme.Colors.labelTertiary)
            }
        }
        .frame(width: size, height: size)
        .shimmer(active: image == nil && isLoading)
        .clipShape(shape)
        .animation(.easeInOut(duration: 0.3), value: image != nil)
        .task(id: fileName) {
            guard let fileName else {
                image = nil
                return
            }
            image = await ArtworkLoader.image(named: fileName, maxPixelSize: size * displayScale)
        }
        .accessibilityHidden(true)
    }
}

/// Загрузка и даунсэмплинг обложек вне главного потока с кэшем в памяти.
enum ArtworkLoader {
    private final class Cache: @unchecked Sendable {
        let storage = NSCache<NSString, UIImage>()
        init() { storage.countLimit = 300 }
    }

    private static let cache = Cache()

    static func image(named fileName: String, maxPixelSize: CGFloat) async -> UIImage? {
        await image(at: Storage.artworkURL(fileName), cacheKey: fileName, maxPixelSize: maxPixelSize)
    }

    static func image(at url: URL, cacheKey: String? = nil, maxPixelSize: CGFloat) async -> UIImage? {
        // Корзины размеров, чтобы не плодить копии в кэше
        let bucket = maxPixelSize <= 200 ? 200 : (maxPixelSize <= 700 ? 700 : 1400)
        let key = "\(cacheKey ?? url.path())#\(bucket)" as NSString
        if let cached = cache.storage.object(forKey: key) { return cached }

        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: bucket,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: cgImage)
        }.value

        if let image { cache.storage.setObject(image, forKey: key) }
        return image
    }

    /// Своя обложка: обрезка по центру до квадрата, не больше `maxPixelSize`, в JPEG (HEIC/PNG тоже читаются).
    static func squareJPEG(from data: Data, maxPixelSize: Int = 1400) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let side = min(image.width, image.height)
        let crop = CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side)
        return UIImage(cgImage: image.cropping(to: crop) ?? image).jpegData(compressionQuality: 0.9)
    }
}
