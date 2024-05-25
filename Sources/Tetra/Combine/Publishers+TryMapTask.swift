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
    
    
    internal struct SubscriptionState<S:Subscriber> where S.Input == Output, S.Failure == Failure {
        
        typealias AsyncSequenceSource = AsyncThrowingMapSequence<AsyncThrowingStream<Upstream.Output,Failure>, Output>
        private let lock: some UnfairStateLock<S?> = createCheckedStateLock(checkedState: nil)
        private let demandBuffer:DemandAsyncBuffer
        
        init(demandBuffer: DemandAsyncBuffer, subscriber:S) {
            self.demandBuffer = demandBuffer
            self.lock.withLockUnchecked{ $0 = subscriber }
        }
        
        func receive(_ input: S.Input) -> Subscribers.Demand? {
            lock.withLockUnchecked{
                $0
            }?.receive(input)
        }
        
        func receive(completion: Subscribers.Completion<Failure>) {
            lock.withLockUnchecked{ 
                let old = $0
                $0 = nil
                return old
            }?.receive(completion: completion)
        }
        
        func dropSubscriber() {
            let _ = lock.withLockUnchecked{
                let old = $0
                $0 = nil
                return old
            }
        }
        
        func makeSource(
            upstream:Upstream,
            transform:@escaping @Sendable (Upstream.Output) async throws -> Output
        ) async -> (AsyncSequenceSource, Subscription)? {
            let subscriptionLock = createCheckedStateLock(checkedState: SubscriptionContinuation.waiting)
            let (stream, continuation) = AsyncThrowingStream<Upstream.Output,Failure>.makeStream()
            continuation.onTermination = { _ in
                demandBuffer.close()
            }
            upstream
                .subscribe(
                    AnySubscriber(
                        receiveSubscription: subscriptionLock.received,
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
            guard let subscription = await subscriptionLock.consumeSubscription()
            else {
                continuation.finish()
                return nil
            }
            return (stream.map(transform),subscription)
        }
        
        func runTask(
            _ source:AsyncSequenceSource,
            _ subscription: any Subscription
        ) async {
            await withTaskCancellationHandler {
                var iterator = source.makeAsyncIterator()
                do {
                    for await var pending in demandBuffer {
                        if pending == .none {
                            subscription.request(.none)
                            continue
                        }
                        while pending > .none {
                            subscription.request(.max(1))
                            pending -= 1
                            guard
                                let value = try await iterator.next(),
                                let demand = receive(value)
                            else {
                                return
                            }
                            pending += demand
                        }
                    }
                } catch {
                    receive(completion: .failure(error))
                }
            } onCancel: {
                subscription.cancel()
                dropSubscriber()
            }
            receive(completion: .finished)
            demandBuffer.close()
        }
        
        
    }
    
    private final class Inner<S:Subscriber>:Subscription, CustomStringConvertible, CustomPlaygroundDisplayConvertible where S.Input == Output, S.Failure == Failure {
        
        var description: String { "TryMapTask" }
        
        var playgroundDescription: Any { description }
        
        private let task:Task<Void,Never>
        private let demander:DemandAsyncBuffer
        
        // TODO: Replace with Delegating StateHolder
        fileprivate init(upstream:Upstream, subscriber:S, transform: @escaping @Sendable (Upstream.Output) async throws -> Output) {
            let buffer = DemandAsyncBuffer()
            let state = SubscriptionState(demandBuffer: buffer, subscriber: subscriber)
            demander = buffer
            task = Task {
                guard let (stream, subscription) = await state.makeSource(upstream: upstream, transform: transform)
                else { return }
                await state.runTask(stream, subscription)
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
        

    }
    
}

extension Publishers {
    
    typealias TryMapTask = Tetra.TryMapTask
}
