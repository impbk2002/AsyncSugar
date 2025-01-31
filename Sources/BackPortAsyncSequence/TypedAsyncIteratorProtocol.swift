//
//  TypedAsyncIteratorProtocol.swift
//  
//
//  Created by 박병관 on 6/13/24.
//
/***
 Entry point of TypeFailure for `AsyncFlatMap` and `AsyncSequencePublisher

 Since generalized `AsyncSequence` is not available until Swift 6, this `protocol` is a entry point for async typed throw.

Even though it has isolation parameter, this parameter is rarely used since `AsyncFlatMap` and `AsyncSequencePublisher` runs in nonisolated Task space.

`Use `WrappedAsyncSequence`  or  `LegacyTypedAsyncSequence` if possible which provides general implementation to adapt this protocol
 
 Use `TypedAsyncSequence` with Associated primarmy type generic to make use of AsyncSequence in abstract way. And later wrap the instance with `ConvertTypeToAsyncSequence` to use it as typed `AsyncSequence`
```
 
 let source = AsyncStream<Int>(...)
 let abstactSequence:some TypedAsyncSequence<Int, Never> = AsyncTypedStream(base: source)
 for await value in ConvertTypeToAsyncSequence(base: abstactSequence) {
    // use value
    // this sequence is fully typed throwing and actor isolation support
 }
 
 
```
 
 
 - important: `Err` must be same as `AsyncIterator.Failure`
 
 
 - adapting protocol to existing type,
 
 adapting protocols to exisiting type that user don't own is pretty easy too. By writing conformance like below, compiler now know the correct implemenation without recursive problem.
````
 extension AsyncStream.Iterator: TypedAsyncIteratorProtocol {
 
     @_implements(TypedAsyncIteratorProtocol, next(isolation:))
     mutating public func tetraNext(isolation actor: isolated (any Actor)?) async throws(Never) -> Self.Element? {
         if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
             var c: some AsyncIteratorProtocol<Element, TetraFailure> = self
             defer {
                 self = c as! Self
             }
             return await c.next(isolation: actor)
         } else {
             return try? await next()
         }
     }
     
 }

 ````
 */

public protocol TypedAsyncIteratorProtocol<Element, Err>: ~Copyable {
    
    associatedtype Element
    associatedtype Err: Error
//    typealias Failure = Err
    
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
