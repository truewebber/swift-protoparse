import XCTest

@testable import SwiftProtoParser

final class ParserTests: XCTestCase {
  private func parse(_ input: String) throws -> FileNode {
    let lexer = Lexer(input: input)
    let parser = try Parser(lexer: lexer)
    return try parser.parseFile()
  }

  // MARK: - Syntax Declaration Tests

  func testValidSyntaxDeclaration() throws {
    let input = """
      syntax = "proto3";
      """
    let file = try parse(input)
    XCTAssertEqual(file.syntax, "proto3")
  }

  func testInvalidSyntaxValue() throws {
    let inputs = [
      """
      syntax = "proto2";
      """,
      """
      syntax = "invalid";
      """,
      """
      syntax = proto3;
      """,
    ]

    for input in inputs {
      XCTAssertThrowsError(try parse(input)) { error in
        guard let error = error as? ParserError else {
          XCTFail("Expected ParserError")
          return
        }

        XCTAssertEqual(error.description.contains("syntax"), true)
      }
    }
  }

  func testMissingSyntax() throws {
    let input = """
      package test;
      """
    let file = try parse(input)
    XCTAssertEqual(file.syntax, "proto3")  // Default to proto3
  }

  // MARK: - Package Declaration Tests

  func testValidPackageDeclaration() throws {
    let input = """
      syntax = "proto3";
      package foo.bar.baz;
      """
    let file = try parse(input)
    XCTAssertEqual(file.package, "foo.bar.baz")
  }

  func testInvalidPackageName() throws {
    let inputs = [
      "package 123.456;",
      "package .test;",
      "package test.;",
      "package test..name;",
      "package Test.Name;",
    ]

    for input in inputs {
      XCTAssertThrowsError(try parse(input)) { error in
        guard let error = error as? ParserError else {
          XCTFail("Expected ParserError")
          return
        }
        XCTAssertEqual(error.description.contains("package"), true)
      }
    }
  }

  // MARK: - Import Tests

  func testValidImports() throws {
    let input = """
      syntax = "proto3";
      import "other.proto";
      import public "public.proto";
      import weak "weak.proto";
      """
    let file = try parse(input)
    XCTAssertEqual(file.imports.count, 3)
    XCTAssertEqual(file.imports[0].path, "other.proto")
    XCTAssertEqual(file.imports[0].modifier, .none)
    XCTAssertEqual(file.imports[1].path, "public.proto")
    XCTAssertEqual(file.imports[1].modifier, .public)
    XCTAssertEqual(file.imports[2].path, "weak.proto")
    XCTAssertEqual(file.imports[2].modifier, .weak)
  }

  func testInvalidImports() throws {
    let inputs = [
      """
      import;
      """,
      """
      import public;
      """,
      """
      import weak;
      """,
      """
      import "missing_semicolon"
      """,
    ]

    for input in inputs {
      XCTAssertThrowsError(try parse(input))
    }
  }

  // MARK: - Empty File Tests

  func testEmptyFile() throws {
    let input = ""
    let file = try parse(input)
    XCTAssertEqual(file.syntax, "proto3")
    XCTAssertNil(file.package)
    XCTAssertTrue(file.imports.isEmpty)
    XCTAssertTrue(file.options.isEmpty)
    XCTAssertTrue(file.messages.isEmpty)
    XCTAssertTrue(file.enums.isEmpty)
    XCTAssertTrue(file.services.isEmpty)
  }

  func testWhitespaceOnlyFile() throws {
    let input = "  \n\t\n   "
    let file = try parse(input)
    XCTAssertEqual(file.syntax, "proto3")
  }

  // MARK: - Invalid File Structure Tests

  func testSyntaxAfterOtherDeclarations() throws {
    let input = """
      package test;
      syntax = "proto3";
      """
    XCTAssertThrowsError(try parse(input))
  }

  func testDuplicatePackageDeclaration() throws {
    let input = """
      syntax = "proto3";
      package test;
      package other;
      """
    XCTAssertThrowsError(try parse(input))
  }

