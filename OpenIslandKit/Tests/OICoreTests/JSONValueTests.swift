import Foundation
@testable import OICore
import Testing

struct JSONValueTests {
    @Test
    func `Codable round-trip for all types`() throws {
        let original: JSONValue = [
            "string": "hello",
            "int": 42,
            "double": 3.14,
            "bool": true,
            "null": nil,
            "array": [1, 2, 3],
            "nested": ["key": "value"],
        ]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(decoded == original)
    }

    @Test
    func `String subscript returns value for objects`() {
        let json: JSONValue = ["name": "test", "count": 42]
        #expect(json["name"]?.stringValue == "test")
        #expect(json["count"]?.intValue == 42)
        #expect(json["missing"] == nil)
    }

    @Test
    func `Int subscript returns value for arrays`() {
        let json: JSONValue = [10, 20, 30]
        #expect(json[0]?.intValue == 10)
        #expect(json[2]?.intValue == 30)
        #expect(json[5] == nil)
    }

    @Test
    func `Type mismatch subscripts return nil`() {
        let str: JSONValue = "hello"
        #expect(str["key"] == nil)
        #expect(str[0] == nil)
    }

    @Test
    func `Convenience properties`() {
        #expect(JSONValue.string("hi").stringValue == "hi")
        #expect(JSONValue.int(42).intValue == 42)
        #expect(JSONValue.double(3.14).doubleValue == 3.14)
        #expect(JSONValue.bool(true).boolValue == true)
        #expect(JSONValue.null.isNull == true)
        #expect(JSONValue.string("hi").isNull == false)
    }

    @Test
    func `Convenience properties return nil for wrong type`() {
        #expect(JSONValue.string("hi").intValue == nil)
        #expect(JSONValue.int(42).stringValue == nil)
        #expect(JSONValue.double(3.14).boolValue == nil)
        #expect(JSONValue.bool(true).doubleValue == nil)
        #expect(JSONValue.null.stringValue == nil)
        #expect(JSONValue.string("hi").arrayValue == nil)
        #expect(JSONValue.int(1).objectValue == nil)
    }

    @Test
    func `Literal conformances`() {
        let str: JSONValue = "hello"
        let int: JSONValue = 42
        let dbl: JSONValue = 3.14
        let bool: JSONValue = true
        let null: JSONValue = nil
        let arr: JSONValue = [1, 2, 3]
        let obj: JSONValue = ["key": "value"]
        #expect(str.stringValue == "hello")
        #expect(int.intValue == 42)
        #expect(dbl.doubleValue == 3.14)
        #expect(bool.boolValue == true)
        #expect(null.isNull)
        #expect(arr.arrayValue?.count == 3)
        #expect(obj.objectValue?["key"]?.stringValue == "value")
    }

    @Test
    func `Nested access`() {
        let json: JSONValue = ["users": [["name": "Alice"], ["name": "Bob"]]]
        #expect(json["users"]?[0]?["name"]?.stringValue == "Alice")
        #expect(json["users"]?[1]?["name"]?.stringValue == "Bob")
    }

    @Test
    func `Empty object and array`() {
        let emptyObj: JSONValue = .object([:])
        let emptyArr: JSONValue = .array([])
        #expect(emptyObj.objectValue?.isEmpty == true)
        #expect(emptyArr.arrayValue?.isEmpty == true)
        #expect(emptyObj["key"] == nil)
        #expect(emptyArr[0] == nil)
    }

    @Test
    func `Equatable across all cases`() {
        let lhs = JSONValue.string("a")
        let rhs = JSONValue.string("a")
        #expect(lhs == rhs)
        #expect(JSONValue.string("a") != JSONValue.string("b"))
        let intLHS = JSONValue.int(1)
        let intRHS = JSONValue.int(1)
        #expect(intLHS == intRHS)
        #expect(JSONValue.int(1) != JSONValue.int(2))
        let doubleLHS = JSONValue.double(1.5)
        let doubleRHS = JSONValue.double(1.5)
        #expect(doubleLHS == doubleRHS)
        let boolLHS = JSONValue.bool(true)
        let boolRHS = JSONValue.bool(true)
        #expect(boolLHS == boolRHS)
        #expect(JSONValue.bool(true) != JSONValue.bool(false))
        let nullLHS = JSONValue.null
        let nullRHS = JSONValue.null
        #expect(nullLHS == nullRHS)
        #expect(JSONValue.string("a") != JSONValue.int(1))
    }

    @Test
    func `Decode bool is not confused with int`() throws {
        let jsonData = Data(#"true"#.utf8)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: jsonData)
        #expect(decoded == .bool(true))
        #expect(decoded.boolValue == true)
        #expect(decoded.intValue == nil)
    }

    @Test
    func `Decode int stays int, not double`() throws {
        let jsonData = Data(#"42"#.utf8)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: jsonData)
        #expect(decoded == .int(42))
        #expect(decoded.intValue == 42)
        #expect(decoded.doubleValue == nil)
    }
}
