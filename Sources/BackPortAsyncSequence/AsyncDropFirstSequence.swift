//
//  AsyncDropFirstSequence.swift
//
//
//  Created by 박병관 on 6/14/24.
//

extension BackPort {
    
    public struct AsyncDropFirstSequence<Base: AsyncSequence> where Base.AsyncIterator: TypedAsyncIteratorProtocol {
        @usableFromInline
        let base: Base
        
        @usableFromInline
        let count: Int
        
        @inlinable
        package init(_ base: Base, dropping count: Int) {
            precondition(count >= 0, "Can't drop a negative number of elements from an async sequence")
            self.base = base
            self.count = count
        }
    }
    
}

extension BackPort.AsyncDropFirstSequence: AsyncSequence, TypedAsyncSequence {
    
    public typealias AsyncIterator = Iterator
    public typealias Failure = AsyncIterator.Failure
    
    public struct Iterator {
        
        @usableFromInline
        var baseIterator: Base.AsyncIterator
        
        @usableFromInline
        var count: Int
        
        @usableFromInline
        init(_ baseIterator: Base.AsyncIterator, count: Int) {
            self.baseIterator = baseIterator
            self.count = count
        }
    }
    
    public func makeAsyncIterator() -> Iterator {
        Iterator(base.makeAsyncIterator(), count: count)
    }
    
}

extension BackPort.AsyncDropFirstSequence.Iterator: AsyncIteratorProtocol, TypedAsyncIteratorProtocol {
    
    public typealias Element = Base.Element
    
    public typealias Failure = Base.AsyncIterator.Err
    
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
        var remainingToDrop = count
        while remainingToDrop > 0 {
            guard try await baseIterator.next(isolation: actor) != nil else {
                count = 0
                return nil
            }
            remainingToDrop -= 1
        }
        count = 0
        return try await baseIterator.next(isolation: actor)
    }
    
    @inlinable
    public mutating func next() async throws(Failure) -> Element? {
        try await next(isolation: nil)
    }
    
}

extension BackPort.AsyncDropFirstSequence: @unchecked Sendable
where Base: Sendable,
      Base.Element: Sendable { }

extension BackPort.AsyncDropFirstSequence.Iterator: @unchecked Sendable
where Base.AsyncIterator: Sendable,
      Base.Element: Sendable { }
