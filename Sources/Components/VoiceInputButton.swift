import SwiftUI

/// 语音输入按钮 — 点击开始/停止录音，录音时显示波形动画
struct VoiceInputButton: View {
    let isRecording: Bool
    let action: () -> Void

    @State private var animationPhase: CGFloat = 0

    var body: some View {
        Button(action: action) {
            ZStack {
                // 录音时的脉冲动画
                if isRecording {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 36, height: 36)
                        .scaleEffect(1.0 + animationPhase * 0.3)
                        .opacity(1.0 - animationPhase * 0.5)
                }

                Image(systemName: isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isRecording ? .red : .gray.opacity(0.6))
                    .frame(width: 30, height: 30)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: isRecording) { _, recording in
            if recording {
                startPulseAnimation()
            } else {
                animationPhase = 0
            }
        }
    }

    private func startPulseAnimation() {
        animationPhase = 0
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            animationPhase = 1.0
        }
    }
}
