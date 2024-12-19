//
//  AsyncPrefixWhileSequence.swift
//
//
//  Created by 박병관 on 6/13/24.
//

extension BackPort {
    
    public struct AsyncPrefixWhileSequence<Base: AsyncSequence> where Base.AsyncIterator: TypedAsyncIteratorProtocol {
        @usableFromInline
        let base: Base
        
        @usableFromInline
        let predicate: (Base.Element) async throws(Failure) -> Bool
        
        @inlinable
        package init(
            _ base: Base,
            predicate: @escaping (Base.Element) async throws(Failure) -> Bool
        ) {
            self.base = base
            self.predicate = predicate
        }
    }
    
    
    
}


extension BackPort.AsyncPrefixWhileSequence: AsyncSequence, TypedAsyncSequence {
    /// The type of element produced by this asynchronous sequence.
    ///
    /// The prefix-while sequence produces whatever type of element its base
    /// iterator produces.
    /// The type of error produced by this asynchronous sequence.
    ///
    /// The prefix-while sequence produces errors from either the base
    /// sequence or the filtering closure.
    public typealias Failure = AsyncIterator.Failure
    /// The type of iterator that produces elements of the sequence.
    public typealias AsyncIterator = Iterator
    
    /// The iterator that produces elements of the prefix-while sequence.
    public struct Iterator {
        

        
        @usableFromInline
        var predicateHasFailed = false
        
        @usableFromInline
        var baseIterator: Base.AsyncIterator
        
        @usableFromInline
        let predicate: (Base.Element) async throws(Failure) -> Bool
        
        @usableFromInline
        init(
            _ baseIterator: Base.AsyncIterator,
            predicate: @escaping (Base.Element) async throws(Failure) -> Bool
        ) {
            self.baseIterator = baseIterator
            self.predicate = predicate
        }
        

        
    }
    
    @inlinable
    public __consuming func makeAsyncIterator() -> Iterator {
        return Iterator(base.makeAsyncIterator(), predicate: predicate)
    }
}

extension BackPort.AsyncPrefixWhileSequence.Iterator: AsyncIteratorProtocol, TypedAsyncIteratorProtocol {
    
    public typealias Element = Base.Element
    public typealias Failure = Base.AsyncIterator.Err
    
    /// Produces the next element in the prefix-while sequence.
    ///
    /// If the predicate hasn't failed yet, this method gets the next element
    /// from the base sequence and calls the predicate with it. If this call
    /// succeeds, this method passes along the element. Otherwise, it returns
    /// `nil`, ending the sequence. If calling the predicate closure throws an
    /// error, the sequence ends and `next()` rethrows the error.
    @_disfavoredOverload
    @inlinable
    public mutating func next() async throws(Failure) -> Element? {
        try await next(isolation: nil)
    }
    
    /// Produces the next element in the prefix-while sequence.
    ///
    /// If the predicate hasn't failed yet, this method gets the next element
    /// from the base sequence and calls the predicate with it. If this call
    /// succeeds, this method passes along the element. Otherwise, it returns
    /// `nil`, ending the sequence. If calling the predicate closure throws an
    /// error, the sequence ends and `next(isolation:)` rethrows the error.
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Failure) -> Base.Element? {
        if !predicateHasFailed, let nextElement = try await baseIterator.next(isolation: actor) {
            do throws(Failure) {
                if try await predicate(Suppress(base: nextElement).base) {
                    return nextElement
                } else {
                    predicateHasFailed = true
                }
            } catch {
                predicateHasFailed = true
                throw error
            }
        }
        return nil
    }

    
}

extension BackPort.AsyncPrefixWhileSequence: @unchecked Sendable
where Base: Sendable,
      Base.Element: Sendable { }

extension BackPort.AsyncPrefixWhileSequence.Iterator: @unchecked Sendable
where Base.AsyncIterator: Sendable,
      Base.Element: Sendable { }

extension BackPort.AsyncPrefixWhileSequence {
    
    @inlinable
    package init<Source:AsyncSequence, Failure:Error>(
        _ source: Source,
        predicate: @escaping (Base.Element) async throws(Failure) -> Bool
    ) where Source.AsyncIterator: TypedAsyncIteratorProtocol, Source.AsyncIterator.Err == Never, Base == AsyncMapErrorSequence<Source, Failure> {
        let base = AsyncMapErrorSequence(base: source, failure: Failure.self)

        self.init(base, predicate: predicate)
    }
    
    
}
