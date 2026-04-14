import PhotosUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 聊天输入栏视图（支持文字 + 图片混合输入）
struct ChatInputBar: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var inputText: String
    @FocusState.Binding var isInputFocused: Bool
    let hasPastedImage: Bool
    let onSend: () -> Void
    let onDismissPasteImage: () -> Void
    let onAtTap: () -> Void
    let onSlashTap: () -> Void
    let onCtrlC: () -> Void
    let onEsc: () -> Void
    let onCompact: () -> Void
    let onStatus: () -> Void
    let onPlan: () -> Void
    let isInPlanMode: Bool

    /// 混合输入 ViewModel（由父视图注入）
    @ObservedObject var composeViewModel: ComposeInputViewModel

    /// 混合消息发送回调
    var onSendComposed: ((ComposedMessage) -> Void)?

    /// 图片选择器状态
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    /// 是否有已插入的图片（进入混合输入模式）
    private var hasImages: Bool {
        composeViewModel.blocks.contains(where: \.isImage)
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider().background(CMColors.separator)
            // 快捷按钮行
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("@", color: .blue) { onAtTap() }
                    chip("/", color: .orange) { onSlashTap() }
                    chip(isInPlanMode ? "退出Plan" : "Plan", color: isInPlanMode ? .red : .cyan) { onPlan() }
                    if isCompactLayout {
                        Menu {
                            Button("^C", action: onCtrlC)
                            Button("Esc", action: onEsc)
                            Button("/compact", action: onCompact)
                            Button("/status", action: onStatus)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 18))
                                .frame(width: 36, height: 36)
                        }
                        .accessibilityLabel(String(localized: "chat.input.more_actions", defaultValue: "更多聊天快捷操作"))
                    } else {
                        Rectangle().fill(CMColors.separator).frame(width: 1, height: 16)
                        chip("^C", color: .red) { onCtrlC() }
                        chip("Esc", color: .gray) { onEsc() }
                        chip("/compact", color: .purple) { onCompact() }
                        chip("/status", color: .green) { onStatus() }
                    }
                }.padding(.horizontal, 12).padding(.vertical, 6)
            }
            // 粘贴板图片提示
            if hasPastedImage, !hasImages {
                HStack(spacing: 6) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 11)).foregroundStyle(.blue)
                    Text(String(localized: "chat.clipboard_image", defaultValue: "粘贴板包含图片"))
                        .font(.system(size: 11)).foregroundStyle(CMColors.textTertiary)
                    Spacer()
                    Button {
                        onDismissPasteImage()
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 9)).foregroundStyle(CMColors.textTertiary)
                    }
                    .frame(width: 28, height: 28)
                    .accessibilityLabel(String(localized: "chat.clipboard.dismiss", defaultValue: "关闭粘贴板图片提示"))
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
                .background(Color.blue.opacity(0.06))
            }

            // 已插入图片的预览区
            if hasImages {
                imagePreviewArea
            }

            // 输入行
            HStack(spacing: 8) {
                // 图片按钮
                imageButtons

                // 文本输入框
                ZStack(alignment: .bottomTrailing) {
                    TextField(
                        "",
                        text: $inputText,
                        prompt: Text(String(localized: "chat.input.placeholder", defaultValue: "消息..."))
                            .foregroundStyle(CMColors.textSecondary),
                        axis: .vertical
                    )
                    .font(.system(size: 15)).foregroundStyle(CMColors.textPrimary)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .lineLimit(1...8).focused($isInputFocused)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(CMColors.tertiarySystemFill)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .onSubmit { handleSend() }
                    // 字符计数
                    if inputText.count > 500 {
                        Text("\(inputText.count)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(inputText.count > 10000 ? .red.opacity(0.6) : CMColors.textTertiary)
                            .padding(.trailing, 10).padding(.bottom, 6)
                    }
                }

                // 发送按钮
                Button(action: handleSend) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                        .foregroundStyle(canSend ? .purple : .gray.opacity(0.3))
                }
                .frame(width: 44, height: 44)
                .disabled(!canSend)
                .accessibilityLabel(String(localized: "chat.send", defaultValue: "发送消息"))
                .accessibilityHint(String(localized: "chat.send.hint", defaultValue: "发送当前输入内容"))
            }.padding(.horizontal, 12).padding(.bottom, 8)
        }
        .background(CMColors.inputBarBackground)
    }

    // MARK: - 图片按钮

    private var imageButtons: some View {
        HStack(spacing: 4) {
            // 相册选择
            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: 5,
                matching: .images
            ) {
                Image(systemName: "photo")
                    .font(.system(size: 16))
                    .foregroundStyle(CMColors.textSecondary)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(String(localized: "chat.attach.photo", defaultValue: "添加图片"))
            .onChange(of: selectedPhotoItems) { _, items in
                guard !items.isEmpty else { return }
                handlePhotoSelection(items)
            }

        }
    }

    // MARK: - 图片预览区

    private var imagePreviewArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(composeViewModel.blocks) { block in
                    if case .image(let id, let data, let thumbnail) = block {
                        imagePreviewChip(id: id, data: data, thumbnail: thumbnail)
                    }
                }
                if composeViewModel.isCompressing {
                    ProgressView()
                        .frame(width: 56, height: 56)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(CMColors.tertiarySystemFill.opacity(0.5))
    }

    private func imagePreviewChip(id: UUID, data: Data, thumbnail: UIImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                composeViewModel.removeImage(blockID: id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .background(Circle().fill(.black.opacity(0.5)))
            }
            .frame(width: 28, height: 28)
            .accessibilityLabel(String(localized: "chat.attach.remove_image", defaultValue: "移除图片"))
            .offset(x: 4, y: -4)
        }
        .overlay(alignment: .bottom) {
            Text("\(data.count / 1024)KB")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(.black.opacity(0.5))
                .clipShape(Capsule())
                .offset(y: -2)
        }
    }

    // MARK: - 发送逻辑

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasImages
    }

    private func handleSend() {
        if hasImages {
            // 混合模式：同步当前文本到 composeViewModel 的活跃文本块
            flushInputToCompose()
            onSendComposed?(composeViewModel.buildMessage(targetSurfaceID: ""))
            composeViewModel.reset()
            inputText = ""
        } else {
            // 纯文字模式：走原有逻辑
            onSend()
        }
    }

    /// 将 inputText 同步到 composeViewModel 的当前活跃文本块，然后清空输入框
    private func flushInputToCompose() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let activeID = composeViewModel.activeTextBlockID else { return }
        let existing = composeViewModel.blocks.first(where: { $0.id == activeID })?.textContent ?? ""
        let combined = existing.isEmpty ? text : existing + "\n" + text
        composeViewModel.updateText(blockID: activeID, content: combined)
        inputText = ""
    }

    // MARK: - 图片选择处理

    private func handlePhotoSelection(_ items: [PhotosPickerItem]) {
        // 选图前先将已输入的文字同步到活跃文本块，保证文字在图片之前
        flushInputToCompose()
        for item in items {
            item.loadTransferable(type: Data.self) { result in
                guard case .success(let data) = result, let data,
                      let image = UIImage(data: data) else { return }
                Task { @MainActor in
                    composeViewModel.insertImage(image)
                }
            }
        }
        selectedPhotoItems = []
    }

    // MARK: - 工具方法

    private func chip(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(minWidth: 36, minHeight: 36)
                .padding(.horizontal, 8)
                .background(color.opacity(0.1)).foregroundStyle(color.opacity(0.7)).clipShape(Capsule())
        }
    }

    private var isCompactLayout: Bool {
        horizontalSizeClass == .compact
    }
}
