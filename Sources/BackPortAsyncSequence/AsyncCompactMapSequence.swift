//
//  AsyncCompactMapSequence.swift
//
//
//  Created by 박병관 on 6/13/24.
//

extension BackPort {
    
    
    public struct AsyncCompactMapSequence<Base: AsyncSequence, ElementOfResult> where Base.AsyncIterator: TypedAsyncIteratorProtocol {
        
        @usableFromInline
        let base: Base
        
        @usableFromInline
        let transform: (Base.Element) async throws(Failure) -> ElementOfResult?
        
        @inlinable
        package init(
            _ base: Base,
            transform: @escaping (Base.Element) async throws(Failure) -> ElementOfResult?
        ) {
            self.base = base
            self.transform = transform
        }
    }
    
    
}

extension BackPort.AsyncCompactMapSequence: AsyncSequence, TypedAsyncSequence {

    /// The type of element produced by this asynchronous sequence.
    ///
    /// The compact map sequence produces errors from either the base
    /// sequence or the transforming closure.
    public typealias Failure = AsyncIterator.Failure
    /// The type of iterator that produces elements of the sequence.
    public typealias AsyncIterator = Iterator
    
    /// The iterator that produces elements of the compact map sequence.
    public struct Iterator {

        
        @usableFromInline
        var baseIterator: Base.AsyncIterator
        
        @usableFromInline
        let transform: (Base.Element) async throws(Failure) -> sending ElementOfResult?
        
        @usableFromInline
        var finished = false
        
        @usableFromInline
        init(
            _ baseIterator: Base.AsyncIterator,
            transform: @escaping (Base.Element) async throws(Failure) -> ElementOfResult?
        ) {
            self.baseIterator = baseIterator
            self.transform = transform
        }
        

    }
    
    @inlinable
    public __consuming func makeAsyncIterator() -> Iterator {
        return Iterator(base.makeAsyncIterator(), transform: transform)
    }
}


extension BackPort.AsyncCompactMapSequence.Iterator: AsyncIteratorProtocol, TypedAsyncIteratorProtocol {
    
    public typealias Element = ElementOfResult
    public typealias Failure = Base.AsyncIterator.Err
    
    /// Produces the next element in the compact map sequence.
    ///
    /// This iterator calls `next()` on its base iterator; if this call
    /// returns `nil`, `next()` returns `nil`. Otherwise, `next()`
    /// calls the transforming closure on the received element, returning it if
    /// the transform returns a non-`nil` value. If the transform returns `nil`,
    /// this method continues to wait for further elements until it gets one
    /// that transforms to a non-`nil` value. If calling the closure throws an
    /// error, the sequence ends and `next()` rethrows the error.
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Failure) -> Element? {
        while !finished {
            guard let element = try await baseIterator.next(isolation: actor) else {
                finished = true
                return nil
            }
            do {
                if let transformed = try await transform(element) {
                    return transformed
                }
            } catch {
                finished = true
                throw error
            }
        }
        return nil
    }
    
    @_disfavoredOverload
    @inlinable
    public mutating func next() async throws(Failure) -> Element? {
        try await next(isolation: nil)
    }

}

extension BackPort.AsyncCompactMapSequence: @unchecked Sendable
where Base: Sendable,
      Base.Element: Sendable { }



extension BackPort.AsyncCompactMapSequence.Iterator: @unchecked Sendable
where Base.AsyncIterator: Sendable,
      Base.Element: Sendable { }


extension BackPort.AsyncCompactMapSequence {
    
    @inlinable
    package init <Source:AsyncSequence, Failure:Error>(
        _ source: Source,
        transform: @escaping (Base.Element) async throws(Failure) -> ElementOfResult?
    ) where Source.AsyncIterator: TypedAsyncIteratorProtocol, Source.AsyncIterator.Err == Never, Base == AsyncMapErrorSequence<Source, Failure> {
        let base = AsyncMapErrorSequence(base: source, failure: Failure.self)
        self.init(base, transform: transform)
    }
    
}
