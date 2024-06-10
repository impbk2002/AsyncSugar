//
//  Publishers+TryMapTask.swift
//  
//
//  Created by pbk on 2023/01/04.
//

import Foundation
@preconcurrency import Combine
import _Concurrency

/**
 
    underlying task will receive task cancellation signal if the subscription is cancelled
 
    **There is an issue when using with PassthroughSubject or CurrentValueSubject**

    - Since Swift does not support running Task inline way (run in sync until suspension point), Subject's value can lost.
    - wrap the mapTask with `flatMap` or use `buffer` before `mapTask`

```
 import Combine

 let subject = PassthroughSubject<Int,Never>()
 subject.flatMap(maxPublishers: .max(1)) { value in
     Just(value).tryMapTask{ \**do async job**\ }
 }
 subject.buffer(size: 1, prefetch: .keepFull, whenFull: .customError{ fatalError() })
     .tryMapTask{ \**do async job**\ }
     
```
 */
public struct TryMapTask<Upstream:Publisher, Output:Sendable>: Publisher where Upstream.Output:Sendable {

    public typealias Output = Output
    public typealias Failure = any Error

    public let upstream:Upstream
    public var transform:@Sendable (Upstream.Output) async throws -> Output

    public init(upstream: Upstream, transform: @escaping @Sendable (Upstream.Output) async throws -> Output) {
        self.upstream = upstream
        self.transform = transform
    }
    
    public func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
        let processor = Inner(subscriber: subscriber, transform: transform)
        let task = Task(operation: processor.run)
        processor.resumeCondition(task)
        upstream.subscribe(processor)
        
    }

}

extension TryMapTask: Sendable where Upstream: Sendable {}

extension TryMapTask {
    
    internal struct TaskState<S:Subscriber> where S.Failure == Failure, S.Input == Output {
        
        var subscriber:S? = nil
        var upstreamSubscription = SubscriptionContinuation.waiting
        var condition = TaskValueContinuation.waiting
    }
    
    internal struct Inner<S:Subscriber>: CustomCombineIdentifierConvertible where S.Failure == Failure, S.Input == Output {
        
        private let valueSource = AsyncThrowingStream<Upstream.Output,Failure>.makeStream(bufferingPolicy: .bufferingNewest(2))
        private let demandSource = AsyncStream<Subscribers.Demand>.makeStream()
        private let state: some UnfairStateLock<TaskState<S>> = createUncheckedStateLock(uncheckedState: .init())
        private let transform:@Sendable (Upstream.Output) async throws -> Output
        let combineIdentifier = CombineIdentifier()
        
        init(
            subscriber:S,
            transform: @escaping @Sendable (Upstream.Output) async throws -> Output
        ) {
            
            self.transform = transform
            state.withLockUnchecked{ $0.subscriber = subscriber }
        }
        
        private func send(completion: Subscribers.Completion<Failure>?, cancel:Bool = false) {
            terminateStream()
            let (subscriber, effect) = state.withLockUnchecked{
                let old = $0.subscriber
                $0.subscriber = nil
                let effect = if cancel {
                    $0.condition.transition(.cancel)
                } else {
                    $0.condition.transition(.finish)
                }
                return (old, effect)
            }
            effect?.run()
            if let completion {
                subscriber?.receive(completion: completion)
            }
        }
        
        private func send(_ value:Output) -> Subscribers.Demand? {
            state.withLockUnchecked{
                $0.subscriber
            }?.receive(value)
        }

        private func terminateStream() {
            demandSource.continuation.finish()
            valueSource.continuation.finish()
        }
        
        private func waitForUpStream() async -> (any Subscription)? {
            await withTaskCancellationHandler {
                await withUnsafeContinuation { coninuation in
                    state.withLockUnchecked {
                        $0.upstreamSubscription.transition(.suspend(coninuation))
                    }?.run()
                }
            } onCancel: {
                state.withLockUnchecked{
                    $0.upstreamSubscription.transition(.cancel)
                }?.run()
            }
        }
        
        func resumeCondition(_ task:Task<Void,Never>) {
            state.withLock{
                $0.condition.transition(.resume(task))
            }?.run()
        }
        
        private func waitForCondition() async throws {
            try await withUnsafeThrowingContinuation{ continuation in
                state.withLock{
                    $0.condition.transition(.suspend(continuation))
                }?.run()
            }
        }
        
        private func clearCondition() {
            state.withLock{
                $0.condition.transition(.finish)
            }?.run()
        }
        
        @Sendable
        nonisolated func run() async {
            let token:Void? = try? await waitForCondition()
            if token == nil {
                withUnsafeCurrentTask{
                    $0?.cancel()
                }
            }
            defer {
                clearCondition()
            }
            let subscription = await waitForUpStream()
            state.withLockUnchecked{
                $0.subscriber
            }?.receive(subscription: self)
            defer { terminateStream() }
            guard let subscription else {
                return
            }
            let stream = valueSource.stream
            await withTaskCancellationHandler {
                var iterator = stream.makeAsyncIterator()
                for await var demand in demandSource.stream {
                    while demand > .none {
                        demand -= 1
                        subscription.request(.max(1))
                        let upstreamValue:Upstream.Output
                        do {
                            guard let value = try await iterator.next() else {
                                send(completion: .finished, cancel: false)
                                return
                            }
                            upstreamValue = value
                        } catch {
                            send(completion: .failure(error), cancel: false)
                            return
                        }
                        do {
                            let value = try await transform(upstreamValue)
                            guard let newDemand = send(value) else {
                                return
                            }
                            demand += newDemand
                        } catch {
                            send(completion: .failure(error), cancel: true)
                            return
                        }
                    }
                    
                }
            } onCancel: {
                subscription.cancel()
                send(completion: nil)
            }

        }
        
    }
 
    
}

extension TryMapTask.Inner: Subscription {
    
    func cancel() {
        state.withLock{
            $0.condition.transition(.cancel)
        }?.run()
    }
    
    func request(_ demand: Subscribers.Demand) {
        demandSource.continuation.yield(demand)
    }
    
}

extension TryMapTask.Inner: Subscriber {
    
    func receive(subscription: any Subscription) {
        state.withLockUnchecked {
            $0.upstreamSubscription.transition(.resume(subscription))
        }?.run()
    }
    
    func receive(_ input: Upstream.Output) -> Subscribers.Demand {
        let result = valueSource.continuation.yield(input)
        switch result {
        case .enqueued, .terminated:
            break
        case .dropped:
            preconditionFailure("Buffer overflow")
        @unknown default:
            fatalError("unknown case")
        }
        return .none
    }
    
    func receive(completion: Subscribers.Completion<Upstream.Failure>) {
        switch completion {
        case .finished:
            valueSource.continuation.finish()
        case .failure(let failure):
            valueSource.continuation.finish(throwing: failure)
        }
    }
    
}

extension TryMapTask.Inner: CustomStringConvertible, CustomPlaygroundDisplayConvertible {
    
    var playgroundDescription: Any { description }
    
    var description: String { "TryMapTask" }
    
}
