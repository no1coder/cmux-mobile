import XCTest
@testable import cmux_models

final class ClaudeChatItemCodableTests: XCTestCase {

    func testToolRoleRoundTrip() throws {
        let item = ClaudeChatItem(
            id: "tool-1",
            seq: 42,
            role: .tool(name: "Read"),
            content: "/tmp/file.swift",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            toolResult: "ok",
            toolState: .completed,
            toolUseId: "tool-use-1",
            completedAt: Date(timeIntervalSince1970: 1_700_000_005),
            modelName: "Sonnet"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ClaudeChatItem.self, from: data)

        XCTAssertEqual(decoded, item)
        XCTAssertEqual(decoded.seq, 42)
        XCTAssertEqual(decoded.toolResult, "ok")
        XCTAssertEqual(decoded.toolUseId, "tool-use-1")
        XCTAssertEqual(decoded.modelName, "Sonnet")
    }

    func testTUIOutputRoleRoundTrip() throws {
        let item = ClaudeChatItem(
            id: "tui-1",
            role: .tuiOutput(command: "/status"),
            content: "all systems go",
            timestamp: Date(timeIntervalSince1970: 1_700_000_010)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ClaudeChatItem.self, from: data)

        XCTAssertEqual(decoded, item)
        if case .tuiOutput(let command) = decoded.role {
            XCTAssertEqual(command, "/status")
        } else {
            XCTFail("期望解码为 tuiOutput")
        }
    }
}
