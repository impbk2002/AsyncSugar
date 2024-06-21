//
//  WrappedAsyncSequence.swift
//  
//
//  Created by 박병관 on 6/15/24.
//

public struct WrappedAsyncSequence<Base:AsyncSequence> {
    
    @usableFromInline
    let base:Base
    
    @inlinable
    public init(base: Base) {
        self.base = base
    }
    
    public struct Iterator {

        @usableFromInline
        var baseIterator:Base.AsyncIterator

        @inlinable
        public init(baseIterator: Base.AsyncIterator) {
            self.baseIterator = baseIterator
        }
        
    }
    
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension WrappedAsyncSequence: AsyncSequence, TypedAsyncSequence {
    
    public typealias AsyncIterator = Iterator
    public typealias Element = Base.Element
    public typealias Failure = Base.Failure
    
    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(baseIterator: base.makeAsyncIterator())
    }

}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension WrappedAsyncSequence.Iterator: AsyncIteratorProtocol, TypedAsyncIteratorProtocol {
    
    
    public typealias Element = Base.Element
    public typealias Failure = Base.Failure
    
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
        try await baseIterator.next(isolation: actor)
    }
    
    @inlinable
    public mutating func next() async throws(Failure) -> Element? {
        try await next(isolation: nil)
    }
    
}


@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension WrappedAsyncSequence: Sendable where Base: Sendable, Base.Element: Sendable {}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension WrappedAsyncSequence.Iterator: Sendable where Base.AsyncIterator: Sendable, Base.Element: Sendable {}
