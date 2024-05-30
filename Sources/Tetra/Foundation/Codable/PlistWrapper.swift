//
//  PlistWrapper.swift
//  
//
//  Created by pbk on 2023/01/30.
//

import Foundation



/**
    Encodable Object specialized for propertyList,  which provides opportunity to mix general primitive types into single value.

    ```
        let wrapped:PlistWrapper = [
            "api_key":"unqiueKeys",
            "values": [["fruit":"apple", "cost":100.0], ["fruit":"banana", "cost":20.0],
            "codeNumber": 123,
            "isUser": false,
            "mixedArray":[false, 0, "asds", [1]]
        ]
        let data = try PropertyListEncoder().encode(wrapped)
        let decoded = try PlistWrapper(from: data)
 ```

    
 */
public enum PlistWrapper: Sendable {

    case bool(Bool)
    case data(Data)
    case date(Date)
    case string(String)
    case integer(Int)
    case double(Double)
    case array([Self])
    case object([String:Self])
    
}

extension PlistWrapper: Hashable {}

extension PlistWrapper: Encodable {
    
    @inlinable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .bool(value):
            try container.encode(value)
        case let .data(value):
            try container.encode(value)
        case let .date(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }
    
    @inlinable
    public init(unsafeObject: Any) throws {
        if PropertyListSerialization.propertyList([unsafeObject], isValidFor: .binary) {
            self = try Self.init(unsafeObject, path: [])
        } else if let value = unsafeObject as? Self {
            self = value
        } else {
            let context = DecodingError.Context(codingPath: [], debugDescription: "\(type(of: unsafeObject)) is not supported")
            throw DecodingError.dataCorrupted(context)
        }
    }
    
    @inlinable
    public func write(to stream:OutputStream, format: PropertyListSerialization.PropertyListFormat, options opt: PropertyListSerialization.WriteOptions) throws -> Int {
        var error:NSError? = nil
        let byteCount = PropertyListSerialization.writePropertyList(propertyObject, to: stream, format: format, options: opt, error: &error)
        if let error {
            throw error
        }
        return byteCount
    }
    
    @inlinable
    public func serialize(format: PropertyListSerialization.PropertyListFormat, options opt: PropertyListSerialization.WriteOptions) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: propertyObject, format: format, options: opt)
    }
    
    /// perform `PropertyListSerialization`and map the object into `PlistWrapper`
    /// - Parameters:
    ///   - data: A data object containing a serialized property list.
    ///   - opt: The options used to create the property list. For possible values, see PropertyListSerialization.MutabilityOptions.
    /// - Returns: the `PlistWrapper`
    /// - throws: `PropertyListSerialization` internal error if  `PropertyListSerialization` fails.  `DecodingError.typeMismatch`  if deserialized object contains unsupport type
    @inlinable
    public init(
        from data: Data,
        options opt: PropertyListSerialization.ReadOptions = [],
        format: PropertyListSerialization.PropertyListFormat? = nil
    ) throws {
        let topLevelRawObject:Any
        if let format {
            var formatRef = format
            topLevelRawObject = try PropertyListSerialization.propertyList(from: data, options: opt, format: &formatRef)
        } else {
            topLevelRawObject = try PropertyListSerialization.propertyList(from: data, options: opt, format: nil)
        }
        self = try PlistWrapper(topLevelRawObject, path: [])
    }
    
    /// perform `PropertyListSerialization`and map the object into `PlistWrapper`
    /// - Parameters:
    ///   - stream: An NSStream object. The stream should be open and configured for reading.
    ///   - opt: The options used to create the property list. For possible values, see PropertyListSerialization.MutabilityOptions.
    /// - Returns: the `PlistWrapper`
    /// - throws: `PropertyListSerialization` internal error if  `PropertyListSerialization` fails.  `DecodingError.typeMismatch` if deserialized object contains unsupport type
    @inlinable
    public init(
        from stream: InputStream,
        options opt: PropertyListSerialization.ReadOptions = [],
        format: PropertyListSerialization.PropertyListFormat? = nil
    ) throws {
        
        let topLevelRawObject:Any
        if let format {
            var formatRef = format
            topLevelRawObject = try PropertyListSerialization.propertyList(with: stream, options: opt, format: &formatRef)
        } else {
            topLevelRawObject = try PropertyListSerialization.propertyList(with: stream, options: opt, format: nil)
        }
        self = try PlistWrapper(topLevelRawObject, path: [])
    }
    
    @inlinable
    public static func transform(
        _ value: some Encodable, encoder: PropertyListEncoder = PropertyListEncoder()
    ) throws -> Self {
        switch value {
        case let object as Self:
            return object
        default:
            return try Self(from: encoder.encode(value))
        }
    }
    
}

// MARK: - Expressible Initializer
extension PlistWrapper: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral, CustomStringConvertible {
    
    @inlinable
    public init(stringLiteral value: StringLiteralType) {
        self = .string(value)
    }
    
    @inlinable
    public init(booleanLiteral value: BooleanLiteralType) {
        self = .bool(value)
    }
    
    @inlinable
    public init(integerLiteral value: IntegerLiteralType) {
        self = .integer(value)
    }
    
    @inlinable
    public init(floatLiteral value: FloatLiteralType) {
        self = .double(value)
    }
    
    @inlinable
    public init(dictionaryLiteral elements: (String, Self)...) {
        self = .object(.init(elements) { old, new in new })
    }
    
    @inlinable
    public init(arrayLiteral elements: Self...) {
        self = .array(elements)
    }
    
    @inlinable
    public var description: String {
        """
        \(Self.self)(\(propertyObject))
        """
    }
    
}

// MARK: - custom operator
public extension PlistWrapper {
    
