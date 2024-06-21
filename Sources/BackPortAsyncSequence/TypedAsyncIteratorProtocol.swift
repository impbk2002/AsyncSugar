//
//  Untitled.swift
//  
//
//  Created by 박병관 on 6/13/24.
//

public protocol TypedAsyncIteratorProtocol<Element, Err> {
    
    associatedtype Element
    associatedtype Err: Error
    typealias Failure = Err
    
    @inlinable
    mutating func next(isolation actor: isolated (any Actor)?) async throws(Err) -> Element?

}


public protocol TypedAsyncSequence<Element, Err>:AsyncSequence where AsyncIterator: TypedAsyncIteratorProtocol{


    /// The type of errors produced when iteration over the sequence fails.
    associatedtype Err = AsyncIterator.Err where Err == AsyncIterator.Err

    /// Creates the asynchronous iterator that produces elements of this
    /// asynchronous sequence.
    ///
    /// - Returns: An instance of the `AsyncIterator` type used to produce
    /// elements of the asynchronous sequence.
    @inlinable
    func makeAsyncIterator() -> AsyncIterator
}

package extension TypedAsyncIteratorProtocol {
    
    @inlinable
    mutating func next() async throws(Err) -> Element? {
        try await next(isolation: nil)
    }
    
}
