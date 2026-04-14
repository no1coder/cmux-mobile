import XCTest
@testable import cmux_models

final class AnyCodableTests: XCTestCase {

    // MARK: - 各 case 的 JSON 往返编解码

    func testNullRoundTrip() throws {
        let value = AnyCodable.null
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)
        XCTAssertEqual(decoded, .null)
    }

    func testBoolRoundTrip() throws {
        let value = AnyCodable.bool(true)
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)
        XCTAssertEqual(decoded, .bool(true))
    }

    func testIntRoundTrip() throws {
        let value = AnyCodable.int(42)
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)
        XCTAssertEqual(decoded, .int(42))
    }

    func testDoubleRoundTrip() throws {
        let value = AnyCodable.double(3.14)
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)
        // double 对比用精度容差
        if case .double(let d) = decoded {
            XCTAssertEqual(d, 3.14, accuracy: 1e-10)
        } else {
            XCTFail("期望 .double，实际为 \(decoded)")
        }
    }

    func testStringRoundTrip() throws {
        let value = AnyCodable.string("hello world")
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)
        XCTAssertEqual(decoded, .string("hello world"))
    }

    func testArrayRoundTrip() throws {
        let value = AnyCodable.array([.int(1), .string("two"), .bool(false)])
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)
        XCTAssertEqual(decoded, value)
    }

    func testObjectRoundTrip() throws {
        let value = AnyCodable.object(["key": .string("val"), "num": .int(7)])
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)
        XCTAssertEqual(decoded, value)
    }

    // MARK: - 嵌套结构（dict 内含 array 内含 dict）

    func testNestedStructureRoundTrip() throws {
        let inner = AnyCodable.object(["x": .int(1)])
        let arr = AnyCodable.array([inner, .null])
        let outer = AnyCodable.object(["list": arr, "flag": .bool(true)])
        let encoded = try JSONEncoder().encode(outer)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: encoded)
        XCTAssertEqual(decoded, outer)
    }

    // MARK: - 从原始 JSON 字节解码

    func testDecodeFromRawJSON() throws {
        let json = """
        {"name":"cmux","count":3,"active":true,"score":null}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: json)
        guard case .object(let dict) = decoded else {
            XCTFail("期望 .object"); return
        }
        XCTAssertEqual(dict["name"], .string("cmux"))
        XCTAssertEqual(dict["count"], .int(3))
        XCTAssertEqual(dict["active"], .bool(true))
        XCTAssertEqual(dict["score"], .null)
    }
}
