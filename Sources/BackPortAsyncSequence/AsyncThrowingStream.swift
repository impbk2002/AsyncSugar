//
//  AsyncThrowingStream.swift
//  
//
//  Created by 박병관 on 6/15/24.
//

public struct AsyncTypedThrowingStream<Element,Failure:Error> {
    
    @usableFromInline
    let base: AsyncThrowingStream<Element,Failure>
    

    @inlinable
    public init(base: AsyncThrowingStream<Element, Failure>) {
        self.base = base
    }
    
}

extension AsyncTypedThrowingStream: AsyncSequence, TypedAsyncSequence {
    
        
    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(baseIterator: base.makeAsyncIterator())
    }
    
    
    public struct Iterator {
        
        @usableFromInline
        var baseIterator:AsyncThrowingStream<Element,Failure>.AsyncIterator

        @inlinable
        public init(baseIterator: AsyncThrowingStream<Element, Failure>.AsyncIterator) {
            self.baseIterator = baseIterator
        }
        

    }
    
}

extension AsyncTypedThrowingStream.Iterator: AsyncIteratorProtocol, TypedAsyncIteratorProtocol {
    
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Failure) -> Element? {
        if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
            return try await baseIterator.next(isolation: actor)
        } else {
            nonisolated(unsafe)
            var iter = self
            do {
                let value = try await iter.nextValue()
                self = iter
                return value
            } catch {
                self = iter
                throw (error as! Failure)
            }
        }
    }
    
    @_disfavoredOverload
    @inlinable
    public mutating func next() async throws(Failure) -> Element? {
        try await next(isolation: nil)
    }
    
    @inline(__always)
    @usableFromInline
    internal mutating func nextValue() async throws -> sending Element? {
        try await baseIterator.next()
    }
    
}

extension AsyncTypedThrowingStream: Sendable where Element: Sendable {}



