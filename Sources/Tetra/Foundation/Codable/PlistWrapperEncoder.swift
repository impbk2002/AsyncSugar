//
//  PlistWrapperEncoder.swift
//  
//
//  Created by pbk on 2023/05/27.
//

import Foundation
import Combine

public struct PlistWrapperEncoder: TopLevelEncoder {
    
    public var userInfo: [CodingUserInfoKey : Any] = [:]
    
    public init() {
        
    }
    
    public func encode<T>(_ value: T) throws -> PlistWrapper where T : Encodable {
        let container = PlistReference.emptyContainer
        try value.encode(to: EncoderImp(codingPath: [], userInfo: userInfo, ref: container) )
        defer { container.backing = nil }
        switch container.unwrap() {
        case .none:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Top-level \(T.self) did not encode any values."
                )
            )
        case .some(let value):
            return value
        }
        
    }
    
    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, macOS 12, *)
    func encode<T>(_ value: T, configuration: T.EncodingConfiguration) throws -> PlistWrapper where T : EncodableWithConfiguration {
        let container = PlistReference.emptyContainer
        try value.encode(to: EncoderImp(codingPath: [], userInfo: userInfo, ref: container), configuration: configuration)
        defer { container.backing = nil }
        switch container.unwrap() {
        case .none:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Top-level \(T.self) did not encode any values."
                )
            )
        case .some(let value):
            return value
        }
    }

    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macCatalyst 15.0, macOS 12, *)
    func encode<T, C>(_ value: T, configuration: C.Type) throws -> PlistWrapper where T : EncodableWithConfiguration, C : EncodingConfigurationProviding, T.EncodingConfiguration == C.EncodingConfiguration {
        try encode(value, configuration: configuration.encodingConfiguration)
    }
    
}

extension PlistWrapperEncoder {
    
    
    struct EncoderImp {
        
        let codingPath:[CodingKey]
        let userInfo:[CodingUserInfoKey:Any]
        let ref:PlistReference
        
    }
    
    struct SingleEncoder {
        
        let codingPath:[CodingKey]
        let userInfo:[CodingUserInfoKey:Any]
        let ref:PlistReference
        
    }
    
    struct KeyedEncoder<Key:CodingKey> {
        
        let codingPath:[CodingKey]
        let userInfo:[CodingUserInfoKey:Any]
        let ref:PlistReference
        
    }
    
    struct UnkeyedEncoder {
        
        let codingPath:[CodingKey]
        let userInfo:[CodingUserInfoKey:Any]
        let ref:PlistReference
        
    }
    
}

extension PlistWrapperEncoder.EncoderImp: Encoder {
    
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        switch ref.backing {
        case .none:
            ref.backing = .dictionary([:])
            let container = PlistWrapperEncoder.KeyedEncoder<Key>(codingPath: codingPath, userInfo: userInfo, ref: ref)
            return .init(container)
            // inflate encoded dictionary back to keyed container
        case .primitive(.object(let dictionary)):
            ref.backing = .dictionary(dictionary.mapValues{ PlistReference(.primitive($0))})
            fallthrough
        case .dictionary(_):
            let container = PlistWrapperEncoder.KeyedEncoder<Key>(codingPath: codingPath, userInfo: userInfo, ref: ref)
            return .init(container)
        default:
            let context = EncodingError.Context(codingPath: codingPath, debugDescription: "Attempt to create new keyed encoding container when already previously encoded at this path.")
            return .init(InvalidKeyedEncodingContainer(context: context, codingPath: codingPath))
        }
    }
    
    func unkeyedContainer() -> UnkeyedEncodingContainer {
        switch ref.backing {
        case .none:
            ref.backing = .array([])
            return PlistWrapperEncoder.UnkeyedEncoder(codingPath: codingPath, userInfo: userInfo, ref: ref)
            // inflate back to unkeyed container
        case .primitive(.array(let encoded)):
            ref.backing = .array(encoded.map{ PlistReference(.primitive($0))})
            fallthrough
        case .array(_):
            return PlistWrapperEncoder.UnkeyedEncoder(codingPath: codingPath, userInfo: userInfo, ref: ref)
        default:
            let context = EncodingError.Context(codingPath: codingPath, debugDescription: "Attempt to create new unkeyed encoding container when already previously encoded at this path.")
            return InvalidUnkeyedEncodingContainer(context: context, codingPath: codingPath)
        }
    }
    
    func singleValueContainer() -> SingleValueEncodingContainer {
        if ref.backing != nil {
            let context = EncodingError.Context(codingPath: codingPath, debugDescription: "Attempt to create new single encoding container when already previously encoded at this path.")
            return InvalidSingleEncodingContainer(context: context, codingPath: codingPath)
        }
        return PlistWrapperEncoder.SingleEncoder(codingPath: codingPath, userInfo: userInfo, ref: ref)
    }
    
    
}

