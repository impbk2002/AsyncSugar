//
//  Publishers+TryMapTask.swift
//  
//
//  Created by pbk on 2023/01/04.
//

import Foundation
import Combine
import _Concurrency

/**
 
    underlying task will receive task cancellation signal if the subscription is cancelled
 
 */
public struct TryMapTask<Upstream:Publisher, Output:Sendable>: Publisher where Upstream.Output:Sendable {

    public typealias Output = Output
    public typealias Failure = Error

    public let upstream:Upstream
    public var transform:@Sendable (Upstream.Output) async throws -> Output

    public init(upstream: Upstream, transform: @escaping @Sendable (Upstream.Output) async throws -> Output) {
        self.upstream = upstream
        self.transform = transform
    }
    
    public func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
        subscriber
            .receive(
                subscription: Inner(
                    upstream: upstream, subscriber: subscriber, transform: transform
                )
            )
    }

}

extension TryMapTask: Sendable where Upstream: Sendable {}

extension TryMapTask {
    
    private final class Inner<S:Subscriber>:Subscription, CustomStringConvertible, CustomPlaygroundDisplayConvertible where S.Input == Output, S.Failure == Failure {
        
        var description: String { "TryMapTask" }
        
        var playgroundDescription: Any { description }
        
        private let task:Task<Void,Never>
        private let demander:DemandAsyncBuffer
        
        // TODO: Replace with Delegating StateHolder
        fileprivate init(upstream:Upstream, subscriber:S, transform: @escaping @Sendable (Upstream.Output) async throws -> Output) {
            let buffer = DemandAsyncBuffer()
            let lock = createUncheckedStateLock(uncheckedState: S?.some(subscriber))
            demander = buffer
            task = Task {
                let subscriptionLock = createCheckedStateLock(checkedState: SubscriptionContinuation.waiting)
                let stream = Self.makeStream(
                    upstream: upstream,
                    receiveSubscription: subscriptionLock.received,
                    onCancel: { buffer.close() },
                    transform: transform
                )
                guard let subscription = await subscriptionLock.consumeSubscription()
                else { return }
                await withTaskCancellationHandler {
                    var iterator = stream.makeAsyncIterator()
                    do {
                        for await demand in buffer {
                            var pending = demand
                            while pending > .none {
                                subscription.request(pending)
                                pending = .none
                                guard 
                                    let value = try await iterator.next(),
                                    let currentSubscriber = lock.withLockUnchecked({ $0 })
                                else {
                                    return
                                }
                                pending += currentSubscriber.receive(value)
                            }
                        }
                    } catch {
                        lock.withLockUnchecked{
                            let oldValue = $0
                            $0 = nil
                            return oldValue
                        }?.receive(completion: .failure(error))
                    }
                } onCancel: {
                    subscription.cancel()
                    lock.withLock{ $0 = nil }
                }
                lock.withLockUnchecked{
                    let oldValue = $0
                    $0 = nil
                    return oldValue
                }?.receive(completion: .finished)
                buffer.close()
            }
        }
        
        func cancel() {
            task.cancel()
        }
        
        func request(_ demand: Subscribers.Demand) {
            demander.append(element: demand)
        }
        
        deinit {
            task.cancel()
        }
        
        static func makeStream(
            upstream:Upstream,
            receiveSubscription: @escaping (any Subscription) -> Void,
            onCancel: @escaping @Sendable () -> Void,
            transform:@escaping @Sendable (Upstream.Output) async throws -> Output
        ) -> AsyncThrowingMapSequence<AsyncThrowingStream<Upstream.Output,Failure>, Output> {
            return AsyncThrowingStream<Upstream.Output,Failure> { continuation in
                continuation.onTermination = {
                    if case .cancelled = $0 {
                        onCancel()
                    }
                }
                upstream
                    .subscribe(
                        AnySubscriber(
                            receiveSubscription: receiveSubscription,
                            receiveValue: {
                                continuation.yield($0)
                                return .none
                            },
                            receiveCompletion: {
                                switch $0 {
                                case .finished:
                                    continuation.finish(throwing: .none)
                                case .failure(let error):
                                    continuation.finish(throwing: error)
                                }
                            }
                        )
                    )
            }.map{
                try await transform($0)
            }
        }

    }
    
}

extension Publishers {
    
    typealias TryMapTask = Tetra.TryMapTask
}
