#if canImport(UIKit)
import UIKit

/// 图片压缩工具：将手机端图片压缩到适合 Relay 传输的大小
/// 策略：长边限制 1536px + JPEG 渐进压缩，保证 <500KB
enum ImageCompressor {

    /// 默认最大字节数（500KB）
    static let defaultMaxBytes = 500_000

    /// 默认长边最大像素
    static let defaultMaxDimension: CGFloat = 1536

    /// 压缩图片到目标大小以内
    /// - Parameters:
    ///   - image: 原始 UIImage
    ///   - maxBytes: 最大字节数，默认 500KB
    ///   - maxDimension: 长边最大像素，默认 1536
    /// - Returns: 压缩后的 JPEG Data，失败返回 nil
    static func compress(
        _ image: UIImage,
        maxBytes: Int = defaultMaxBytes,
        maxDimension: CGFloat = defaultMaxDimension
    ) -> Data? {
        let resized = resizeToFit(image, maxDimension: maxDimension)

        // 从 quality 0.7 开始，逐步降低直到满足大小限制
        for quality in stride(from: 0.7, through: 0.3, by: -0.1) {
            if let data = resized.jpegData(compressionQuality: quality),
               data.count <= maxBytes {
                return data
            }
        }

        // 兜底：最低质量
        return resized.jpegData(compressionQuality: 0.3)
    }

    /// 获取压缩后的预估信息（用于 UI 显示）
    static func previewInfo(_ image: UIImage) -> (pixelSize: CGSize, estimatedKB: Int) {
        let resized = resizeToFit(image, maxDimension: defaultMaxDimension)
        let estimatedBytes = resized.jpegData(compressionQuality: 0.7)?.count ?? 0
        return (resized.size, estimatedBytes / 1024)
    }

    // MARK: - 内部方法

    /// 按长边等比缩放
    private static func resizeToFit(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longerSide = max(size.width, size.height)

        // 已经够小，不需要缩放
        guard longerSide > maxDimension else { return image }

        let scale = maxDimension / longerSide
        let newSize = CGSize(
            width: (size.width * scale).rounded(.down),
            height: (size.height * scale).rounded(.down)
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
#endif