  func testIncompleteFile() throws {
    let inputs = [
      "syntax = ",
      "package ",
      "import ",
      "syntax = \"proto3",
      "package test",
    ]

    for input in inputs {
      XCTAssertThrowsError(try parse(input))
    }
  }

  // MARK: - Message Tests

  func testBasicMessageDefinition() throws {
    let input = """
      message Test {
        string name = 1;
        int32 id = 2;
        bool active = 3;
      }
      """
    let file = try parse(input)
    XCTAssertEqual(file.messages.count, 1)
    let message = file.messages[0]
    XCTAssertEqual(message.name, "Test")
    XCTAssertEqual(message.fields.count, 3)
  }

  func testNestedMessages() throws {
    let input = """
      message Outer {
        string name = 1;
        message Middle {
      	int32 id = 1;
      	message Inner {
      	  bool active = 1;
      	}
      	Inner inner = 2;
        }
        Middle middle = 2;
      }
      """
    let file = try parse(input)
    let outer = file.messages[0]
    XCTAssertEqual(outer.messages.count, 1)
    let middle = outer.messages[0]
    XCTAssertEqual(middle.messages.count, 1)
  }

  func testInvalidMessageName() throws {
    let inputs = [
      "message 123 {}",
      "message test {}",  // Must start with uppercase
      "message Test$Name {}",
      "message Test.Name {}",
    ]

    for input in inputs {
      XCTAssertThrowsError(try parse(input))
    }
  }

  func testEmptyMessage() throws {
    let input = "message Empty {}"
    let file = try parse(input)
    XCTAssertTrue(file.messages[0].fields.isEmpty)
  }

  func testMultipleMessages() throws {
    let input = """
      message First {}
      message Second {}
      message Third {}
      """
    let file = try parse(input)
    XCTAssertEqual(file.messages.count, 3)
  }

  func testReservedFields() throws {
    let input = """
      message Test {
        reserved 2, 15, 9 to 11;
        reserved "foo", "bar";
        string name = 1;
      }
      """
    let file = try parse(input)
    let message = file.messages[0]
    XCTAssertEqual(message.reserved.count, 2)
  }

  func testDuplicateFieldNumbers() throws {
    let input = """
      message Test {
        string name = 1;
        int32 id = 1;
      }
      """

    XCTAssertThrowsError(try parse(input))
  }

  func testInvalidFieldNumbers() throws {
    let inputs = [
      "message Test { string name = 0; }",
      "message Test { string name = 19000; }",  // Reserved range
      "message Test { string name = 536870912; }",  // Too large
    ]

    for input in inputs {
      XCTAssertThrowsError(try parse(input))
    }
  }

  func testMapFields() throws {
    let input = """
      message Test {
        map<string, Project> projects = 1;
        map<int32, string> names = 2;
      }
      """

    let file = try parse(input)
    let fields = file.messages[0].fields

    XCTAssertEqual(fields.count, 2)

    if case .map = fields[0].type {
      // Map type verified
    } else {
      XCTFail("Expected map type")
    }
  }

  func testOneofFields() throws {
    let input = """
      message Test {
        oneof test_oneof {
      	string name = 1;
      	int32 id = 2;
        }
      }
      """

    let file = try parse(input)
    let message = file.messages[0]

    XCTAssertEqual(message.oneofs.count, 1)
    XCTAssertEqual(message.oneofs[0].fields.count, 2)
  }

  func testOptionalFields() throws {
    let input = """
      message Test {
        optional string name = 1;
        optional int32 id = 2;
      }
      """

    let file = try parse(input)
    let fields = file.messages[0].fields

    XCTAssertTrue(fields[0].isOptional)
    XCTAssertTrue(fields[1].isOptional)
  }

  func testRequiredFields() throws {
    let input = "message Test { required string name = 1; }"
    XCTAssertThrowsError(try parse(input))
  }

  // MARK: - Field Tests

