//
//  ConvertTypeToAsyncSequence.swift
//  
//
//  Created by 박병관 on 6/15/24.
//

public struct ConvertTypeToAsyncSequence<Base:AsyncSequence> where Base.AsyncIterator: TypedAsyncIteratorProtocol {
    
    @usableFromInline
    var base:Base
    
    @inlinable
    public init(base: Base) {
        self.base = base
    }
    
}

extension ConvertTypeToAsyncSequence: AsyncSequence, TypedAsyncSequence {
    
    public typealias Failure = Iterator.Failure
    
    public struct Iterator {
        
        @usableFromInline
        var baseIterator:Base.AsyncIterator
        
        @usableFromInline
        init(baseIterator: Base.AsyncIterator) {
            self.baseIterator = baseIterator
        }
        
    }
    
    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(baseIterator: base.makeAsyncIterator())
    }
    
}


extension ConvertTypeToAsyncSequence.Iterator: AsyncIteratorProtocol, TypedAsyncIteratorProtocol {
    
    public typealias Failure = Base.AsyncIterator.Err
    public typealias Element = Base.Element
    
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
        try await baseIterator.next(isolation: actor)
    }
    
    @inlinable
    public mutating func next() async throws(Failure) -> Element? {
        try await next(isolation: nil)
    }
    
    
}

extension ConvertTypeToAsyncSequence: Sendable where Base: Sendable, Base.Element: Sendable {}
extension ConvertTypeToAsyncSequence.Iterator: Sendable where Base.AsyncIterator: Sendable, Base.Element: Sendable {}

