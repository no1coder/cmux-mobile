import PhotosUI
import SwiftUI

/// 块状输入编辑器的 ViewModel
/// 管理 TextBlock + ImageBlock 交替排列的内容块数组
@MainActor
final class ComposeInputViewModel: ObservableObject {

    /// 所有内容块（初始状态：一个空文本块）
    @Published var blocks: [ContentBlock] = [.text(id: UUID(), content: "")]

    /// 当前活跃（聚焦）的文本块 ID
    @Published var activeTextBlockID: UUID?

    /// 是否正在压缩图片
    @Published var isCompressing = false

    init() {
        activeTextBlockID = blocks.first?.id
    }

    // MARK: - 文本编辑

    /// 更新指定文本块的内容（不可变模式）
    func updateText(blockID: UUID, content: String) {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }),
              case .text = blocks[index] else { return }
        var updated = blocks
        updated[index] = .text(id: blockID, content: content)
        blocks = updated
    }

    // MARK: - 图片操作

    /// 在当前活跃文本块之后插入图片 + 新文本块
    func insertImage(_ image: UIImage) {
        // 图片数量上限为 5
        guard blocks.filter(\.isImage).count < 5 else { return }

        isCompressing = true

        Task {
            // 压缩在后台执行，避免阻塞主线程
            let compressedData = await Task.detached(priority: .userInitiated) {
                ImageCompressor.compress(image)
            }.value

            guard let compressedData else {
                isCompressing = false
                return
            }

            // 缩略图生成也在后台
            let thumbnail = await Task.detached(priority: .utility) {
                let size = CGSize(width: 120, height: 120)
                let renderer = UIGraphicsImageRenderer(size: size)
                return renderer.image { _ in
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
            }.value

            // 回到主线程后才读写 blocks（actor 隔离保证串行，避免并发竞争）
            let imageBlock = ContentBlock.image(id: UUID(), data: compressedData, thumbnail: thumbnail)
            let newTextBlock = ContentBlock.text(id: UUID(), content: "")
            let insertIndex = findInsertIndex()

            var updated = blocks
            updated.insert(imageBlock, at: insertIndex)
            updated.insert(newTextBlock, at: insertIndex + 1)
            blocks = updated

            // 聚焦到新文本块
            activeTextBlockID = newTextBlock.id
            isCompressing = false
        }
    }

    /// 处理 PHPicker 选择结果
    func handlePickerResults(_ results: [PHPickerResult]) {
        for result in results {
            let provider = result.itemProvider
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                    guard let image = object as? UIImage else { return }
                    Task { @MainActor in
                        self?.insertImage(image)
                    }
                }
            }
        }
    }

    /// 删除图片块，合并前后文本块
    func removeImage(blockID: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == blockID }),
              case .image = blocks[index] else { return }

        var updated = blocks

        // 检查前后是否都是文本块，如果是则合并
        let hasPrevText = index > 0 && blocks[index - 1].isText
        let hasNextText = index + 1 < blocks.count && blocks[index + 1].isText

        if hasPrevText, hasNextText {
            // 合并前后文本块
            let prevIndex = index - 1
            let nextIndex = index + 1
            let prevContent = blocks[prevIndex].textContent ?? ""
            let nextContent = blocks[nextIndex].textContent ?? ""
            let mergedID = blocks[prevIndex].id
            let merged = ContentBlock.text(id: mergedID, content: prevContent + nextContent)

            // 移除后文本块、图片块，替换前文本块
            updated.remove(at: nextIndex)
            updated.remove(at: index)
            updated[prevIndex] = merged
            activeTextBlockID = mergedID
        } else {
            // 仅移除图片块
            updated.remove(at: index)
        }

        // 确保至少有一个文本块
        if updated.isEmpty {
            let emptyText = ContentBlock.text(id: UUID(), content: "")
            updated.append(emptyText)
            activeTextBlockID = emptyText.id
        }

        blocks = updated
    }

    // MARK: - 构建消息

    /// 构建待发送的混合消息
    func buildMessage(targetSurfaceID: String) -> ComposedMessage {
        ComposedMessage(blocks: blocks, targetSurfaceID: targetSurfaceID)
    }

    /// 重置为初始状态
    func reset() {
        let emptyText = ContentBlock.text(id: UUID(), content: "")
        blocks = [emptyText]
        activeTextBlockID = emptyText.id
    }

    /// 是否有可发送的内容
    var canSend: Bool {
        blocks.contains { block in
            switch block {
            case .text(_, let content):
                return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .image:
                return true
            }
        }
    }

    // MARK: - 内部

    /// 找到图片插入位置（当前活跃文本块之后）
    private func findInsertIndex() -> Int {
        if let activeID = activeTextBlockID,
           let index = blocks.firstIndex(where: { $0.id == activeID }) {
            return index + 1
        }
        return blocks.count
    }
}
