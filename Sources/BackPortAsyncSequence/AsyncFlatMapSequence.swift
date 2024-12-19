//
//  AsyncFlatMapSequence.swift
//
//
//  Created by 박병관 on 6/13/24.
//

extension BackPort {
    
    
    public struct AsyncFlatMapSequence<Base: AsyncSequence, SegmentOfResult: AsyncSequence>  where Base.AsyncIterator:TypedAsyncIteratorProtocol, SegmentOfResult.AsyncIterator:TypedAsyncIteratorProtocol, SegmentOfResult.AsyncIterator.Err == Base.AsyncIterator.Err {
        
        
        @usableFromInline
        let base: Base
        
        @usableFromInline
        let transform: (Base.Element) async throws(Failure) -> SegmentOfResult
        
        @inlinable
        package init(
            _ base: Base,
            transform: @escaping (Base.Element) async throws(Failure) -> SegmentOfResult
        ) {
            self.base = base
            self.transform = transform
        }
    }
    
    
}

extension BackPort.AsyncFlatMapSequence: AsyncSequence, TypedAsyncSequence {
    
    @inlinable
    public func makeAsyncIterator() -> Iterator {
        .init(baseIterator: base.makeAsyncIterator(), transform: transform)
    }
    
    public typealias Failure = AsyncIterator.Failure
    public typealias AsyncIterator = Iterator
    
    
    public struct Iterator {
        
        @usableFromInline
        var baseIterator: Base.AsyncIterator
        
        @usableFromInline
        let transform: (Base.Element) async throws(Failure) -> SegmentOfResult
        
        @usableFromInline
        var currentIterator: SegmentOfResult.AsyncIterator?
        
        @usableFromInline
        var finished = false
        
        @usableFromInline
        init(
            baseIterator: Base.AsyncIterator,
            transform: @escaping (Base.Element) async throws(Failure) -> SegmentOfResult
        ) {
            self.baseIterator = baseIterator
            self.transform = transform
        }
        
    }
    
    
    
}


extension BackPort.AsyncFlatMapSequence.Iterator: AsyncIteratorProtocol, TypedAsyncIteratorProtocol {
    
    public typealias Element = SegmentOfResult.Element
    public typealias Failure = Base.AsyncIterator.Err
    
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Failure) -> Element? {
        while !finished {
            if var iterator = currentIterator {
                do {
                    guard let element = try await iterator.next(isolation: actor) else {
                        currentIterator = nil
                        continue
                    }
                    // restore the iterator since we just mutated it with next
                    currentIterator = iterator
                    return element
                } catch {
                    finished = true
                    throw error
                }
            } else {
                guard let item = try await baseIterator.next(isolation: actor) else {
                    return nil
                }
                let block = transform
                let wrapper = {
                    let a = try await block($0)
                    return Suppress(base: a)
                }
                do {
                    let segment: SegmentOfResult = try await wrapper(Suppress(base: item).base).base
                    var iterator = segment.makeAsyncIterator()
                    guard let element = try await iterator.next(isolation: actor) else {
                        currentIterator = nil
                        continue
                    }
                    currentIterator = iterator
                    return element
                } catch {
                    finished = true
                    currentIterator = nil
                    throw error as! Failure
                }
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

extension BackPort.AsyncFlatMapSequence: @unchecked Sendable
where Base: Sendable,
      Base.Element: Sendable,
      SegmentOfResult: Sendable,
      SegmentOfResult.Element: Sendable { }

extension BackPort.AsyncFlatMapSequence.Iterator: @unchecked Sendable
where Base.AsyncIterator: Sendable,
      Base.Element: Sendable,
      SegmentOfResult.AsyncIterator: Sendable,
      SegmentOfResult.Element: Sendable { }



extension BackPort.AsyncFlatMapSequence {
    
    @inlinable
    package init<Source:AsyncSequence, Failure:Error> (
        _ source: Source,
        transform: @escaping (Source.Element) async throws(Failure) -> SegmentOfResult
    ) where
    Source.AsyncIterator: TypedAsyncIteratorProtocol,
    Source.AsyncIterator.Err == Never,
    Base == AsyncMapErrorSequence<Source, Failure> {
        let base = AsyncMapErrorSequence(base: source, failure: Failure.self)
        self.init(base, transform: transform)
    }
    
    @inlinable
    package init<SegmentOfResultSource:AsyncSequence, Failure:Error>(
        _ base: Base,
        transform: @escaping (Base.Element) async throws(Failure) -> SegmentOfResultSource
    ) where
    SegmentOfResultSource.AsyncIterator: TypedAsyncIteratorProtocol,
    SegmentOfResultSource.AsyncIterator.Err == Never,
    SegmentOfResult == AsyncMapErrorSequence<SegmentOfResultSource, Failure> {
        self.init(base) { (value) throws(Failure) in
            
            let source = try await transform(value)
            return AsyncMapErrorSequence(base: source, failure: Failure.self)
        }
    }
    
    ///  A == B == C
    ///  A / B == C
    ///  A == B / C
    
    @inlinable
    package init<Source:AsyncSequence, SegmentOfResultSource:AsyncSequence, Failure:Error>(
        _ source: Source,
        transform: @escaping (Source.Element) async throws(Failure) -> SegmentOfResultSource
    ) where
    Source.AsyncIterator: TypedAsyncIteratorProtocol,
    Source.AsyncIterator.Err == Never,
    SegmentOfResultSource.AsyncIterator : TypedAsyncIteratorProtocol,
    SegmentOfResultSource.AsyncIterator.Err == Never,
    SegmentOfResult == AsyncMapErrorSequence<SegmentOfResultSource, Failure>,
    Base == AsyncMapErrorSequence<Source,Failure> {
        let base = AsyncMapErrorSequence(base: source, failure: Failure.self)
        self.init(base, transform: { value throws(Failure) in
            let source = try await transform(value)
            return AsyncMapErrorSequence(base: source, failure: Failure.self)
        })
    }
    
}
