import Testing
import Foundation
@testable import cmux_mobile

struct MessageStoreTests {

    // MARK: - 辅助方法

    /// 构造标准 RelayEnvelope JSON
    private func makeEnvelope(
        seq: UInt64,
        type: String,
        payload: [String: Any]
    ) -> Data {
        var dict: [String: Any] = [
            "seq": seq,
            "ts": Int64(Date().timeIntervalSince1970 * 1000),
            "from": "mac",
            "type": type,
            "payload": payload
        ]
        return try! JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: - Seq 追踪测试

    @Test @MainActor func testSeqTracking() async {
        let store = MessageStore()

        let msg1 = makeEnvelope(seq: 1, type: "event", payload: [:])
        let msg2 = makeEnvelope(seq: 2, type: "event", payload: [:])
        let msg5 = makeEnvelope(seq: 5, type: "event", payload: [:])

        store.processRawMessage(msg1)
        store.processRawMessage(msg2)
        store.processRawMessage(msg5)

        #expect(store.lastSeq == 5)
    }

    @Test @MainActor func testSeqDoesNotDecrease() async {
        let store = MessageStore()

        let msg5 = makeEnvelope(seq: 5, type: "event", payload: [:])
        let msg3 = makeEnvelope(seq: 3, type: "event", payload: [:])

        store.processRawMessage(msg5)
        store.processRawMessage(msg3)

        // lastSeq 不应该因收到旧消息而减小
        #expect(store.lastSeq == 5)
    }

    // MARK: - 屏幕快照测试

    @Test @MainActor func testScreenSnapshotUpdate() async {
        let store = MessageStore()

        let payload: [String: Any] = [
            "event": "screen.snapshot",
            "surface_id": "surf-001",
            "lines": ["$ ls -la", "total 42", "drwxr-xr-x  5 user group 160 Jan 1 00:00 ."],
            "dimensions": ["rows": 24, "cols": 80]
        ]

        let msg = makeEnvelope(seq: 1, type: "event", payload: payload)
        store.processRawMessage(msg)

        let snapshot = store.snapshots["surf-001"]
        #expect(snapshot != nil)
        #expect(snapshot?.surfaceID == "surf-001")
        #expect(snapshot?.lines.count == 3)
        #expect(snapshot?.lines[0] == "$ ls -la")
        #expect(snapshot?.dimensions.rows == 24)
        #expect(snapshot?.dimensions.cols == 80)
    }

    @Test @MainActor func testScreenSnapshotOverwrite() async {
        let store = MessageStore()

        let payload1: [String: Any] = [
            "event": "screen.snapshot",
            "surface_id": "surf-001",
            "lines": ["old line"],
            "dimensions": ["rows": 24, "cols": 80]
        ]
        let payload2: [String: Any] = [
            "event": "screen.snapshot",
            "surface_id": "surf-001",
            "lines": ["new line 1", "new line 2"],
            "dimensions": ["rows": 24, "cols": 80]
        ]

        store.processRawMessage(makeEnvelope(seq: 1, type: "event", payload: payload1))
        store.processRawMessage(makeEnvelope(seq: 2, type: "event", payload: payload2))

        let snapshot = store.snapshots["surf-001"]
        #expect(snapshot?.lines.count == 2)
        #expect(snapshot?.lines[0] == "new line 1")
    }

    // MARK: - Surface 列表测试

    @Test @MainActor func testSurfaceListUpdateFromRPCResponse() async {
        let store = MessageStore()

        let surfaceData: [[String: Any]] = [
            [
                "id": "surf-001",
                "ref": "t1",
                "index": 0,
                "type": "terminal",
                "title": "Terminal 1",
                "focused": true
            ],
            [
                "id": "surf-002",
                "ref": "t2",
                "index": 1,
                "type": "terminal",
                "title": "Terminal 2",
                "focused": false
            ]
        ]

        let payload: [String: Any] = [
            "result": [
                "surfaces": surfaceData
            ]
        ]

        let msg = makeEnvelope(seq: 1, type: "rpc_response", payload: payload)
        store.processRawMessage(msg)

        #expect(store.surfaces.count == 2)
        #expect(store.surfaces[0].id == "surf-001")
        #expect(store.surfaces[0].title == "Terminal 1")
        #expect(store.surfaces[0].focused == true)
        #expect(store.surfaces[1].id == "surf-002")
    }

    @Test @MainActor func testSurfaceListReplaces() async {
        let store = MessageStore()

        // 首次设置 2 个 surface
        let payload1: [String: Any] = [
            "result": [
                "surfaces": [
                    ["id": "s1", "ref": "r1", "index": 0, "type": "terminal", "title": "T1", "focused": false],
                    ["id": "s2", "ref": "r2", "index": 1, "type": "terminal", "title": "T2", "focused": false]
                ]
            ]
        ]
        store.processRawMessage(makeEnvelope(seq: 1, type: "rpc_response", payload: payload1))
        #expect(store.surfaces.count == 2)

        // 更新为 1 个 surface
        let payload2: [String: Any] = [
            "result": [
                "surfaces": [
                    ["id": "s1", "ref": "r1", "index": 0, "type": "terminal", "title": "T1 Updated", "focused": true]
                ]
            ]
        ]
        store.processRawMessage(makeEnvelope(seq: 2, type: "rpc_response", payload: payload2))
        #expect(store.surfaces.count == 1)
        #expect(store.surfaces[0].title == "T1 Updated")
    }
}
