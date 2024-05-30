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
            try await withTaskCancellationHandler(operation: inner.next) { [reference] in
                reference.cancel()
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

private final class AsyncThrowingSubscriber<P:Publisher> : Subscriber, Cancellable {
    
    typealias Input = P.Output
    typealias Failure = P.Failure
    
    private let lock:some UnfairStateLock<SubscribedState> = createUncheckedStateLock(uncheckedState: SubscribedState())

    private struct SubscribedState {
        var state = State.awaitingSubscription
        var pending:[UnsafeContinuation<Input?,Error>] = []
        var pendingDemand = Subscribers.Demand.none
    }
    
    private enum State {
        case awaitingSubscription
        case subscribed(Subscription)
        case terminal(Error?)
    }

    fileprivate init() {
        
    }
    
    func receive(_ input: Input) -> Subscribers.Demand {
        let snapShot = lock.withLock {
            let oldValue = $0
            switch oldValue.state {
            case .subscribed:
                precondition(!$0.pending.isEmpty, "Received an output without requesting demand")
                $0.pending.removeFirst()
            default:
                $0.pending = []
            }
            return oldValue
        }
        switch snapShot.state {
        case .subscribed:
            snapShot.pending.first?.resume(returning: input)
        default:
            snapShot.pending.forEach{ $0.resume(returning: nil) }
        }
        return .none
    }
    
    func receive(completion: Subscribers.Completion<Failure>) {
        let snapShot = lock.withLock {
            let oldState = $0
            $0.pending.removeAll()
            switch oldState.state {
            case .awaitingSubscription, .subscribed:
                if !oldState.pending.isEmpty {
                    $0.state = .terminal(nil)
                } else {
                    switch completion {
                    case .finished:
                        $0.state = .terminal(nil)
                    case .failure(let failure):
                        $0.state = .terminal(failure)
                    }
                }
            default:
                break
            }
            return oldState
        }
        switch snapShot.state {
        case .awaitingSubscription, .subscribed:
            if let continuation = snapShot.pending.first {
                let remaining = snapShot.pending.dropFirst()
                switch completion {
                case .finished:
                    continuation.resume(returning: nil)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
                remaining.forEach{ $0.resume(returning: nil) }
            }
        case .terminal:
            snapShot.pending.forEach{ $0.resume(returning: nil) }
        }
    }
    
    func receive(subscription: Subscription) {
        let pendingDemand = lock.withLock {
            guard case .awaitingSubscription = $0.state else { return nil as Subscribers.Demand? }
            let demand = $0.pendingDemand
            $0.state = .subscribed(subscription)
            $0.pendingDemand = .none
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
        let (continuations, resource) = lock.withLock {
            let captured = ($0.pending, $0.state)
            $0.pending = []
            $0.state = .terminal(nil)
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
        
    func next() async throws -> Input? {
        return try await withUnsafeThrowingContinuation { continuation in
            let snapShot = lock.withLock {
                let oldStatus = $0.state
                switch oldStatus {
                case .awaitingSubscription:
                    $0.pending.append(continuation)
                    $0.pendingDemand += 1
                case .subscribed(_):
                    $0.pending.append(continuation)
                case .terminal:
                    $0.state = .terminal(nil)
                }
                return oldStatus
            }
            switch snapShot {
            case .awaitingSubscription:
                break
            case .subscribed(let subscription):
                subscription.request(.max(1))
            case .terminal(.none):
                continuation.resume(returning: nil)
            case .terminal(.some(let error)):
                continuation.resume(throwing: error)
            }
         }
    }
    
}

