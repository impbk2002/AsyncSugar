//
//  Untitled.swift
//
//
//  Created by 박병관 on 6/13/24.
//

extension BackPort {
    
    
    public struct AsyncFilterSequence<Base: AsyncSequence> where Base.AsyncIterator: TypedAsyncIteratorProtocol {
        
        @usableFromInline
        let base: Base
        
        @usableFromInline
        let isIncluded: (Element) async throws(Failure) -> Bool
        
        @inlinable
        package init(
            _ base: Base,
            isIncluded: @escaping (Base.Element) async throws(Failure) -> Bool
        ) {
            self.base = base
            self.isIncluded = isIncluded
        }
    }
    
    
    
}

extension BackPort.AsyncFilterSequence: AsyncSequence, TypedAsyncSequence {
    
    
    public typealias Failure = AsyncIterator.Failure
    public typealias AsyncIterator = Iterator
    
    public struct Iterator {

        @usableFromInline
        var baseIterator: Base.AsyncIterator
        
        @usableFromInline
        let isIncluded: (Base.Element) async throws(Failure) -> Bool
        
        @usableFromInline
        var finished = false
        
        @usableFromInline
        init(
            _ baseIterator: Base.AsyncIterator,
            isIncluded: @escaping (Base.Element) async throws(Failure) -> Bool
        ) {
            self.baseIterator = baseIterator
            self.isIncluded = isIncluded
        }
        

    }
    
    @inlinable
    public __consuming func makeAsyncIterator() -> Iterator {
        return Iterator(base.makeAsyncIterator(), isIncluded: isIncluded)
    }
    
}


extension BackPort.AsyncFilterSequence.Iterator: AsyncIteratorProtocol, TypedAsyncIteratorProtocol {
    
    public typealias Element = Base.Element
    public typealias Failure = Base.AsyncIterator.Err
    
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Failure) -> Element? {
        while !finished {
            guard let element = try await baseIterator.next(isolation: actor) else {
                return nil
            }
            do {
                if try await isIncluded(element) {
                    return element
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

extension BackPort.AsyncFilterSequence: @unchecked Sendable
where Base: Sendable,
      Base.Element: Sendable { }

extension BackPort.AsyncFilterSequence.Iterator: @unchecked Sendable
where Base.AsyncIterator: Sendable,
      Base.Element: Sendable { }

extension BackPort.AsyncFilterSequence {
    
    @inlinable
    package init<Source:AsyncSequence, Failure:Error>(
        _ source: Source,
        predicate: @escaping (Base.Element) async throws(Failure) -> Bool
    ) where Source.AsyncIterator: TypedAsyncIteratorProtocol, Source.AsyncIterator.Err == Never, Base == AsyncMapErrorSequence<Source, Failure> {
        let base = AsyncMapErrorSequence(base: source, failure: Failure.self)
        self.init(base, isIncluded: predicate)
    }
    

    
}
