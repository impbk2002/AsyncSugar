//
//  Publishers+TryMapTask.swift
//  
//
//  Created by pbk on 2023/01/04.
//

import Foundation
@preconcurrency import Combine
import _Concurrency
internal import CriticalSection

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
public struct TryMapTask<Upstream:Publisher, Output>: Publisher where Upstream.Output:Sendable {

    public typealias Output = Output
    public typealias Failure = any Error
    public typealias Transform = @isolated(any) @Sendable (Upstream.Output) async throws -> sending Output
    public let upstream:Upstream
    public var transform: Transform
    public var priority: TaskPriority? = nil

    public init(
        priority:TaskPriority? = nil,
        upstream: Upstream,
        transform: @escaping Transform
    ) {
        self.upstream = upstream
        self.transform = transform
        self.priority = priority
    }
    
    public func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
//        let processor = Inner(subscriber: subscriber, transform: transform)
//        let task = Task(priority: priority, operation: processor.run)
//        processor.resumeCondition(task)
//        upstream.subscribe(processor)
        MultiMapTask(
            priority: priority,
            maxTasks: .max(1),
            upstream: upstream.mapError{ $0 as any Error },
            transform: transform
        ).subscribe(MapTaskInner(
            description: "TryMapTask",
            downstream: subscriber,
            upstream: nil
        ))
        
    }

}


extension TryMapTask: Sendable where Upstream: Sendable {}

extension TryMapTask {
    
    internal struct TaskState<S:Subscriber> where S.Failure == Failure, S.Input == Output {
        
        var subscriber:S? = nil
        var upstreamSubscription = AsyncSubscriptionState.waiting
        var condition = TaskValueContinuation.waiting
        var isSleeping = true
        var pending = Subscribers.Demand.none
    }
    
    internal struct Inner<S:Subscriber>: Sendable, CustomCombineIdentifierConvertible where S.Failure == Failure, S.Input == Output {
        
        private let valueSource = AsyncThrowingStream<Upstream.Output,Failure>.makeStream(bufferingPolicy: .bufferingNewest(2))
        private let state: some UnfairStateLock<TaskState<S>> = createUncheckedStateLock(uncheckedState: .init())
        private let transform: Transform
        let combineIdentifier = CombineIdentifier()
        
        init(
            subscriber:S,
            transform: @escaping Transform
        ) {
            
            self.transform = transform
            state.withLockUnchecked{ $0.subscriber = subscriber }
        }
        
        private func send(completion: Subscribers.Completion<Failure>?, cancel:Bool = false) {
            terminateStream()
            let (subscriber, effect, taskEffect) = state.withLockUnchecked{
                let old = $0.subscriber
                $0.subscriber = nil
                let effect = if cancel {
                    $0.upstreamSubscription.transition(.cancel)
                } else {
                    $0.upstreamSubscription.transition(.finish)
                }
                let taskEffect = if cancel {
                    $0.condition.transition(.cancel)
                } else {
                    $0.condition.transition(.finish)
                }
                return (old, effect, taskEffect)
            }
            (consume effect)?.run()
            if let completion {
                (consume subscriber)?.receive(completion: completion)
            }
            (consume taskEffect)?.run()
        }
        
        private func send(_ value:Output) throws {
            let subscriber = state.withLockUnchecked{
                $0.isSleeping = true
                return $0.subscriber
             }
             guard let subscriber else {
                 throw CancellationError()
             }
             let demand = subscriber.receive(value)
             request(demand)
        }

        private func terminateStream() {
            valueSource.continuation.finish()
        }
        
        
        private func waitForUpStream( isolation actor:isolated (any Actor)? = #isolation) async throws {
            try await withTaskCancellationHandler {
                try await withUnsafeThrowingContinuation { coninuation in
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
        
        
        private func waitForCondition( isolation actor:isolated (any Actor)? = #isolation) async throws {
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
            let token:Void? = try? await waitForCondition(isolation: transform.isolation)
            if token == nil {
                withUnsafeCurrentTask{
                    $0?.cancel()
                }
            }
            defer {
                clearCondition()
            }
            let subscription: Void? = try? await waitForUpStream(isolation: transform.isolation)
            state.withLockUnchecked{
                $0.subscriber
            }?.receive(subscription: self)
            defer { terminateStream() }
            guard subscription != nil else {
                return
            }
            await runInIsolation(isolation: transform.isolation)
        }
        
        func runInIsolation(
            isolation actor: isolated (any Actor)? = #isolation
        ) async {
            let block = { @Sendable in
                let value = try await transform($0)
                return Suppress(value: value)
            }
            do {
                for try await upValue in valueSource.stream {
                    do {
                        // enqueue to separate task to prevent transformer cancelling root task using `UnsafeCurrentTask`
                        async let job = block(upValue)
                        let value = try await job.value
                        guard let _ = try? send(value) else {
                            return
                        }
                    } catch {
                        send(completion: .failure(error), cancel: true)
                        return
                    }
                }
                send(completion: .finished, cancel: false)
            } catch {
                send(completion: .failure(error), cancel: false)
            }
        }
        
    }
 
    
}

extension TryMapTask.Inner: Subscription {
    
    func cancel() {
        send(completion: nil, cancel: true)
    }
    
    func request(_ demand: Subscribers.Demand) {
        let subscription = state.withLockUnchecked {
            $0.pending += demand
            if $0.isSleeping && $0.pending > .none {
                $0.isSleeping = false
                $0.pending -= 1
                return $0.upstreamSubscription.subscription
            } else {
                
                return nil
            }
        }
        subscription?.request(.max(1))
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
        state.withLockUnchecked {
            $0.upstreamSubscription.transition(.finish)
        }?.run()
        switch completion {
        case .finished:
            valueSource.continuation.finish(throwing: nil)
        case .failure(let failure):
            valueSource.continuation.finish(throwing: failure)
        }
    }
    
}

extension TryMapTask.Inner: CustomStringConvertible, CustomPlaygroundDisplayConvertible {
    
    var playgroundDescription: Any { description }
    
    var description: String { "TryMapTask" }
    
}
