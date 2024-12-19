//
//  LegacyTypedAsyncSequence.swift
//  
//
//  Created by 박병관 on 6/15/24.
//

public struct LegacyTypedAsyncSequence<Base:AsyncSequence> {
    
    @usableFromInline
    let base:Base
    

    @inlinable
    public init(base: Base) {
        self.base = base
    }

    
}

extension LegacyTypedAsyncSequence: AsyncSequence, TypedAsyncSequence {
    
    
    public typealias Failure = any Error
    public typealias Element = Base.Element
    
    @inlinable
    public func makeAsyncIterator() -> Iterator {
        return Iterator(baseIterator: base.makeAsyncIterator())
    }
    
    
    public struct Iterator {
        
        @usableFromInline
        package var baseIterator:Base.AsyncIterator
        

        @inlinable
        public init(baseIterator: Base.AsyncIterator) {
            self.baseIterator = baseIterator
        }
        
    }
    
}


extension LegacyTypedAsyncSequence.Iterator: AsyncIteratorProtocol, TypedAsyncIteratorProtocol {
    
    public typealias Element = Base.Element
    public typealias Failure = any Error
    
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Failure) -> Element? {
        if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
            return try await baseIterator.next(isolation: actor)
        } else {
            nonisolated(unsafe)
            var iter = self
            do {
                let value = try await iter.advance()?.base
                self = iter
                return value
            } catch {
                self = iter
                throw error
            }
        }
    }
    
    @_disfavoredOverload
    @inlinable
    public mutating func next() async throws(Failure) -> Element? {
        try await baseIterator.next()
    }
    
    @inline(__always)
    @usableFromInline
    internal mutating func advance() async throws(Failure) -> Suppress<Element>? {
        guard let value = try await baseIterator.next() else { return nil }
        return .init(base: value)
    }
    
    
}

extension LegacyTypedAsyncSequence: Sendable where Base: Sendable, Base.Element: Sendable {}

extension LegacyTypedAsyncSequence.Iterator: Sendable where Base.AsyncIterator: Sendable, Base.Element: Sendable {}
