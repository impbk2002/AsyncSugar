//
//  ThrowingTaskGroup.swift
//  
//
//  Created by 박병관 on 6/28/24.
//
import Namespace

public struct TypedThrowingTaskGroup<Element: Sendable, Failure:Error> {
    
    @usableFromInline
    let base:ThrowingTaskGroup<Element,Failure>
    
    @inlinable
    public init(base: ThrowingTaskGroup<Element,Failure>) {
        self.base = base
    }
    
}

extension TypedThrowingTaskGroup: AsyncSequence, TypedAsyncSequence {
    
    public typealias Failure = Failure

    
    @inlinable
    public func makeAsyncIterator() -> Iterator {
        Iterator(parent: base)
    }
    
    public struct Iterator {
        
        @usableFromInline
        var parent:ThrowingTaskGroup<Element,Failure>
        
        @inlinable
        internal init(
            parent: ThrowingTaskGroup<Element,Failure>
        ) {
            self.parent = parent
        }
        
    }
    
}

extension TypedThrowingTaskGroup.Iterator: AsyncIteratorProtocol, TypedAsyncIteratorProtocol {
    
    public typealias Failure = Failure
    
    @inlinable
    public mutating func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Failure) -> Element? {
        return try await parent.nextResult(isolation: actor)?.get()
    }
    
    @_disfavoredOverload
    @inlinable
    public mutating func next() async throws(Failure) -> Element? {
        try await next(isolation: nil)
    }
    
}


extension TetraExtension{
    
    @inlinable
    public func bridge<T:Sendable,Failure:Error>() -> TypedThrowingTaskGroup<T,Failure> where Base == ThrowingTaskGroup<T,Failure> {
        return .init(base: base)
    }
    
}
