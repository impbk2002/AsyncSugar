//
//  AsyncPrefixSequence.swift
//
//
//  Created by 박병관 on 6/14/24.
//

extension BackPort {
    
    
    public struct AsyncPrefixSequence<Base: AsyncSequence> where Base.AsyncIterator: TypedAsyncIteratorProtocol {
        @usableFromInline
        let base: Base
        
        @usableFromInline
        let count: Int
        
        @usableFromInline
        init(_ base: Base, count: Int) {
            precondition(count >= 0, "Can't prefix a negative number of elements from an async sequence")
            self.base = base
            self.count = count
        }
    }
    
}

extension BackPort.AsyncPrefixSequence: AsyncSequence, TypedAsyncSequence {
        
    public typealias Failure = AsyncIterator.Failure
    public typealias AsyncIterator = Iterator
    
    public struct Iterator {
        
        @usableFromInline
        var baseIterator: Base.AsyncIterator
        
        @usableFromInline
        var remaining: Int
        
        @usableFromInline
        init(_ baseIterator: Base.AsyncIterator, count: Int) {
            self.baseIterator = baseIterator
            self.remaining = count
        }
        
    }
    
    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(base.makeAsyncIterator(), count: count)
    }
    
}

extension BackPort.AsyncPrefixSequence.Iterator: AsyncIteratorProtocol, TypedAsyncIteratorProtocol {
    
    public typealias Element = Base.Element
    public typealias Failure = Base.AsyncIterator.Err
    
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Failure) -> Element? {
        if remaining != 0 {
            remaining &-= 1
            return try await baseIterator.next(isolation: actor)
        } else {
            return nil
        }
    }
    
    @_disfavoredOverload
    @inlinable
    public mutating func next() async throws(Failure) -> Element? {
        try await next(isolation: nil)
    }
    
}

extension BackPort.AsyncPrefixSequence: Sendable
where Base: Sendable,
      Base.Element: Sendable { }

extension BackPort.AsyncPrefixSequence.Iterator: Sendable
where Base.AsyncIterator: Sendable,
      Base.Element: Sendable { }
