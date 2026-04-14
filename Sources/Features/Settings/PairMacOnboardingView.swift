import SwiftUI

/// Connection-first onboarding shown before any device has been paired.
struct PairMacOnboardingView: View {
    let title: String
    let message: String
    var highlights: [String] = []

    @EnvironmentObject private var relayConnection: RelayConnection
    @State private var showPairingSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.system(size: 52))
                    .foregroundStyle(.blue)
                    .padding(.top, 32)

                VStack(spacing: 10) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                if !highlights.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(highlights, id: \.self) { highlight in
                            Label(highlight, systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(CMColors.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    showPairingSettings = true
                } label: {
                    Label(
                        String(localized: "pairing.onboarding.cta", defaultValue: "配对 Mac"),
                        systemImage: "qrcode.viewfinder"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text(String(
                    localized: "pairing.onboarding.hint",
                    defaultValue: "在 Mac 上打开 Devpod / cmux 桌面端并显示二维码，然后继续。"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(CMColors.backgroundPrimary)
        .sheet(isPresented: $showPairingSettings) {
            NavigationStack {
                PairingSettingsView(startScanningOnAppear: true)
                    .environmentObject(relayConnection)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceStoreDidChange)) { _ in
            if DeviceStore.hasPairedDevice() {
                showPairingSettings = false
            }
        }
    }
}
