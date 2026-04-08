import SwiftUI

/// Token 用量显示组件 — 横条比例 + 文字标签
struct TokenUsageView: View {
    let inputTokens: Int
    let outputTokens: Int
    let cacheTokens: Int
    var compact: Bool = true

    private var totalTokens: Int {
        inputTokens + outputTokens + cacheTokens
    }

    var body: some View {
        if totalTokens > 0 {
            if compact {
                compactView
            } else {
                detailView
            }
        }
    }

    // MARK: - 紧凑模式（单行，嵌入会话头部）

    private var compactView: some View {
        VStack(spacing: 4) {
            proportionBar
            HStack(spacing: 10) {
                tokenLabel("Input", count: inputTokens, color: .blue)
                tokenLabel("Output", count: outputTokens, color: .orange)
                if cacheTokens > 0 {
                    tokenLabel("Cache", count: cacheTokens, color: .purple)
                }
                Spacer()
                Text(formatCount(totalTokens) + " total")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
    }

    // MARK: - 详细模式

    private var detailView: some View {
        VStack(spacing: 8) {
            proportionBar
            HStack(spacing: 16) {
                tokenLabel("Input", count: inputTokens, color: .blue)
                tokenLabel("Output", count: outputTokens, color: .orange)
                if cacheTokens > 0 {
                    tokenLabel("Cache", count: cacheTokens, color: .purple)
                }
            }
            Text("Total: \(formatCount(totalTokens))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - 比例条

    private var proportionBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let total = max(CGFloat(totalTokens), 1)
            let inputWidth = width * CGFloat(inputTokens) / total
            let outputWidth = width * CGFloat(outputTokens) / total
            let cacheWidth = width * CGFloat(cacheTokens) / total

            HStack(spacing: 1) {
                if inputTokens > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue.opacity(0.6))
                        .frame(width: max(inputWidth, 2))
                }
                if outputTokens > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.orange.opacity(0.6))
                        .frame(width: max(outputWidth, 2))
                }
                if cacheTokens > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.purple.opacity(0.6))
                        .frame(width: max(cacheWidth, 2))
                }
            }
        }
        .frame(height: 4)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    // MARK: - 辅助

    private func tokenLabel(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color.opacity(0.6)).frame(width: 6, height: 6)
            Text("\(label): \(formatCount(count))")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    /// 格式化数量（>1000 用 K 表示）
    private func formatCount(_ count: Int) -> String {
        if count >= 1000 {
            let k = Double(count) / 1000.0
            if k >= 100 {
                return String(format: "%.0fK", k)
            }
            return String(format: "%.1fK", k)
        }
        return "\(count)"
    }
}
