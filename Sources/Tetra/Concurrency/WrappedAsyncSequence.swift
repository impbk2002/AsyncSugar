//
//  WrappedAsyncSequence.swift
//
//
//  Created by 박병관 on 6/11/24.
//


public struct WrappedAsyncSequence<Base:AsyncSequence>: AsyncSequence {
    
    public typealias AsyncIterator = Iterator
    
    public typealias Element = Base.Element
    public typealias Failure = any Error
    
    @usableFromInline
    var base:Base
    
    @inlinable
    public func makeAsyncIterator() -> AsyncIterator {
        Iterator(base: base.makeAsyncIterator())
    }
    
    public struct Iterator: AsyncIteratorProtocol, TypedAsyncIteratorProtocol {
        
        public typealias Element = Base.Element
        
        public typealias Failure = any Error
        
        @usableFromInline
        var base:Base.AsyncIterator

        @inlinable
        public mutating func next() async throws -> Base.Element? {
            try await base.next()
        }
        
        @inlinable
        @_implements(TypedAsyncIteratorProtocol, tetraNext(isolation:))
        public mutating func next(isolation actor: isolated (any Actor)?) async throws -> Base.Element? {
            if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
                return try await base.next(isolation: actor)
            } else {
                return try await base.advanceUnsafe()
            }
        }
        
        @usableFromInline
        init(base: Base.AsyncIterator) {
            self.base = base
        }
        

    }
    
    @inlinable
    public init(base: Base) {
        self.base = base
    }
    
}

extension WrappedAsyncSequence: Sendable where Base:Sendable {}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public struct WrappedAsyncSequenceV2<Base:AsyncSequence>: AsyncSequence {
    
    public typealias Element = Base.Element
    public typealias Failure = Base.Failure
    
    @inlinable
    public func makeAsyncIterator() -> Iterator {
        return Iterator(base: base.makeAsyncIterator())
    }
    
    @usableFromInline
    var base:Base
    
    public struct Iterator: TypedAsyncIteratorProtocol {
        
        
        @usableFromInline
        var base:Base.AsyncIterator
        
        @inlinable
        @_implements(TypedAsyncIteratorProtocol, tetraNext(isolation:))
        public mutating func next(isolation actor: isolated (any Actor)?) async throws(Base.Failure) -> Base.Element? {
            return try await base.next(isolation: actor)
        }
        
        @inlinable
        public mutating func next() async throws -> Base.Element? {
            return try await base.next()
        }
        
        @usableFromInline
        init(base: Base.AsyncIterator) {
            self.base = base
        }
    
    }
    
    @inlinable
    public init(base: Base) {
        self.base = base
    }
    
}

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension WrappedAsyncSequenceV2: Sendable where Base: Sendable {}
