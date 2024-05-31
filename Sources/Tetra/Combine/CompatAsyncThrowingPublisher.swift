//
//  CompatAsyncThrowingPublisher.swift
//  It's simply rewritten from OpenCombine/Concurrency with manual Mirror inspection
//  See https://github.com/OpenCombine/OpenCombine/tree/master/Sources/OpenCombine/Concurrency
//
//  Created by pbk on 2022/12/16.
//

import Foundation
@preconcurrency import Combine

public struct CompatAsyncThrowingPublisher<P:Publisher>: AsyncTypedSequence {

    public typealias AsyncIterator = Iterator
    public typealias Element = P.Output
    
    public var publisher:P
    
    public func makeAsyncIterator() -> AsyncIterator {
        Iterator(source: publisher)
    }
    
    public struct Iterator: AsyncIteratorProtocol {
        
        public typealias Element = P.Output
        
        private let inner = AsyncThrowingSubscriber<P>()
        private let reference:AnyCancellable
        
        public mutating func next() async throws -> P.Output? {
            let result = await withTaskCancellationHandler(operation: inner.next) { [reference] in
                reference.cancel()
            }
            switch result {
            case .failure(let failure):
                throw failure
            case .success(let success):
                return success
            case .none:
                return nil
            }
        }
        
        internal init(source: P) {
            self.reference = AnyCancellable(inner)
            source.subscribe(inner)
        }
        
    }
    
    public init(publisher: P) {
        self.publisher = publisher
    }

}

private struct AsyncThrowingSubscriber<P:Publisher>: Subscriber, Cancellable {
    
    typealias Input = P.Output
    typealias Failure = P.Failure
    
    private let lock:some UnfairStateLock<AsyncSubscriberState<P.Output,P.Failure>> = createUncheckedStateLock(uncheckedState: .init())


    let combineIdentifier = CombineIdentifier()
    
    func receive(_ input: Input) -> Subscribers.Demand {
        lock.withLockUnchecked{
            $0.transition(.resume(input))
        }?.run()
        
        return .none
    }
    
    func receive(completion: Subscribers.Completion<Failure>) {
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
        
    func next() async -> Result<Input,Failure>? {
        return await withUnsafeContinuation { continuation in
            lock.withLockUnchecked{
                $0.transition(.suspend(continuation))
            }?.run()
         }
    }
    
}