  func testScalarTypeFields() throws {
    let input = """
      message Test {
      	double d = 1;
      	float f = 2;
      	int32 i32 = 3;
      	int64 i64 = 4;
      	uint32 u32 = 5;
      	uint64 u64 = 6;
      	sint32 s32 = 7;
      	sint64 s64 = 8;
      	fixed32 f32 = 9;
      	fixed64 f64 = 10;
      	sfixed32 sf32 = 11;
      	sfixed64 sf64 = 12;
      	bool b = 13;
      	string s = 14;
      	bytes by = 15;
      }
      """
    let file = try parse(input)
    let fields = file.messages[0].fields
    XCTAssertEqual(fields.count, 15)

    // Verify each field type
    if case .scalar(let type) = fields[0].type {
      XCTAssertEqual(type, .double)
    }
    // ... verify other types
  }

  func testRepeatedFields() throws {
    let input = """
      message Test {
      	repeated string names = 1;
      	repeated int32 numbers = 2;
      	repeated Test nested = 3;
      }
      """
    let file = try parse(input)
    let fields = file.messages[0].fields
    XCTAssertTrue(fields.allSatisfy { $0.isRepeated })
  }

  func testFieldOptions() throws {
    let input = """
      message Test {
      	string name = 1 [deprecated = true];
      	int32 id = 2 [packed = true, json_name = "identifier"];
      	bool active = 3 [(custom.option) = "value"];
      }
      """
    let file = try parse(input)
    let fields = file.messages[0].fields
    XCTAssertFalse(fields[0].options.isEmpty)
    XCTAssertEqual(fields[1].options.count, 2)
  }

  func testInvalidFieldNames() throws {
    let inputs = [
      "message Test { string 123field = 1; }",
      "message Test { string Field = 1; }",
      "message Test { string field-name = 1; }",
      "message Test { string field.name = 1; }",
    ]

    for input in inputs {
      XCTAssertThrowsError(try parse(input))
    }
  }

  func testReservedFieldNumbers() throws {
    let input = """
      message Test {
      	reserved 2, 4, 6;
      	string name = 2;  // Should fail
      }
      """
    XCTAssertThrowsError(try parse(input))
  }

  func testReservedFieldNames() throws {
    let input = """
      message Test {
      	reserved "foo", "bar";
      	string foo = 1;  // Should fail
      }
      """
    XCTAssertThrowsError(try parse(input))
  }

  func testCustomTypeFields() throws {
    let input = """
      message Test {
      	OtherMessage other = 1;
      	nested.Message nested = 2;
      	.fully.qualified.Type qualified = 3;
      }
      """
    let file = try parse(input)
    let fields = file.messages[0].fields

    for field in fields {
      if case .named = field.type {
        // Custom type verified
      } else {
        XCTFail("Expected named type")
      }
    }
  }

  func testMapFieldKeyTypes() throws {
    let validInputs = [
      "map<int32, string>",
      "map<int64, string>",
      "map<uint32, string>",
      "map<uint64, string>",
      "map<sint32, string>",
      "map<sint64, string>",
      "map<fixed32, string>",
      "map<fixed64, string>",
      "map<sfixed32, string>",
      "map<sfixed64, string>",
      "map<bool, string>",
      "map<string, string>",
    ]

    let invalidInputs = [
      "map<float, string>",
      "map<double, string>",
      "map<bytes, string>",
      "map<CustomType, string>",
      "map<repeated string, string>",
    ]

    for input in validInputs {
      let testInput = "message Test { \(input) field = 1; }"
      XCTAssertNoThrow(try parse(testInput))
    }

    for input in invalidInputs {
      let testInput = "message Test { \(input) field = 1; }"
      XCTAssertThrowsError(try parse(testInput))
    }
  }