extension PlistWrapperEncoder.SingleEncoder: SingleValueEncodingContainer {
    
    private func assertCanEncodeNewValue() {
        precondition(ref.backing == nil, "Attempt to encode value through single value container when previously value already encoded.")
    }
    
    func encodeNil() throws {
        throw EncodingError.invalidValue(Never.self, .init(codingPath: codingPath, debugDescription: "null is not allowed in propertylist"))
    }
    
    func encode(_ value: Bool) throws {
        assertCanEncodeNewValue()
        ref.backing = .primitive(.bool(value))
    }
    
    func encode(_ value: String) throws {
        assertCanEncodeNewValue()
        ref.backing = .primitive(.string(value))
    }
    
    func encode(_ value: Double) throws {
        assertCanEncodeNewValue()
        ref.backing = .primitive(.double(value))
    }
    
    func encode(_ value: Float) throws {
        try encode(value.isSignalingNaN ? .signalingNaN : Double(value))
    }
    
    func encode(_ value: Int) throws {
        assertCanEncodeNewValue()
        ref.backing = .primitive(.integer(value))
    }
    
    func encode(_ value: Int8) throws {
        try encode(Int(value))
    }
    
    func encode(_ value: Int16) throws {
        try encode(Int(value))
    }
    
    func encode(_ value: Int32) throws {
        try encode(Int(value))
    }
    
    func encode(_ value: Int64) throws {
        try encode(Int(value))
    }
    
    func encode(_ value: UInt) throws {
        try encode(Int(value))
    }
    
    func encode(_ value: UInt8) throws {
        try encode(Int(value))
    }
    
    func encode(_ value: UInt16) throws {
        try encode(Int(value))
    }
    
    func encode(_ value: UInt32) throws {
        try encode(Int(value))
    }
    
    func encode(_ value: UInt64) throws {
        try encode(Int(value))
    }
    
    func encode<T>(_ value: T) throws where T : Encodable {
        assertCanEncodeNewValue()
        switch value {
        case let v as Data:
            ref.backing = .primitive(.data(v))
        case let v as Date:
            ref.backing = .primitive(.date(v))
        case let v as PlistWrapper:
            ref.backing = .primitive(v)
        case let v as [PlistWrapper]:
            ref.backing = .primitive(.array(v))
        case let v as [String:PlistWrapper]:
            ref.backing = .primitive(.object(v))
        default:
            let container = PlistWrapperEncoder.EncoderImp(codingPath: codingPath, userInfo: userInfo, ref: ref)
            try value.encode(to: container)
            
        }
       
    }
    
}

extension PlistWrapperEncoder.KeyedEncoder: KeyedEncodingContainerProtocol {
    
    func encodeNil(forKey key: Key) throws {
        throw EncodingError.invalidValue(Never.self, .init(codingPath: codingPath + [key], debugDescription: "null is not allowed in propertyList"))
    }
    
