import Testing
@testable import cmux_mobile

struct ANSIParserTests {
    @Test func testPlainText() {
        let result = ANSIParser.parse("hello world")
        #expect(String(result.characters) == "hello world")
    }

    @Test func testBoldText() {
        let result = ANSIParser.parse("\u{1B}[1mbold\u{1B}[0m normal")
        #expect(String(result.characters) == "bold normal")
    }

    @Test func testColoredText() {
        let result = ANSIParser.parse("\u{1B}[32mgreen\u{1B}[0m")
        #expect(String(result.characters) == "green")
    }

    @Test func testNestedStyles() {
        let result = ANSIParser.parse("\u{1B}[1;31mred bold\u{1B}[0m")
        #expect(String(result.characters) == "red bold")
    }

    @Test func test256Color() {
        let result = ANSIParser.parse("\u{1B}[38;5;196mred256\u{1B}[0m")
        #expect(String(result.characters) == "red256")
    }
}