  func testMapFieldValidation() throws {
    let invalidInputs = [
      "message Test { repeated map<string, string> field = 1; }",  // Cannot be repeated
      "message Test { map<string> field = 1; }",  // Missing value type
      "message Test { map<string, oneof> field = 1; }",  // Invalid value type
      "message Test { map<map<string, string>, string> field = 1; }",  // Nested maps
    ]

    for input in invalidInputs {
      XCTAssertThrowsError(try parse(input))
    }
  }

  // MARK: - Enum Tests

  func testBasicEnum() throws {
    let input = """
      enum Status {
      	STATUS_UNKNOWN = 0;
      	STATUS_ACTIVE = 1;
      	STATUS_INACTIVE = 2;
      }
      """

    let file = try parse(input)
    let firstEnum = file.enums[0]

    XCTAssertEqual(firstEnum.values.count, 3)
    XCTAssertEqual(firstEnum.values[0].number, 0)
  }

  func testEnumAllowAlias() throws {
    let input = """
      enum Alias {
      	option allow_alias = true;
      	UNKNOWN = 0;
      	STARTED = 1;
      	RUNNING = 1;  // Alias
      }
      """
    let file = try parse(input)
    XCTAssertEqual(file.enums[0].values.count, 3)
  }

  func testEnumFirstValueNotZero() throws {
    let input = """
      enum Invalid {
      	FIRST = 1;
      }
      """
    XCTAssertThrowsError(try parse(input))
  }

  func testDuplicateEnumValues() throws {
    let input = """
      enum Duplicate {
      	UNKNOWN = 0;
      	FIRST = 1;
      	SECOND = 1;  // Should fail without allow_alias
      }
      """
    XCTAssertThrowsError(try parse(input))
  }

  func testEnumValueOptions() throws {
    let input = """
      enum Test {
      	UNKNOWN = 0;
      	FIRST = 1 [deprecated = true];
      	SECOND = 2 [(custom_option) = "value"];
      }
      """
    let file = try parse(input)
    let values = file.enums[0].values
    XCTAssertFalse(values[1].options.isEmpty)
    XCTAssertFalse(values[2].options.isEmpty)
  }

  func testInvalidEnumNames() throws {
    let inputs = [
      "enum 123test {}",
      "enum test {}",  // Must start uppercase
      "enum Test$Name {}",
      "enum Test.Name {}",
    ]
    for input in inputs {
      XCTAssertThrowsError(try parse(input))
    }
  }

  func testReservedEnumValues() throws {
    let input = """
      enum Test {
      	reserved 2, 15, 9 to 11;
      	reserved "FOO", "BAR";
      	UNKNOWN = 0;
      	FOO = 2;  // Should fail
      }
      """
    XCTAssertThrowsError(try parse(input))
  }

  func testNestedEnums() throws {
    let input = """
      message Container {
      	enum Status {
      		UNKNOWN = 0;
      		ACTIVE = 1;
      	}
      	Status status = 1;
      }
      """
    let file = try parse(input)
    XCTAssertEqual(file.messages[0].enums.count, 1)
  }

  func testEmptyEnum() throws {
    let input = "enum Empty {}"
    XCTAssertThrowsError(try parse(input))
  }

  // MARK: - Service Tests

  func testBasicService() throws {
    let input = """
      service Greeter {
      	rpc SayHello (HelloRequest) returns (HelloResponse);
      }
      """
    let file = try parse(input)
    let service = file.services[0]
    XCTAssertEqual(service.rpcs.count, 1)
    XCTAssertEqual(service.rpcs[0].name, "SayHello")
    XCTAssertFalse(service.rpcs[0].clientStreaming)
    XCTAssertFalse(service.rpcs[0].serverStreaming)
  }

  func testStreamingRPC() throws {
    let input = """
      service StreamService {
      	rpc ClientStream (stream Request) returns (Response);
      	rpc ServerStream (Request) returns (stream Response);
      	rpc BidiStream (stream Request) returns (stream Response);
      }
      """
    let file = try parse(input)
    let service = file.services[0]
    XCTAssertTrue(service.rpcs[0].clientStreaming)
    XCTAssertTrue(service.rpcs[1].serverStreaming)
    XCTAssertTrue(service.rpcs[2].clientStreaming && service.rpcs[2].serverStreaming)
  }

