//
//  AsyncStream.swift
//  
//
//  Created by 박병관 on 6/15/24.
//

public struct AsyncTypedStream<Element> {
    
    @usableFromInline
    let base:AsyncStream<Element>
    
    @inlinable
    public init(base: AsyncStream<Element>) {
        self.base = base
    }
    
}

extension AsyncTypedStream: AsyncSequence, TypedAsyncSequence {
    
    public typealias Failure = Never
    
    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(baseIterator: base.makeAsyncIterator())
    }
    
    public struct Iterator {
        
        @usableFromInline
        var baseIterator:AsyncStream<Element>.AsyncIterator
        
        @inlinable
        public init(baseIterator: AsyncStream<Element>.AsyncIterator) {
            self.baseIterator = baseIterator
        }
        
    }
    
}

extension AsyncTypedStream.Iterator: AsyncIteratorProtocol, TypedAsyncIteratorProtocol {
    
    public typealias Failure = Never
    
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)? = #isolation) async -> Element? {
        if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
            return await baseIterator.next(isolation: actor)
        } else {
            nonisolated(unsafe)
            var iter = self
            defer {
                self = iter
            }
            let value = await iter.advanceNext()?.base
            return value
        }
    }
    
    @_disfavoredOverload
    @inlinable
    public mutating func next() async -> Element? {
        await baseIterator.next()
    }
    
    @inline(__always)
    @usableFromInline
//    @preconcurrency
    internal mutating func advanceNext() async -> sending Suppress<Element>? {
        guard let value = await baseIterator.next() else { return nil }
        return .init(base: value)
    }
    
}

extension AsyncTypedStream: Sendable where Element: Sendable {}