    func encode<T>(_ value: T, forKey key: Key) throws where T : Encodable {
        let newRef = PlistReference.emptyContainer
        let container = PlistWrapperEncoder.SingleEncoder(codingPath: codingPath + [key], userInfo: userInfo, ref: newRef)
        try container.encode(value)
        switch newRef.unwrap() {
        case .none:
            break
        case .some(let value):
            insert(.init(.primitive(value)), for: key.stringValue)
        }
    }
    
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        let newRef = PlistReference.emptyObject
        let container = PlistWrapperEncoder.KeyedEncoder<NestedKey>(codingPath: codingPath + [key], userInfo: userInfo, ref: newRef)
        insert(newRef, for: key.stringValue)
        return .init(container)
    }
    
    func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        let newREf = PlistReference.emptyArray
        let container = PlistWrapperEncoder.UnkeyedEncoder(codingPath: codingPath + [key], userInfo: userInfo, ref: newREf)
        insert(newREf, for: key.stringValue)
        return container
    }
    
    func superEncoder() -> Encoder {
        let newRef = PlistReference.emptyContainer
        let container = PlistWrapperEncoder.EncoderImp(codingPath: codingPath + [TetraCodingKey.super], userInfo: userInfo, ref: newRef)
        insert(newRef, for: TetraCodingKey.super.stringValue)
        return container
    }
    
    func superEncoder(forKey key: Key) -> Encoder {
        let newRef = PlistReference.emptyContainer
        let container = PlistWrapperEncoder.EncoderImp(codingPath: codingPath + [key], userInfo: userInfo, ref: newRef)
        insert(newRef, for: key.stringValue)
        return container
    }
    
    @inline(__always)
    func insert(_ newValue: PlistReference, for key: String) {
        guard case .dictionary(var object) = self.ref.backing else {
            preconditionFailure("Wrong underlying PropertyList reference type")
        }
        object[key] = newValue
        ref.backing = .dictionary(object)
    }
    
}

extension PlistWrapperEncoder.KeyedEncoder {
    
    func encode(_ value: Bool, forKey key: Key) throws {
        insert(.bool(value), for: key.stringValue)
    }

    func encode(_ value: String, forKey key: Key) throws {
        insert(.string(value), for: key.stringValue)
    }

    func encode(_ value: Double, forKey key: Key) throws {
        insert(.float(value), for: key.stringValue)
    }

    func encode(_ value: Float, forKey key: Key) throws {
        insert(.float(value.isSignalingNaN ? .signalingNaN : Double(value)), for: key.stringValue)
    }

    func encode(_ value: Int, forKey key: Key) throws {
        insert(.integer(value), for: key.stringValue)
    }

    func encode(_ value: Int8, forKey key: Key) throws {
        try encode(Int(value), forKey: key)
    }

    func encode(_ value: Int16, forKey key: Key) throws {
        try encode(Int(value), forKey: key)
    }

    func encode(_ value: Int32, forKey key: Key) throws {
        try encode(Int(value), forKey: key)
    }

    func encode(_ value: Int64, forKey key: Key) throws {
        try encode(Int(value), forKey: key)
    }

    func encode(_ value: UInt, forKey key: Key) throws {
        try encode(Int(value), forKey: key)
    }

    func encode(_ value: UInt8, forKey key: Key) throws {
        try encode(Int(value), forKey: key)
    }

    func encode(_ value: UInt16, forKey key: Key) throws {
        try encode(Int(value), forKey: key)
    }

    func encode(_ value: UInt32, forKey key: Key) throws {
        try encode(Int(value), forKey: key)
    }

    func encode(_ value: UInt64, forKey key: Key) throws {
        try encode(Int(value), forKey: key)
    }
}

extension PlistWrapperEncoder.UnkeyedEncoder: UnkeyedEncodingContainer {
    
    var count: Int {
        guard case let .array(array) = ref.backing else {
            preconditionFailure("Wrong underlying PropertyList reference type to evaluate count")
        }
        return array.count
    }
    
    func encodeNil() throws {
        throw EncodingError.invalidValue(Never.self, .init(codingPath: codingPath + [TetraCodingKey(index: count)], debugDescription: "null is not allowed in propertyList"))
    }
    
