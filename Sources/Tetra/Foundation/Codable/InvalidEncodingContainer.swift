//
//  File.swift
//  
//
//  Created by 박병관 on 5/5/24.
//

import Foundation

struct InvalidEncoder: Encoder {
    //    context where actual invalid behavior happen
    let context:EncodingError.Context
    var codingPath: [any CodingKey]
    
    var userInfo: [CodingUserInfoKey : Any] { [:]}
    
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key : CodingKey {
        return .init(InvalidKeyedEncodingContainer(context: context, codingPath: codingPath))
    }
    
    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        return InvalidUnkeyedEncodingContainer(context: context, codingPath: codingPath)
    }
    
    func singleValueContainer() -> any SingleValueEncodingContainer {
        return InvalidSingleEncodingContainer(context: context, codingPath: codingPath)
    }
    
}

struct InvalidSingleEncodingContainer: SingleValueEncodingContainer  {
    //    context where actual invalid behavior happen
    let context:EncodingError.Context
    var codingPath: [any CodingKey]
    
    func encodeNil() throws {
        throw EncodingError.invalidValue(Optional<Any>.none as Any, context)
    }

    func encode<T>(_ value: T) throws where T : Encodable {
        throw EncodingError.invalidValue(value, context)
    }
}

struct InvalidUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    //    context where actual invalid behavior happen
    let context:EncodingError.Context
    var codingPath: [any CodingKey]
    
    var count: Int { 0 }
    
    func encodeNil() throws {
        throw EncodingError.invalidValue(Optional<Any>.none as Any, context)
    }
    
    func encode<T>(_ value: T) throws where T : Encodable {
        throw EncodingError.invalidValue(value, context)
    }
    
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        return .init(InvalidKeyedEncodingContainer(context: context, codingPath: codingPath))
    }
    
    func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        return self
    }
    
    func superEncoder() -> any Encoder {
        return InvalidEncoder(context: context, codingPath: codingPath + [TetraCodingKey.super])
    }
    
}

struct InvalidKeyedEncodingContainer<Key:CodingKey>: KeyedEncodingContainerProtocol {
    let context:EncodingError.Context
    var codingPath: [any CodingKey]
    
    func encodeNil(forKey key: Key) throws {
        throw EncodingError.invalidValue(Optional<Any>.none as Any, context)
    }
    
    func encode<T>(_ value: T, forKey key: Key) throws where T : Encodable {
        throw EncodingError.invalidValue(value, context)
    }
    
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        return .init(InvalidKeyedEncodingContainer<NestedKey>(context: context, codingPath: codingPath + [key]))
    }
    
    func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        return InvalidUnkeyedEncodingContainer(context: context, codingPath: codingPath + [key])
    }
    
    func superEncoder() -> any Encoder {
        return InvalidEncoder(context: context, codingPath: codingPath + [TetraCodingKey.super])
    }
    
    func superEncoder(forKey key: Key) -> any Encoder {
        return InvalidEncoder(context: context, codingPath: codingPath + [key])
    }
    
}


