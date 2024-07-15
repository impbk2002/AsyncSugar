//
//  operators.swift
//  
//
//  Created by 박병관 on 6/13/24.
//
import Namespace

public extension AsyncSequence  {
    
    @inlinable
    var tetra:TetraExtension<Self> {
        .init(self)
    }
    
}


public extension TetraExtension where Base:AsyncSequence, Base.AsyncIterator: TypedAsyncIteratorProtocol, Base.AsyncIterator.Err == Never {
    
    @inlinable
    func mapError<Failure:Error>(
        _ failureType: Failure.Type = Failure.self
    ) -> some TypedAsyncSequence<Base.Element, Failure> {
        AsyncMapErrorSequence(base: base, failure: failureType)
    }
    
    @inlinable func filter<Element,Failure:Error>(
        _ isIncluded: @escaping @Sendable (Element) async throws(Failure) -> Bool
    ) -> some TypedAsyncSequence<Element, Failure>
    where Element == Base.Element {
        mapError(Failure.self).tetra.filter(isIncluded)
    }

    @inlinable
    @_disfavoredOverload
    func map<Failure:Error, T>(
        _ map: @escaping @Sendable (Base.Element) async throws(Failure) -> T
    ) -> some TypedAsyncSequence<T,Failure>  {
        mapError().tetra.map(map)
    }
    
    @inlinable
    func flatMap2<T, Failure:Error, SegmentOfResults: AsyncSequence>(
        _ map: @escaping @Sendable (Base.AsyncIterator.Element) async throws(Failure) -> SegmentOfResults
    ) -> some TypedAsyncSequence<T, Failure> where
    SegmentOfResults.AsyncIterator.Err == Failure,
    SegmentOfResults.AsyncIterator: TypedAsyncIteratorProtocol,
    SegmentOfResults.Element == T {
        mapError().tetra.flatMap(map)
    }
//    
    @inlinable
    func flatMap0<T, Failure:Error, SegmentOfResults: AsyncSequence>(
        _ map: @escaping @Sendable (Base.AsyncIterator.Element) async throws(Failure) -> SegmentOfResults
    ) -> some TypedAsyncSequence<T, Failure> where
    SegmentOfResults.AsyncIterator.Err == Never,
    SegmentOfResults.AsyncIterator: TypedAsyncIteratorProtocol,
    SegmentOfResults.Element == T {
        mapError().tetra.flatMap{ value throws(Failure) in
            let segment = try await map(value)
            return segment.tetra.mapError(Failure.self)
        }
    }
//    
    
}

public extension TetraExtension where Base:AsyncSequence, Base.AsyncIterator: TypedAsyncIteratorProtocol {
    

    @inlinable
    func mapError<Failure:Error>(
        _ mapError: @escaping @Sendable (Base.AsyncIterator.Err) async throws(Failure) -> Void
    ) -> some TypedAsyncSequence<Base.Element, Failure> {
        AsyncMapErrorSequence(base: base, mapError: mapError)
    }
    

//    @preconcurrency @inlinable public func map<Transformed>(_ transform: @escaping @Sendable (Self.Element) async -> Transformed) -> AsyncMapSequence<Self, Transformed>
    @inlinable func filter<Element,Failure:Error>(
        _ isIncluded: @escaping @Sendable (Element) async throws(Failure) -> Bool
    ) -> some TypedAsyncSequence<Element, Base.AsyncIterator.Err>
    where Element == Base.Element, Failure == Base.AsyncIterator.Err {
        BackPort.AsyncFilterSequence(base, isIncluded: isIncluded)
    }

    @inlinable
    func map<T, Failure:Error>(
        _ map: @escaping @Sendable (Base.AsyncIterator.Element) async throws(Failure) -> T
    ) -> some TypedAsyncSequence<T, Failure> where Base.AsyncIterator.Err == Failure {
        BackPort.AsyncMapSequence(base, transform: map)
    }
    
    @inlinable
    func flatMap<T, Failure:Error, SegmentOfResults: AsyncSequence>(
        _ map: @escaping @Sendable (Base.AsyncIterator.Element) async throws(Failure) -> SegmentOfResults
    ) -> some TypedAsyncSequence<T, Failure> where
    Base.AsyncIterator.Err == Failure,
    SegmentOfResults.AsyncIterator.Err == Failure,
    SegmentOfResults.AsyncIterator: TypedAsyncIteratorProtocol,
    SegmentOfResults.Element == T {
        BackPort.AsyncFlatMapSequence(base, transform: map)
    }
    

    @inlinable
    func drop<Failure:Error>(
        while predicate: @escaping @Sendable (Base.Element) async throws(Failure) -> Bool
    ) -> some TypedAsyncSequence<Base.Element, Failure> where Failure == Base.AsyncIterator.Err {
        BackPort.AsyncDropWhileSequence(base, predicate: predicate)
    }
    
    @inlinable
    func prefix<Failure:Error>(while predicate: @escaping @Sendable (Base.Element) async throws(Failure) -> Bool) -> some TypedAsyncSequence<Base.Element, Failure> where Base.AsyncIterator.Err == Failure {
        BackPort.AsyncPrefixWhileSequence(base, predicate: predicate)
    }
    
    @inlinable
    func compactMap<ElementOfResult,Failure:Error>(_ transform: @escaping @Sendable (Base.Element) async throws(Failure) -> ElementOfResult?) -> some TypedAsyncSequence<ElementOfResult, Failure> where Base.AsyncIterator.Err == Failure {
        BackPort.AsyncCompactMapSequence(base, transform: transform)
    }
    
    @inlinable func dropFirst(_ count: Int = 1) -> some TypedAsyncSequence<Base.Element, Base.AsyncIterator.Err> {
        BackPort.AsyncDropFirstSequence(base, dropping: count)
    }
    
    @inlinable func prefix(_ count: Int = 1) -> some TypedAsyncSequence<Base.Element, Base.AsyncIterator.Err> {
        BackPort.AsyncPrefixSequence(base, count: count)
    }
    
}


public extension TetraExtension {
    
    @inlinable func dropFirst<U>(_ count: Int = 1) -> some TypedAsyncSequence<Base.Element, Base.Err> where Base == BackPort.AsyncDropFirstSequence<U> {
        BackPort.AsyncDropFirstSequence(base, dropping: count + base.count)
    }
    
    @inlinable func prefix<U>(_ count: Int = 1) -> some TypedAsyncSequence<Base.Element, Base.AsyncIterator.Err> where Base == BackPort.AsyncPrefixSequence<U> {
        BackPort.AsyncPrefixSequence(base, count: base.count + count)
    }
    
    @inlinable
    func bridge<T>() -> AsyncTypedStream<T> where Base == AsyncStream<T> {
        AsyncTypedStream(base: base)
    }
    
    @inlinable
    func bridge<T,Failure:Error>() -> AsyncTypedThrowingStream<T,Failure> where Base == AsyncThrowingStream<T,Failure> {
        AsyncTypedThrowingStream(base: base)
    }
    
}


@preconcurrency
@usableFromInline
struct Suppress<Base>:@unchecked Sendable {
    
    @usableFromInline
    nonisolated(unsafe)
    var base:Base
    
    @usableFromInline
    init(base: Base) {
        self.base = base
    }
    
}