    @inlinable
    var propertyObject:Any {
        switch self {
        case .bool(let bool):
            return bool
        case .string(let string):
            return string
        case .integer(let int):
            return int
        case .double(let double):
            return double
        case .array(let array):
            return array.map(\.propertyObject)
        case .object(let dictionary):
            return dictionary.mapValues(\.propertyObject)
        case .data(let value):
            return value
        case .date(let value):
            return value
        }
    }
    
    @inlinable
    subscript(_ key: String) -> Self? {
        get {
            switch self {
            case .object(let dictionary):
                return dictionary[key]
            default:
                return nil
            }
        }
    }
    
    @inlinable
    subscript(_ index: Int) -> Self? {
        get {
            switch self {
            case .array(let array) where array.indices.contains(index):
                return array[index]
            default:
                return nil
            }
        }
    }
    
    @inlinable
    var object:[String:Self]? {
        switch self {
        case .object(let object):
            return object
        default:
            return nil
        }
    }
    
    @inlinable
    var array:[Self]? {
        switch self {
        case .array(let array):
            return array
        default:
            return nil
        }
    }
    
    @inlinable
    var bool:Bool? {
        switch self {
        case .bool(let bool):
            return bool
        default:
            return nil
        }
    }
    
    @inlinable
    var integer:Int? {
        switch self {
        case .integer(let int):
            return int
        default:
            return nil
        }
    }
    
    @inlinable
    var string:String? {
        switch self {
        case .string(let string):
            return string
        default:
            return nil
        }
    }
    
    @inlinable
    var double:Double? {
        switch self {
        case .double(let double):
            return double
        default:
            return nil
        }
    }
    
    @inlinable
    var number:NSNumber? {
        switch self {
        case .bool(let bool):
            return bool as NSNumber
        case .integer(let int):
            return int as NSNumber
        case .double(let double):
            return double as NSNumber
        default:
            return nil
        }
    }
    
    @inlinable
    var date:Date? {
        switch self {
        case .date(let value):
            return value
        default:
            return nil
        }
    }
    
    @inlinable
    var data:Data? {
        switch self {
        case .data(let value):
            return value
        default:
            return nil
        }
    }
    
}

public extension PlistWrapper {
    
    @inlinable
    static func == (lhs: Self, rhs: Int) -> Bool {
        lhs.integer == rhs
    }
    
    @inlinable
    static func == (lhs: Self, rhs: Double) -> Bool {
        lhs.double == rhs
    }
    
    @inlinable
    static func == (lhs: Self, rhs: String) -> Bool {
        lhs.string == rhs
    }
    
    @inlinable
    static func == (lhs: Self, rhs: Bool) -> Bool {
        lhs.bool == rhs
    }
    
    @inlinable
    static func == (lhs: Self, rhs: [Self]) -> Bool {
        lhs.array == rhs
    }
    
    @inlinable
    static func == (lhs: Self, rhs: [String:Self]) -> Bool {
        lhs.object == rhs
    }
    
    @inlinable
    static func == (lhs: Self, rhs: Date) -> Bool {
        lhs.date == rhs
    }
    
    @inlinable
    static func == (lhs: Self, rhs: Data) -> Bool {
        lhs.data == rhs
    }
    
}

extension PlistWrapper: SerializableMappingProtocol {
    
    @usableFromInline
    init(_ deserializedValue: Any, path: [TetraCodingKey]) throws {
        switch deserializedValue {
        case let value as any FixedWidthInteger:
            self = .integer(Int(value))
        case let value as any BinaryFloatingPoint:
            self = .double(Double(value))
        case let value as NSNumber:
            if value.isBool {
                self = .bool(value.boolValue)
            } else if value.isReal {
                self = .double(value.doubleValue)
            } else {
                self = .integer(value.intValue)
            }
        case let value as String:
            self = .string(value)
        case let value as Date:
            self = .date(value)
        case let value as Data:
            self = .data(value)
        case let value as [Any]:
            var nestedContainer = [Self]()
            nestedContainer.reserveCapacity(value.capacity)
            try drillDownArray(value, &nestedContainer, path: path)
            self = .array(nestedContainer)
        case let value as [String: Any]:
            var nestedContainer = [String:Self](minimumCapacity: value.capacity)
            try drillDownDictionary(value, &nestedContainer, path: path)
            self = .object(nestedContainer)
        case let value as CFTypeRef where PropertyListSerialization.propertyList(value, isValidFor: .xml):
            // unknown CF Plist object possibly CFKeyedArchiverUID?
            let typeId = CFGetTypeID(value)
            let typeDescription = CFCopyTypeIDDescription(typeId) as String
//            let instanceDescription = CFCopyDescription(value) as String
            let context = DecodingError.Context(codingPath: path, debugDescription: "\(typeDescription) is not supported ")
            throw DecodingError.typeMismatch(Self.self, context)
        default:
            let context = DecodingError.Context(
                codingPath: path,
                debugDescription: "\(type(of: deserializedValue)) is not supported",
                underlyingError: nil
            )
            throw DecodingError.typeMismatch(Self.self, context)
        }
    }
    
}



internal extension PlistWrapper {
    
    @usableFromInline
    func typeMissmatchDescription(for type:Any.Type) -> String {
        let word:String
        switch self {
        case .bool(_):
            word = "Bool"
        case .string(_):
            word = "String"
        case .integer(_):
            word = "Int"
        case .double(_):
            word = "Double"
        case .array(_):
            word = "Array"
        case .object(_):
            word = "Dictionary"
        case .data(_):
            word = "Data"
        case .date(_):
            word = "Date"
        }
        return "Expected \(type) but found \(word) instead."
    }
    
}
