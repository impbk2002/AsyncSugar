//
//  DemandAsyncBuffer.swift
//  
//
//  Created by pbk on 2023/01/03.
//

import Foundation
import Combine
import _Concurrency

@usableFromInline
struct DemandAsyncBuffer: AsyncSequence, Sendable {
    
    @usableFromInline
    func makeAsyncIterator() -> AsyncIterator {
        stream.makeAsyncIterator()
    }
    
    @usableFromInline
    typealias Element = Subscribers.Demand
    @usableFromInline
    typealias AsyncIterator = AsyncStream<Element>.AsyncIterator
    
    private let stream:AsyncStream<Element>
    private let continuation: AsyncStream<Element>.Continuation
    
    init() {
        let tuple  = AsyncStream<Element>.makeStream()
        stream = tuple.stream
        continuation = tuple.continuation
    }
    
    func append(element:  Element) {
        continuation.yield(element)
    }
    
    func close() {
        continuation.finish()
    }
    
}
