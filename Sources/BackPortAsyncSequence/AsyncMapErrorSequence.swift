//
//  AsyncMapErrorSequence.swift
//  
//
//  Created by 박병관 on 6/13/24.
//

public struct AsyncMapErrorSequence<Base:AsyncSequence, Failure:Error> where Base.AsyncIterator: TypedAsyncIteratorProtocol {
    
    @usableFromInline
    let mapError: @Sendable (Base.AsyncIterator.Err) async throws(Failure) -> Void
    @usableFromInline
    let base:Base
    
    @inlinable
    package init(
        base: Base,
        mapError: @escaping @Sendable (Base.AsyncIterator.Err) async throws(Failure) -> Void
    ) {
        self.mapError = mapError
        self.base = base
    }
    
    @inlinable
    package init(
        base: Base,
        failure:Failure.Type = Failure.self
    ) where Base.AsyncIterator.Err == Never {
        self.mapError = { @Sendable _ throws(Failure) in
        }
        self.base = base
        
    }
    
}




extension AsyncMapErrorSequence:AsyncSequence, TypedAsyncSequence  {
    
    public typealias AsyncIterator = Iterator
    public typealias Failure = Failure
//    public typealias Failure = AsyncIterator.Failure
    
    
    public struct Iterator {

        @usableFromInline
        let mapError: @Sendable (Base.AsyncIterator.Err) async throws(Failure) -> Void
        @usableFromInline
        var base:Base.AsyncIterator?
        

        @usableFromInline
        init(
            base: Base.AsyncIterator,
            mapError: @Sendable @escaping (Base.AsyncIterator.Err) async throws(Failure) -> Void
        ) {
            self.mapError = mapError
            self.base = base
        }
        
    }
    
    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(base: base.makeAsyncIterator(), mapError: mapError)
    }
    
    
}

extension AsyncMapErrorSequence.Iterator: AsyncIteratorProtocol, TypedAsyncIteratorProtocol {
    
    public typealias Element = Base.Element
    public typealias Failure = Failure
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Failure) -> Element? {
        do {
            let value = try await base?.next(isolation: actor)
            if value == nil {
                base = nil
            }
            return value
        } catch {
            base = nil
            try await mapError(error)
            return nil
        }
    }
    
    @_disfavoredOverload
    @inlinable
    public mutating func next() async throws(Failure) -> Element? {
        try await next(isolation: nil)
    }
    
}

extension AsyncMapErrorSequence: Sendable
where Base: Sendable,
      Base.Element: Sendable { }

extension AsyncMapErrorSequence.Iterator: Sendable
where Base.AsyncIterator: Sendable,
      Base.Element: Sendable { }