  func testServiceOptions() throws {
    let input = """
      service Test {
      	option deprecated = true;
      	option (custom.option) = "value";
      	rpc Method (Request) returns (Response);
      }
      """
    let file = try parse(input)
    XCTAssertFalse(file.services[0].options.isEmpty)
  }

  func testRPCOptions() throws {
    let input = """
      service Test {
      	rpc Method (Request) returns (Response) {
      		option deprecated = true;
      		option idempotency_level = IDEMPOTENT;
      	}
      }
      """
    let file = try parse(input)
    XCTAssertFalse(file.services[0].rpcs[0].options.isEmpty)
  }

  func testInvalidServiceName() throws {
    let inputs = [
      "service 123test {}",
      "service test {}",  // Must start uppercase
      "service Test$Name {}",
      "service Test.Name {}",
    ]
    for input in inputs {
      XCTAssertThrowsError(try parse(input))
    }
  }

  func testInvalidMethodName() throws {
    let inputs = [
      "rpc 123method",
      "rpc method",  // Must start uppercase
      "rpc Method$Name",
      "rpc Method.Name",
    ]
    for name in inputs {
      let input = """
        service Test {
        	\(name) (Request) returns (Response);
        }
        """
      XCTAssertThrowsError(try parse(input))
    }
  }

  func testEmptyService() throws {
    let input = "service Empty {}"
    let file = try parse(input)
    XCTAssertTrue(file.services[0].rpcs.isEmpty)
  }

  func testInvalidStreamDeclaration() throws {
    let inputs = [
      "rpc Method (stream) returns (Response);",
      "rpc Method (Request) returns (stream);",
      "rpc Method (stream stream Request) returns (Response);",
      "rpc Method (Request) returns (stream stream Response);",
    ]
    for rpc in inputs {
      let input = """
        service Test {
        	\(rpc)
        }
        """
      XCTAssertThrowsError(try parse(input))
    }
  }

  func testMissingTypes() throws {
    let inputs = [
      "rpc Method () returns (Response);",
      "rpc Method (Request) returns ();",
      "rpc Method (stream) returns (Response);",
      "rpc Method (Request) returns (stream);",
    ]
    for rpc in inputs {
      let input = """
        service Test {
        	\(rpc)
        }
        """
      XCTAssertThrowsError(try parse(input))
    }
  }

  // MARK: - Option Tests

  func testFileOptions() throws {
    let input = """
      syntax = "proto3";
      option java_package = "com.example.foo";
      option java_outer_classname = "Foo";
      option optimize_for = SPEED;
      option go_package = "foo";
      option (custom.file_option) = true;
      """
    let file = try parse(input)
    XCTAssertEqual(file.options.count, 5)
  }

  func testMessageOptions() throws {
    let input = """
      message Test {
      	option message_set_wire_format = true;
      	option deprecated = true;
      	option (custom.message_option) = "value";
      	string name = 1;
      }
      """
    let file = try parse(input)
    XCTAssertEqual(file.messages[0].options.count, 3)
  }

  func testNestedOptions() throws {
    let input = """
      option (my_option) = {
      	string_field: "hello"
      	int_field: 42
      	nested_field: {
      		a: 1
      		b: 2
      	}
      };
      """
    let file = try parse(input)
    let option = file.options[0]
    if case .map(let fields) = option.value {
      XCTAssertEqual(fields.count, 3)
    } else {
      XCTFail("Expected map value")
    }
  }

  func testArrayOptionValue() throws {
    let input = """
      message Test {
      	string name = 1 [(custom.list) = ["a", "b", "c"]];
      }
      """
    let file = try parse(input)
    let option = file.messages[0].fields[0].options[0]
    if case .array(let values) = option.value {
      XCTAssertEqual(values.count, 3)
    } else {
      XCTFail("Expected array value")
    }
  }

