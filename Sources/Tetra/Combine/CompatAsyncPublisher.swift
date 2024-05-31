//
//  CompatAsyncPublisher.swift
//  It's simply rewritten from OpenCombine/Concurrency with manual Mirror inspection
//  See https://github.com/OpenCombine/OpenCombine/tree/master/Sources/OpenCombine/Concurrency
//
//  Created by pbk on 2022/12/16.
//

import Foundation
@preconcurrency import Combine

public struct CompatAsyncPublisher<P:Publisher>: AsyncSequence where P.Failure == Never {

    public typealias AsyncIterator = Iterator
    public typealias Element = P.Output
    
    public var publisher:P
    
    public func makeAsyncIterator() -> AsyncIterator {
        Iterator(source: publisher)
    }
    
    public init(publisher: P) {
        self.publisher = publisher
    }
    
    public struct Iterator: NonThrowingAsyncIteratorProtocol {
        
        public typealias Element = P.Output
        
        private let inner = AsyncSubscriber<P>()
        private let reference:AnyCancellable
        
        public mutating func next() async -> P.Output? {
            await withTaskCancellationHandler(operation: inner.next) { [reference] in
                reference.cancel()
            }
        }
        
        internal init(source: P) {
            self.reference = AnyCancellable(inner)
            source.subscribe(inner)
        }
        
    }
        
}

private struct AsyncSubscriber<P:Publisher> : Subscriber, Cancellable where P.Failure == Never {
    
    typealias Input = P.Output
    typealias Failure = Never
    
    private let lock:some UnfairStateLock<AsyncSubscriberState<P.Output,Never>> = createUncheckedStateLock(uncheckedState: AsyncSubscriberState())
    
    let combineIdentifier = CombineIdentifier()
    
    func receive(_ input: Input) -> Subscribers.Demand {
        lock.withLockUnchecked{
            $0.transition(.resume(input))
        }?.run()
        return .none
    }
    
    func receive(completion: Subscribers.Completion<Never>) {
        lock.withLockUnchecked{
            $0.transition(.terminate(completion))
        }?.run()
    }
    
    func receive(subscription: Subscription) {
        lock.withLockUnchecked{
            $0.transition(.receive(subscription))
        }?.run()
    }
    
    
    func cancel() {
        lock.withLockUnchecked{
            $0.transition(.terminate(nil))
        }?.run()
    }

    
    func next() async -> Input? {
        let result = await withUnsafeContinuation { continuation in
            lock.withLockUnchecked{
                $0.transition(.suspend(continuation))
            }?.run()
         }
        switch result {
        case .none:
            return nil
        case .success(let value):
            return value
        }
    }
    
}
