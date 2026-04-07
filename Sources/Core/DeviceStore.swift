import Foundation

// MARK: - 数据模型

/// 已配对设备信息
struct PairedDevice: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var serverURL: String
    var pairSecret: String
    var pairedAt: Date
    var lastConnected: Date?

    /// 用于显示的简短设备标识
    var shortID: String {
        String(id.prefix(8))
    }
}

// MARK: - DeviceStore

/// 多设备存储管理器，将已配对设备列表以 JSON 格式存入 Keychain
/// 同时维护一个"活跃设备"ID，表示当前要连接的设备
enum DeviceStore {

    // MARK: - Keychain 键名

    private static let keyPairedDevices = "pairedDevices"
    private static let keyActiveDeviceID = "activeDeviceID"

    // MARK: - 旧版单设备键名（用于迁移）

    private static let legacyKeyDeviceID = "pairedDeviceID"
    private static let legacyKeyServerURL = "pairedServerURL"

    // MARK: - 读取

    /// 获取所有已配对设备
    static func getDevices() -> [PairedDevice] {
        #if canImport(Security)
        // 首次调用时检查是否需要迁移旧数据
        migrateLegacyIfNeeded()

        guard let json = KeychainHelper.load(key: keyPairedDevices),
              let data = json.data(using: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PairedDevice].self, from: data)) ?? []
        #else
        return []
        #endif
    }

    /// 获取当前活跃设备
    static func getActiveDevice() -> PairedDevice? {
        let devices = getDevices()
        guard !devices.isEmpty else { return nil }

        #if canImport(Security)
        if let activeID = KeychainHelper.load(key: keyActiveDeviceID) {
            return devices.first { $0.id == activeID }
        }
        #endif

        // 没有指定活跃设备时，返回第一个
        return devices.first
    }

    /// 获取活跃设备 ID
    static func getActiveDeviceID() -> String? {
        #if canImport(Security)
        return KeychainHelper.load(key: keyActiveDeviceID)
        #else
        return nil
        #endif
    }

    // MARK: - 写入

    /// 添加新配对设备（如已存在则更新）
    static func addDevice(_ device: PairedDevice) {
        var devices = getDevices()

        // 如果设备已存在，替换它
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }

        saveDevices(devices)

        // 如果是第一个设备，自动设为活跃
        if devices.count == 1 {
            setActiveDevice(id: device.id)
        }
    }

    /// 从 PairResult 创建并添加设备
    static func addFromPairResult(_ result: PairResult) {
        let device = PairedDevice(
            id: result.deviceID,
            name: result.deviceName,
            serverURL: result.serverURL,
            pairSecret: result.pairSecret,
            pairedAt: Date(),
            lastConnected: nil
        )
        addDevice(device)
        setActiveDevice(id: device.id)
    }

    /// 移除指定设备
    static func removeDevice(id: String) {
        let devices = getDevices().filter { $0.id != id }
        saveDevices(devices)

        #if canImport(Security)
        // 清理旧版键
        KeychainHelper.delete(key: "pairSecret_\(id)")
        KeychainHelper.delete(key: "serverURL_\(id)")
        KeychainHelper.delete(key: "deviceName_\(id)")

        // 如果删除的是活跃设备，切换到第一个可用设备
        if getActiveDeviceID() == id {
            if let first = devices.first {
                setActiveDevice(id: first.id)
            } else {
                KeychainHelper.delete(key: keyActiveDeviceID)
                // 清理旧版单设备键
                KeychainHelper.delete(key: legacyKeyDeviceID)
                KeychainHelper.delete(key: legacyKeyServerURL)
            }
        }
        #endif
    }

    /// 设置活跃设备 ID
    static func setActiveDevice(id: String) {
        #if canImport(Security)
        try? KeychainHelper.save(key: keyActiveDeviceID, value: id)

        // 同步更新旧版键以保持向后兼容
        if let device = getDevices().first(where: { $0.id == id }) {
            try? KeychainHelper.save(key: legacyKeyDeviceID, value: device.id)
            try? KeychainHelper.save(key: legacyKeyServerURL, value: device.serverURL)
        }
        #endif
    }

    /// 更新设备的最后连接时间
    static func updateLastConnected(id: String) {
        var devices = getDevices()
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }

        let device = devices[index]
        let updated = PairedDevice(
            id: device.id,
            name: device.name,
            serverURL: device.serverURL,
            pairSecret: device.pairSecret,
            pairedAt: device.pairedAt,
            lastConnected: Date()
        )
        devices[index] = updated
        saveDevices(devices)
    }

    // MARK: - 清空

    /// 移除所有设备
    static func removeAllDevices() {
        let devices = getDevices()
        for device in devices {
            #if canImport(Security)
            KeychainHelper.delete(key: "pairSecret_\(device.id)")
            KeychainHelper.delete(key: "serverURL_\(device.id)")
            KeychainHelper.delete(key: "deviceName_\(device.id)")
            #endif
        }

        #if canImport(Security)
        KeychainHelper.delete(key: keyPairedDevices)
        KeychainHelper.delete(key: keyActiveDeviceID)
        KeychainHelper.delete(key: legacyKeyDeviceID)
        KeychainHelper.delete(key: legacyKeyServerURL)
        #endif
    }

    // MARK: - 私有方法

    /// 将设备列表序列化后存入 Keychain
    private static func saveDevices(_ devices: [PairedDevice]) {
        #if canImport(Security)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(devices),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        try? KeychainHelper.save(key: keyPairedDevices, value: json)
        #endif
    }

    /// 从旧版单设备 Keychain 键迁移到多设备格式（仅执行一次）
    private static func migrateLegacyIfNeeded() {
        #if canImport(Security)
        // 如果已有多设备数据，跳过迁移
        if KeychainHelper.load(key: keyPairedDevices) != nil {
            return
        }

        // 检查旧版数据
        guard let deviceID = KeychainHelper.load(key: legacyKeyDeviceID),
              let serverURL = KeychainHelper.load(key: legacyKeyServerURL),
              let pairSecret = KeychainHelper.load(key: "pairSecret_\(deviceID)") else {
            return
        }

        let deviceName = KeychainHelper.load(key: "deviceName_\(deviceID)") ?? deviceID

        let device = PairedDevice(
            id: deviceID,
            name: deviceName,
            serverURL: serverURL,
            pairSecret: pairSecret,
            pairedAt: Date(),
            lastConnected: nil
        )

        saveDevices([device])
        try? KeychainHelper.save(key: keyActiveDeviceID, value: deviceID)
        #endif
    }
}
