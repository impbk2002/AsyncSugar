//
//  Suppress.swift
//
//
//  Created by 박병관 on 6/11/24.
//

import Foundation

// just using to suppress sendable check for unsafe concurrent operation
@usableFromInline
struct Suppress<T>: @unchecked Sendable {
    
    @inline(__always)
    @usableFromInline
    var value:T
    
    @inline(__always)
    @usableFromInline
    init(value: T) {
        self.value = value
    }
    
}

extension AsyncIteratorProtocol {
    
    
    @usableFromInline
    mutating func advanceUnsafe() async throws -> sending Element? {
        nonisolated(unsafe)
        var unsafe = Suppress(value: self)
        defer { self = unsafe.value }
        return try await unsafe.value.next()
    }
    
}

extension Suppress where T: AsyncIteratorProtocol {
    
    @usableFromInline
    mutating func advanceUnsafe() async throws -> sending T.Element? {
        return try await value.next()
    }
    
}
