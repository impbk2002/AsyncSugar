//
//  AsyncTypedSequence.swift
//  
//
//  Created by pbk on 2022/09/26.
//

import Combine
import _Concurrency

@usableFromInline
internal protocol NonThrowingAsyncIteratorProtocol<Element>: AsyncIteratorProtocol {
    
    mutating func next() async -> Element?
    
}

@usableFromInline
internal protocol NonThrowingAsyncSequence<Element>: AsyncSequence where AsyncIterator: NonThrowingAsyncIteratorProtocol<Element> {
}

public protocol AsyncTypedSequence<Element>:AsyncSequence {}

@available(iOS 15.0, macOS 12.0, macCatalyst 15.0, tvOS 15.0, watchOS 8.0, *)
extension AsyncThrowingPublisher: AsyncTypedSequence {}

@available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *)
extension AsyncPublisher.Iterator: NonThrowingAsyncIteratorProtocol {}
extension AsyncStream.Iterator: NonThrowingAsyncIteratorProtocol {}
extension AsyncStream: NonThrowingAsyncSequence {}
public struct WrappedAsyncSequence<Element>:AsyncSequence {
    
    public func makeAsyncIterator() -> Iterator {
        builder()
    }
    
    public typealias AsyncIterator = Iterator
    private let builder: @Sendable () -> AsyncIterator
    
    internal init<T:AsyncSequence>(base:T) where T.Element == Element, T.AsyncIterator: NonThrowingAsyncIteratorProtocol {
        builder = { [base] in
            Iterator(base: base.makeAsyncIterator())
        }
    }
    
    public struct Iterator: AsyncIteratorProtocol {
        
        private var iterator:any NonThrowingAsyncIteratorProtocol<Element>
        
        mutating public func next() async -> Element? {
            await iterator.next()
        }
        
        internal init<T:NonThrowingAsyncIteratorProtocol>(base:T) where T.Element == Element {
            iterator = base
        }
    }
}