    mutating func encode<T>(_ value: T) throws where T : Encodable {
        let newRef = PlistReference.emptyContainer
        let container = PlistWrapperEncoder.SingleEncoder(codingPath: codingPath + [TetraCodingKey(index: count)], userInfo: userInfo, ref: newRef)
        try container.encode(value)
        guard let value = newRef.unwrap() else { return }
        insert(.init(.primitive(value)))
    }
    
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        let newRef = PlistReference.emptyObject
        let container = PlistWrapperEncoder.KeyedEncoder<NestedKey>(codingPath: codingPath + [TetraCodingKey(index: count)], userInfo: userInfo, ref: newRef)
        insert(newRef)
        return .init(container)
    }
    
    func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let newRef = PlistReference.emptyArray
        let container = PlistWrapperEncoder.UnkeyedEncoder(codingPath: codingPath + [TetraCodingKey(index: count)], userInfo: userInfo, ref: newRef)
        insert(newRef)
        return container
    }
    
    func superEncoder() -> Encoder {
        let newRef = PlistReference.emptyContainer
        let container = PlistWrapperEncoder.EncoderImp(codingPath: codingPath + [TetraCodingKey(index: count)], userInfo: userInfo, ref: newRef)
        insert(newRef)
        return container
    }
    
    
    @inline(__always)
    func insert(_ newValue: PlistReference) {
        guard case .array(var array) = self.ref.backing else {
            preconditionFailure("Wrong underlying PropertyList reference type")
        }
        array.append(newValue)
        ref.backing = .array(array)
    }
    
}

extension PlistWrapperEncoder.UnkeyedEncoder {
    
    func encode(_ value: String) throws {
        insert(.string(value))
    }

    func encode(_ value: Double) throws {
        insert(.float(value))
    }

    func encode(_ value: Float) throws {
        try encode(value.isSignalingNaN ? .signalingNaN : Double(value))
    }

    func encode(_ value: Int) throws {
        insert(.integer(value))
    }

    func encode(_ value: Int8) throws {
        try encode(Int(value))
    }

    func encode(_ value: Int16) throws {
        try encode(Int(value))
    }

    func encode(_ value: Int32) throws {
        try encode(Int(value))
    }

    func encode(_ value: Int64) throws {
        try encode(Int(value))
    }

    func encode(_ value: UInt) throws {
        try encode(Int(value))
    }

    func encode(_ value: UInt8) throws {
        try encode(Int(value))
    }

    func encode(_ value: UInt16) throws {
        try encode(Int(value))
    }

    func encode(_ value: UInt32) throws {
        try encode(Int(value))
    }

    func encode(_ value: UInt64) throws {
        try encode(Int(value))
    }

    func encode(_ value: Bool) throws {
        insert(.bool(value))
    }
    
}

final class PlistReference {
    
    enum Backing {
        
        case primitive(PlistWrapper)
        case array([PlistReference])
        case dictionary([String:PlistReference])
    }
    
    var backing:Backing?
    
    @inline(__always)
    init(_ backing: Backing) {
        self.backing = backing
    }
    
    static var emptyContainer: PlistReference {
        let item = PlistReference.init(.array([]))
        item.backing = nil
        return item
    }
    
    static func bool(_ b: Bool) -> PlistReference { .init(.primitive(.bool(b))) }
    static var emptyArray : PlistReference { .init(.array([])) }
    static var emptyObject : PlistReference { .init(.dictionary([:])) }
    static func string(_ str: String) -> PlistReference { .init(.primitive(.string(str))) }
    static func integer<T:FixedWidthInteger>(_ str: T) -> PlistReference { .init(.primitive(.integer(Int(str)))) }
    static func float<T:BinaryFloatingPoint>(_ number:T) -> PlistReference { .init(.primitive(.double(number.isSignalingNaN ? .signalingNaN : Double(number))))}
    
    func unwrap() -> PlistWrapper? {
        switch backing {
        case .none:
            return nil
        case .primitive(let value):
            return value
        case .dictionary(let dictionary):
            return .object(dictionary.compactMapValues{ $0.unwrap() })
        case .array(let array):
            return .array(array.compactMap{ $0.unwrap() })
        }
    }
    
}