  func testInvalidOptionNames() throws {
    let inputs = [
      "option 123invalid = true;",
      "option (123.invalid) = true;",
      "option (.invalid) = true;",
      "option (invalid.) = true;",
    ]
    for input in inputs {
      XCTAssertThrowsError(try parse(input))
    }
  }

  func testDuplicateOptions() throws {
    let input = """
      option java_package = "first";
      option java_package = "second";
      """
    XCTAssertThrowsError(try parse(input))
  }

  func testInvalidOptionValues() throws {
    let inputs = [
      "option bool_option = 123;",
      "option string_option = true;",
      "option enum_option = \"wrong\";",
    ]
    for input in inputs {
      XCTAssertThrowsError(try parse(input))
    }
  }

  func testIncompleteOptions() throws {
    let inputs = [
      "option = true;",
      "option name =;",
      "option name true;",
      "option (custom.) = true;",
      "option (.custom) = true;",
    ]
    for input in inputs {
      XCTAssertThrowsError(try parse(input))
    }
  }

  // MARK: - Corner Cases Tests

  func testLongIdentifiers() throws {
    let longName = String(repeating: "a", count: 1000)
    let input = """
      message \(longName) {
      	string \(longName) = 1;
      }
      """
    let file = try parse(input)
    XCTAssertEqual(file.messages[0].name, longName)
    XCTAssertEqual(file.messages[0].fields[0].name, longName)
  }

  func testMaxNestingDepth() throws {
    var input = "message M1 {"
    for i in 2...100 {
      input += "message M\(i) {"
    }
    input += String(repeating: "}", count: 100)

    XCTAssertThrowsError(try parse(input))
  }

  func testComplexTypeReferences() throws {
    let input = """
      message Test {
      	.foo.bar.Baz field1 = 1;
      	foo.bar.Baz field2 = 2;
      	Baz field3 = 3;
      	.Baz field4 = 4;
      }
      """
    let file = try parse(input)
    let fields = file.messages[0].fields
    XCTAssertEqual(fields.count, 4)
    for field in fields {
      if case .named = field.type {
        // Type reference verified
      } else {
        XCTFail("Expected named type")
      }
    }
  }

  func testCircularDependencies() throws {
    let input = """
      message A {
      	B b = 1;
      }
      message B {
      	A a = 1;
      }
      """
    let file = try parse(input)
    XCTAssertEqual(file.messages.count, 2)
  }

  func testNameCollisions() throws {
    let inputs = [
      // Same name for different types
      """
      message Test {}
      enum Test {}
      """,
      // Same name in different scopes
      """
      message Outer {
      	message Inner {}
      	enum Inner {}
      }
      """,
      // Same name field in message
      """
      message Test {
      	string name = 1;
      	int32 name = 2;
      }
      """,
    ]

    for input in inputs {
      XCTAssertThrowsError(try parse(input))
    }
  }

  func testUnicodeInNames() throws {
    let inputs = [
      "message 测试 {}",
      "message Test { string 名前 = 1; }",
      "enum テスト {}",
    ]

    for input in inputs {
      XCTAssertThrowsError(try parse(input))
    }
  }

  func testEmptyBlocks() throws {
    let input = """
      message Test {
      	oneof test {}
      	message Empty {}
      	enum Status {}
      }
      """
    XCTAssertThrowsError(try parse(input))
  }

  func testWhitespaceHandling() throws {
    let input = """
      message\tTest\t{\n
      	string\t\tname\t=\t1\t;\n
      	int32\t\tid\t=\t2\t;\n
      }\n
      """
    let file = try parse(input)
    XCTAssertEqual(file.messages[0].fields.count, 2)
  }

  func testIncompleteInput() throws {
    let inputs = [
      "message Test {",
      "enum Status {",
      "service Test {",
      "message Test { string name = ",
      "message Test { oneof test {",
      "message Test { map<string,",
    ]

    for input in inputs {
      XCTAssertThrowsError(try parse(input))
    }
  }
}