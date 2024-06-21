//
//  Untitled.swift
//
//
//  Created by 박병관 on 6/13/24.
//

import Foundation


extension BackPort {
    
    public struct AsyncDropWhileSequence<Base: AsyncSequence> where Base.AsyncIterator: TypedAsyncIteratorProtocol {
        
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
extension BackPort.AsyncDropWhileSequence: AsyncSequence, TypedAsyncSequence {
    

    /// The type of errors produced by this asynchronous sequence.
    ///
    /// The drop-while sequence produces whatever type of error its base
    /// sequence produces.
    public typealias Failure = Iterator.Failure
    /// The type of iterator that produces elements of the sequence.
    public typealias AsyncIterator = Iterator
    
    /// The iterator that produces elements of the drop-while sequence.
    public struct Iterator {
        
        @usableFromInline
        var baseIterator: Base.AsyncIterator
        
        @usableFromInline
        let predicate: ((Base.Element) async throws(Failure) -> Bool)
        
        @usableFromInline
        var finished = false
        
        @usableFromInline
        var doneDropping = false
        
        @usableFromInline
        init(
            _ baseIterator: Base.AsyncIterator,
            predicate: @escaping (Base.Element) async throws(Failure) -> Bool
        ) {
            self.baseIterator = baseIterator
            self.predicate = predicate
        }
        

    }
    
    /// Creates an instance of the drop-while sequence iterator.
    @inlinable
    public __consuming func makeAsyncIterator() -> Iterator {
        return Iterator(base.makeAsyncIterator(), predicate: predicate)
    }
}


extension BackPort.AsyncDropWhileSequence.Iterator: AsyncIteratorProtocol, TypedAsyncIteratorProtocol {
    
    public typealias Element = Base.Element
    public typealias Failure = Base.AsyncIterator.Err
    
    /// Produces the next element in the drop-while sequence.
    ///
    /// This iterator calls `next(isolation:)` on its base iterator and
    /// evaluates the result with the `predicate` closure. As long as the
    /// predicate returns `true`, this method returns `nil`. After the predicate
    /// returns `false`, for a value received from the base iterator, this
    /// method returns that value. After that, the iterator returns values
    /// received from its base iterator as-is, and never executes the predicate
    /// closure again.
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)?) async throws(Failure) -> Element? {
        while !finished && !doneDropping {
            guard let element = try await baseIterator.next(isolation: actor) else {
                return nil
            }
            do {
                if try await predicate(element) == false {
                    doneDropping = true
                    return element
                }
            } catch {
                finished = true
                throw error
            }
        }
        guard !finished else {
            return nil
        }
        return try await baseIterator.next(isolation: actor)
    }

    @inlinable
    public mutating func next() async throws(Failure) -> Element? {
        try await next(isolation: nil)
    }
    
}

extension BackPort.AsyncDropWhileSequence: @unchecked Sendable
where Base: Sendable,
      Base.Element: Sendable { }

extension BackPort.AsyncDropWhileSequence.Iterator: @unchecked Sendable
where Base.AsyncIterator: Sendable,
      Base.Element: Sendable { }

extension BackPort.AsyncDropWhileSequence {
    
    
    internal init<Source:AsyncSequence, Failure:Error>(
        _ source: Source,
        predicate: @escaping (Base.Element) async throws(Failure) -> Bool
    ) where Source.AsyncIterator: TypedAsyncIteratorProtocol, Source.AsyncIterator.Err == Never, Base == AsyncMapErrorSequence<Source, Failure> {
        let base = AsyncMapErrorSequence(base: source, failure: Failure.self)

        self.init(base, predicate: predicate)
    }
    
    
}
