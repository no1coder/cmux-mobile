import SwiftUI

/// 已配对设备列表视图：展示所有配对的 Mac 设备，支持切换、删除和添加
struct DeviceListView: View {
    @EnvironmentObject var relayConnection: RelayConnection
    var startScanningOnAppear: Bool = false

    // MARK: - 状态

    @State private var devices: [PairedDevice] = []
    @State private var activeDeviceID: String?
    @State private var showScanner: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var deviceToDelete: PairedDevice?
    @State private var feedbackMessage: String?
    @State private var isSwitching: Bool = false
    @State private var didAutoStartScanner = false
    @State private var pendingPairingQRCode: QRCodeData?
    @State private var pairingRecoveryError: String?

    /// 配对管理器
    @StateObject private var pairingManager = PairingManager()

    var body: some View {
        Group {
            if devices.isEmpty {
                emptyState
            } else {
                deviceList
            }
        }
        .onAppear { reloadDevices() }
        .onAppear {
            guard startScanningOnAppear,
                  !didAutoStartScanner,
                  devices.isEmpty else { return }
            didAutoStartScanner = true
            showScanner = true
        }
        .onChange(of: relayConnection.status) { _, newStatus in
            isSwitching = newStatus == .connecting
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showScanner = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "device_list.scan_button", defaultValue: "扫码配对"))
            }
        }
        .alert(
            String(localized: "device_list.delete_title", defaultValue: "移除设备"),
            isPresented: $showDeleteConfirm
        ) {
            Button(
                String(localized: "device_list.delete_action", defaultValue: "移除"),
                role: .destructive
            ) {
                if let device = deviceToDelete {
                    deleteDevice(device)
                }
            }
            Button(
                String(localized: "device_list.cancel", defaultValue: "取消"),
                role: .cancel
            ) {
                deviceToDelete = nil
            }
        } message: {
            if let device = deviceToDelete {
                Text(String(
                    localized: "device_list.delete_message",
                    defaultValue: "确定移除「\(device.name)」？移除后需要重新扫码配对。"
                ))
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerView(
                onScanned: { text in handleQRScanned(text) },
                onDismiss: { showScanner = false }
            )
            .ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let error = pairingRecoveryError {
                    pairingRecoveryBanner(error)
                }

                if let msg = feedbackMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut, value: feedbackMessage)
        .animation(.easeInOut, value: pairingRecoveryError)
        .onChange(of: pairingManager.pairedDevice) { _, result in
            guard let result else { return }
            DeviceStore.addFromPairResult(result)
            pendingPairingQRCode = nil
            pairingRecoveryError = nil
            reloadDevices()
            connectToDevice(result.deviceID)
            showScanner = false
            showFeedback(String(localized: "device_list.paired_success", defaultValue: "配对成功！"))
        }
        .onChange(of: pairingManager.error) { _, error in
            guard let error else { return }
            showScanner = false
            pairingRecoveryError = error
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                String(localized: "device_list.empty_title", defaultValue: "尚未添加任何设备"),
                systemImage: "desktopcomputer"
            )
        } description: {
            Text(String(
                localized: "device_list.empty_description",
                defaultValue: "点击右上角 + 扫描 Mac 上的二维码进行配对"
            ))
        } actions: {
            Button {
                showScanner = true
            } label: {
                Label(
                    String(localized: "device_list.scan_button", defaultValue: "扫码配对"),
                    systemImage: "qrcode.viewfinder"
                )
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - 设备列表

    private var deviceList: some View {
        List {
            if needsManualDeviceSelection {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "hand.tap.fill")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(
                                localized: "device_list.choose_device_title",
                                defaultValue: "请选择要连接的设备"
                            ))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            Text(String(
                                localized: "device_list.choose_device_desc",
                                defaultValue: "你有多台已配对的 Mac。点按下方任意一台，明确选择本次要连接的设备。"
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // 连接诊断：当前活跃设备断线且有错误时显示具体原因 + 重试
            if let error = relayConnection.lastConnectionError,
               relayConnection.status != .connected,
               activeDeviceID != nil {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(
                                localized: "device_list.connection_error_title",
                                defaultValue: "连接失败"
                            ))
                            .font(.subheadline).fontWeight(.semibold)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Button {
                            if let id = activeDeviceID { connectToDevice(id) }
                        } label: {
                            Text(String(localized: "common.retry", defaultValue: "重试"))
                                .font(.caption).fontWeight(.semibold)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }

            ForEach(devices) { device in
                DeviceRow(
                    device: device,
                    isActive: device.id == activeDeviceID,
                    connectionStatus: connectionStatus(for: device),
                    isSwitching: isSwitching && device.id != activeDeviceID
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    guard device.id != activeDeviceID else { return }
                    switchToDevice(device)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deviceToDelete = device
                        showDeleteConfirm = true
                    } label: {
                        Label(
                            String(localized: "device_list.delete_swipe", defaultValue: "移除"),
                            systemImage: "trash"
                        )
                    }
                }
            }

            if pairingManager.isPairing {
                HStack {
                    ProgressView()
                        .padding(.trailing, 8)
                    Text(String(localized: "device_list.pairing", defaultValue: "正在配对..."))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 辅助方法

    /// 获取设备的连接状态
    private func connectionStatus(for device: PairedDevice) -> DeviceConnectionStatus {
        guard device.id == activeDeviceID else { return .inactive }
        switch relayConnection.status {
        case .connected: return .online
        case .connecting: return .connecting
        case .disconnected: return .offline
        case .macOffline: return .offline
        }
    }

    /// 重新加载设备列表
    private func reloadDevices() {
        devices = DeviceStore.getDevices()
        activeDeviceID = DeviceStore.resolveActiveDevice(
            in: devices,
            activeDeviceID: DeviceStore.getActiveDeviceID()
        )?.id

        // 仅在单设备场景下自动设为活跃，避免多设备时猜错用户想连接哪台 Mac
        if activeDeviceID == nil, devices.count == 1, let first = devices.first {
            DeviceStore.setActiveDevice(id: first.id)
            activeDeviceID = first.id
        }
    }

    /// 切换活跃设备
    private func switchToDevice(_ device: PairedDevice) {
        isSwitching = true
        relayConnection.disconnect()
        activeDeviceID = device.id
        DeviceStore.setActiveDevice(id: device.id)
        connectToDevice(device.id)
        showFeedback(String(
            localized: "device_list.switched",
            defaultValue: "已切换到「\(device.name)」"
        ))
    }

    /// 连接到指定设备
    private func connectToDevice(_ deviceID: String) {
        guard let device = DeviceStore.getDevices().first(where: { $0.id == deviceID }) else {
            return
        }
        let phoneID = getOrCreatePhoneID()
        relayConnection.switchDevice(
            serverURL: device.serverURL,
            phoneID: phoneID,
            pairSecret: device.pairSecret
        )
        DeviceStore.updateLastConnected(id: deviceID)
    }

    /// 删除设备
    private func deleteDevice(_ device: PairedDevice) {
        let wasActive = device.id == activeDeviceID
        DeviceStore.removeDevice(id: device.id)
        reloadDevices()

        if wasActive {
            relayConnection.disconnect()
            // 如果还有其他设备，连接到新的活跃设备
            if let newActive = DeviceStore.getActiveDevice() {
                connectToDevice(newActive.id)
            }
        }

        deviceToDelete = nil
        showFeedback(String(localized: "device_list.deleted", defaultValue: "已移除设备"))
    }

    /// 处理 QR 扫码
    private func handleQRScanned(_ text: String) {
        guard let qrData = PairingManager.parseQRCode(text) else {
            showScanner = false
            pendingPairingQRCode = nil
            pairingRecoveryError = String(
                localized: "device_list.invalid_qr",
                defaultValue: "无效的配对二维码"
            )
            return
        }

        pendingPairingQRCode = qrData
        pairingRecoveryError = nil
        showScanner = false
        beginPairing(with: qrData)
    }

    private func beginPairing(with qrData: QRCodeData) {
        let phoneID = getOrCreatePhoneID()
        let phoneName = UIDevice.current.name

        Task {
            await pairingManager.confirmPairing(
                qrData: qrData,
                phoneID: phoneID,
                phoneName: phoneName
            )
        }
    }

    private func retryPendingPairing() {
        guard let qrData = pendingPairingQRCode else {
            pairingRecoveryError = nil
            showScanner = true
            return
        }

        pairingRecoveryError = nil
        beginPairing(with: qrData)
    }

    /// 获取或创建手机 ID
    private func getOrCreatePhoneID() -> String {
        #if canImport(Security)
        if let existing = KeychainHelper.load(key: "phoneID") {
            return existing
        }
        let newID = "phone-" + UUID().uuidString.prefix(8).lowercased()
        try? KeychainHelper.save(key: "phoneID", value: newID)
        return newID
        #else
        return "phone-" + UUID().uuidString.prefix(8).lowercased()
        #endif
    }

    /// 显示反馈消息
    private func showFeedback(_ message: String) {
        feedbackMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            feedbackMessage = nil
        }
    }

    @ViewBuilder
    private func pairingRecoveryBanner(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if pendingPairingQRCode != nil {
                    Button {
                        retryPendingPairing()
                    } label: {
                        Text(String(localized: "common.retry", defaultValue: "重试"))
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button {
                    pairingRecoveryError = nil
                    showScanner = true
                } label: {
                    Text(String(localized: "device_list.scan_button", defaultValue: "扫码配对"))
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var needsManualDeviceSelection: Bool {
        activeDeviceID == nil && devices.count > 1
    }
}

// MARK: - 连接状态枚举

enum DeviceConnectionStatus {
    case online
    case offline
    case connecting
    case inactive

    var label: String {
        switch self {
        case .online: return String(localized: "device_status.online", defaultValue: "在线")
        case .offline: return String(localized: "device_status.offline", defaultValue: "离线")
        case .connecting: return String(localized: "device_status.connecting", defaultValue: "连接中")
        case .inactive: return String(localized: "device_status.inactive", defaultValue: "未激活")
        }
    }

    var color: Color {
        switch self {
        case .online: return .green
        case .offline: return .red
        case .connecting: return .orange
        case .inactive: return .secondary
        }
    }

    var icon: String {
        switch self {
        case .online: return "circle.fill"
        case .offline: return "circle"
        case .connecting: return "circle.dotted"
        case .inactive: return "circle"
        }
    }
}

// MARK: - 设备行视图

private struct DeviceRow: View {
    let device: PairedDevice
    let isActive: Bool
    let connectionStatus: DeviceConnectionStatus
    let isSwitching: Bool

    var body: some View {
        HStack(spacing: 12) {
            // 设备图标
            Image(systemName: "desktopcomputer")
                .font(.title2)
                .foregroundStyle(isActive ? .blue : .secondary)
                .frame(width: 36)

            // 设备信息
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(device.name)
                        .font(.body)
                        .fontWeight(isActive ? .semibold : .regular)

                    if isActive {
                        Text(String(localized: "device_row.active", defaultValue: "活跃"))
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue)
                            .clipShape(Capsule())
                    }
                }

                Text(device.serverURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // 连接状态指示器
            HStack(spacing: 4) {
                if isSwitching {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: connectionStatus.icon)
                        .font(.caption)
                        .foregroundStyle(connectionStatus.color)
                }

                Text(connectionStatus.label)
                    .font(.caption)
                    .foregroundStyle(connectionStatus.color)
            }
        }
        .padding(.vertical, 4)
    }
}
