//
//  Publishers+MapTask.swift
//  
//
//  Created by pbk on 2023/01/04.
//

import Foundation
import Combine

/**
 
    underlying task will receive task cancellation signal if the subscription is cancelled
 
 */
public struct MapTask<Upstream:Publisher, Output:Sendable>: Publisher where Upstream.Output:Sendable {

    public typealias Output = Output
    public typealias Failure = Upstream.Failure

    public let upstream:Upstream
    public var transform:@Sendable (Upstream.Output) async -> Result<Output,Failure>

    public init(upstream: Upstream, transform: @escaping @Sendable (Upstream.Output) async -> Output) {
        self.upstream = upstream
        self.transform = {
            Result.success(await transform($0))
        }
    }
    
    public init(upstream: Upstream, transform: @escaping @Sendable (Upstream.Output) async -> Result<Output,Failure>) {
        self.upstream = upstream
        self.transform = transform
    }

    public func receive<S>(subscriber: S) where S : Subscriber, Upstream.Failure == S.Failure, Output == S.Input {
        subscriber
            .receive(
                subscription: Inner(
                    upstream: upstream, subscriber: subscriber, transform: transform
                )
            )
    }
    
}

extension MapTask: Sendable where Upstream: Sendable {}

extension MapTask {
    
    private final class Inner<S:Subscriber>:Subscription, CustomStringConvertible, CustomPlaygroundDisplayConvertible where S.Input == Output, S.Failure == Failure {
        
        var description: String { "MapTask" }
        
        var playgroundDescription: Any { description }
        
        private let task:Task<Void,Never>
        private let demander:DemandAsyncBuffer
        
        // TODO: Replace with Delegating StateHolder
        fileprivate init(
            upstream:Upstream,
            subscriber:S,
            transform: @escaping @Sendable (Upstream.Output) async -> Result<Output,Failure>
        ) {
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
                    for await demand in buffer {
                        var pending = demand
                        while pending > .none {
                            pending -= 1
                            subscription.request(.max(1))
                            guard let result = await iterator.next() else {
                                return
                            }
                            switch result {
                            case .success(let value):
                                if let currentSubscriber = lock.withLockUnchecked({ $0 }) {
                                    pending += currentSubscriber.receive(value)
                                } else {
                                    return
                                }
                            case .failure(let failure):
                                lock.withLockUnchecked{
                                    let oldValue = $0
                                    $0 = nil
                                    return oldValue
                                }?.receive(completion: .failure(failure))
                                return
                            }
                        }
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
        
        deinit { task.cancel() }
        
        static func makeStream(
            upstream:Upstream,
            receiveSubscription: @escaping (any Subscription) -> Void,
            onCancel: @escaping @Sendable () -> Void,
            transform:@escaping @Sendable (Upstream.Output) async -> Result<Output,Failure>
        ) -> AsyncMapSequence<AsyncStream<Result<Upstream.Output,Failure>>,Result<Output,Failure>> {
            let stream = AsyncStream<Result<Upstream.Output,Failure>>{ continuation in
                upstream.subscribe(
                    AnySubscriber(
                        receiveSubscription: receiveSubscription,
                        receiveValue: {
                            continuation.yield(.success($0))
                            return .none
                        },
                        receiveCompletion: {
                            switch $0 {
                            case .finished:
                                break
                            case .failure(let error):
                                continuation.yield(.failure(error))
                            }
                            continuation.finish()
                        }
                    )
                )
                continuation.onTermination = {
                    if case .cancelled = $0 {
                        onCancel()
                    }
                }
            }.map{
                switch $0 {
                case .success(let success):
                    return await transform(success)
                case .failure(let failure):
                    return .failure(failure)
                }
            }
            return stream
        }

    }
    
}

extension Publishers {
    
    typealias MapTask = Tetra.MapTask
    
}
