import PhotosUI
import SwiftUI

/// 块状输入编辑器：文字和图片交替排列
/// 用于 Claude 聊天界面，支持发送混合内容（文字 + 图片）
struct ComposeInputView: View {
    @ObservedObject var viewModel: ComposeInputViewModel
    let onSend: (ComposedMessage) -> Void
    let surfaceID: String

    /// 快捷按钮回调
    var onQuickAction: ((String) -> Void)?

    @State private var selectedItems: [PhotosPickerItem] = []

    var body: some View {
        VStack(spacing: 0) {
            // 快捷按钮行
            quickActionBar

            Divider()

            // 内容块列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.blocks) { block in
                            blockView(for: block)
                                .id(block.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 200)
                .onChange(of: viewModel.activeTextBlockID) { _, newID in
                    if let id = newID {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }

            Divider()

            // 底部工具栏：图片选择 + 发送
            bottomToolbar
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 快捷按钮

    private var quickActionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickButton("@", action: "@")
                quickButton("/", action: "/")
                quickButton("^C", action: "ctrl-c")
                quickButton("Esc", action: "escape")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func quickButton(_ label: String, action: String) -> some View {
        Button {
            onQuickAction?(action)
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(uiColor: .tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 内容块视图

    @ViewBuilder
    private func blockView(for block: ContentBlock) -> some View {
        switch block {
        case .text(let id, let content):
            textBlockView(id: id, content: content)

        case .image(let id, let data, let thumbnail):
            imageBlockView(id: id, data: data, thumbnail: thumbnail)
        }
    }

    private func textBlockView(id: UUID, content: String) -> some View {
        ComposeTextBlockView(
            text: Binding(
                get: { content },
                set: { viewModel.updateText(blockID: id, content: $0) }
            ),
            isFocused: viewModel.activeTextBlockID == id,
            onTap: { viewModel.activeTextBlockID = id }
        )
    }

    private func imageBlockView(id: UUID, data: Data, thumbnail: UIImage) -> some View {
        HStack(spacing: 8) {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "compose.image.label", defaultValue: "图片"))
                    .font(.system(size: 13, weight: .medium))
                Text("\(data.count / 1024) KB")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.removeImage(blockID: id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 底部工具栏

    private var bottomToolbar: some View {
        HStack(spacing: 12) {
            // 相册选择
            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: 5,
                matching: .images
            ) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 18))
            }
            .disabled(viewModel.isCompressing)
            .onChange(of: selectedItems) { _, newItems in
                handlePhotoSelection(newItems)
            }

            if viewModel.isCompressing {
                ProgressView()
                    .scaleEffect(0.8)
            }

            Spacer()

            // 发送按钮
            Button {
                let message = viewModel.buildMessage(targetSurfaceID: surfaceID)
                guard !message.isEmpty else { return }
                onSend(message)
                viewModel.reset()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(viewModel.canSend ? .blue : .gray)
            }
            .disabled(!viewModel.canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func handlePhotoSelection(_ items: [PhotosPickerItem]) {
        for item in items {
            item.loadTransferable(type: Data.self) { result in
                guard case .success(let data) = result, let data,
                      let image = UIImage(data: data) else { return }
                Task { @MainActor in
                    viewModel.insertImage(image)
                }
            }
        }
        selectedItems = []
    }
}

// MARK: - 文本块子视图

/// 单个文本块的编辑视图
struct ComposeTextBlockView: View {
    @Binding var text: String
    let isFocused: Bool
    let onTap: () -> Void

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        TextField(
            String(localized: "compose.text.placeholder", defaultValue: "输入消息..."),
            text: $text,
            axis: .vertical
        )
        .font(.system(size: 15))
        .lineLimit(1...8)
        .focused($isFieldFocused)
        .onTapGesture { onTap() }
        .onChange(of: isFocused) { _, shouldFocus in
            if shouldFocus { isFieldFocused = true }
        }
        .onAppear {
            if isFocused { isFieldFocused = true }
        }
    }
}

