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

private final class AsyncSubscriber<P:Publisher> : Subscriber, Cancellable where P.Failure == Never {
    
    typealias Input = P.Output
    typealias Failure = Never
    
    private let lock:some UnfairStateLock<SubscribedState> = createUncheckedStateLock(uncheckedState: SubscribedState())
    
    private struct SubscribedState {
        var status = SubscriptionStatus.awaitingSubscription
        var pending:[UnsafeContinuation<Input?,Never>] = []
        var pendingDemand = Subscribers.Demand.none
    }
    
    fileprivate init() {
        
    }
    
    func receive(_ input: Input) -> Subscribers.Demand {
        let snapShot = lock.withLockUnchecked {
            let oldValue = $0
            switch oldValue.status {
            case .subscribed:
                precondition(!$0.pending.isEmpty, "Received an output without requesting demand")
                $0.pending.removeFirst()
            default:
                $0.pending = []
            }
            return oldValue
        }
        switch snapShot.status {
        case .subscribed:
            snapShot.pending.first?.resume(returning: input)
        default:
            snapShot.pending.forEach{ $0.resume(returning: nil) }
        }
        return .none
    }
    
    func receive(completion: Subscribers.Completion<Never>) {
        lock.withLock {
            let captured = $0.pending
            $0.pending = []
            $0.status = .terminal
            return captured
        }.forEach{
            switch completion {
            case .finished:
                $0.resume(returning: nil)
            case .failure(let failure):
                $0.resume(throwing: failure)
            }
        }
    }
    
    func receive(subscription: Subscription) {
        let pendingDemand = lock.withLock {
            guard case .awaitingSubscription = $0.status else { return nil as Subscribers.Demand? }
            let demand = $0.pendingDemand
            $0.pendingDemand = .none
            $0.status = .subscribed(subscription)
            return demand as Subscribers.Demand?
        }
        if let pendingDemand {
            if pendingDemand > .none {
                subscription.request(pendingDemand)
            }
        } else {
            subscription.cancel()
        }
    }
    
    
    func cancel() {
        let (continuations, resource) = lock.withLockUnchecked {
            let captured = ($0.pending, $0.status)
            $0.pending = []
            $0.status = .terminal
            return (captured)
        }
        continuations.forEach{ $0.resume(returning: nil) }
        switch resource {
        case .subscribed(let cancellable):
            cancellable.cancel()
        default:
            break
        }
    }

    
    func next() async -> Input? {
        await withUnsafeContinuation { continuation in
            let subscriptionState = lock.withLockUnchecked {
                switch $0.status {
                case .subscribed(_):
                    $0.pending.append(continuation)
                case .awaitingSubscription:
                    $0.pending.append(continuation)
                    $0.pendingDemand += 1
                case .terminal:
                    break
                }
                return $0.status
            }
            switch subscriptionState {
            case .awaitingSubscription:
                break
            case .subscribed(let subscription):
                subscription.request(.max(1))
            case .terminal:
                continuation.resume(returning: nil)
            }
         }
    }
    
}
