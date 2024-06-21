//
//  AsyncMapSequence.swift
//
//
//  Created by 박병관 on 6/13/24.
//

extension BackPort {
    
    public struct AsyncMapSequence<Base: AsyncSequence, Transformed> where Base.AsyncIterator: TypedAsyncIteratorProtocol{
        @usableFromInline
        let base: Base
        
        @usableFromInline
        let transform: (Base.Element) async throws(Failure) -> Transformed
        
        @inlinable
        package init(
            _ base: Base,
            transform: @escaping (Base.Element) async throws(Failure) -> Transformed
        ) {
            self.base = base
            self.transform = transform
        }
    }
    
    
}



extension BackPort.AsyncMapSequence: AsyncSequence, TypedAsyncSequence {

    /// The type of the error that can be produced by the sequence.
    ///
    /// The map sequence produces whatever type of error its
    /// base sequence does.
    public typealias Failure = AsyncIterator.Failure
    /// The type of iterator that produces elements of the sequence.
    public typealias AsyncIterator = Iterator
    
    /// The iterator that produces elements of the map sequence.
    public struct Iterator: AsyncIteratorProtocol, TypedAsyncIteratorProtocol {
        
        public typealias Element = Transformed
        public typealias Failure = Base.AsyncIterator.Err
        
        @usableFromInline
        var baseIterator: Base.AsyncIterator
        
        @usableFromInline
        var finished = false
        
        @usableFromInline
        let transform: (Base.Element) async throws(Failure) -> sending Transformed
        
        @usableFromInline
        init(
            _ baseIterator: Base.AsyncIterator,
            transform: @escaping (Base.Element) async throws(Failure) -> Transformed
        ) {
            self.baseIterator = baseIterator
            self.transform = transform
        }
        
        /// Produces the next element in the map sequence.
        ///
        /// This iterator calls `next()` on its base iterator; if this call returns
        /// `nil`, `next()` returns `nil`. Otherwise, `next()` returns the result of
        /// calling the transforming closure on the received element.
        @inlinable
        public mutating func next() async throws(Failure) -> Element? {
            try await next(isolation: nil)
        }
        
        /// Produces the next element in the map sequence.
        ///
        /// This iterator calls `next(isolation:)` on its base iterator; if this
        /// call returns `nil`, `next(isolation:)` returns `nil`. Otherwise,
        /// `next(isolation:)` returns the result of calling the transforming
        /// closure on the received element.
        @inlinable
        public mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) ->  Element? {
            guard !finished, let element = try await baseIterator.next(isolation: actor) else {
                return nil
            }
            do {
                return try await transform(element)
            } catch {
                finished = true
                throw error
            }
        }

    }
    
    @inlinable
    public __consuming func makeAsyncIterator() -> Iterator {
        return Iterator(base.makeAsyncIterator(), transform: transform)
    }
}

extension BackPort.AsyncMapSequence: @unchecked Sendable
where Base: Sendable,
      Base.Element: Sendable,
      Transformed: Sendable { }

extension BackPort.AsyncMapSequence.Iterator: @unchecked Sendable
where Base.AsyncIterator: Sendable,
      Base.Element: Sendable,
      Transformed: Sendable { }

extension BackPort.AsyncMapSequence {
    
    @inlinable
    package init <Source:AsyncSequence, Failure:Error>(
        _ source: Source,
        _ failure: Failure.Type = Failure.self,
        transform: @escaping (Base.Element) async throws(Failure) -> Transformed
    ) where Source.AsyncIterator: TypedAsyncIteratorProtocol, Source.AsyncIterator.Err == Never, Base == AsyncMapErrorSequence<Source, Failure> {
        let base = AsyncMapErrorSequence(base: source, failure: failure)

        self.init(base, transform: transform)
    }
//    
//    internal init(
//        _ base: Base,
//        block: @escaping (Base.Element) async throws(Never) -> Transformed
//    )  {
//        self.init(base, transform: { await block($0) })
//    }
//    
    
    
}


