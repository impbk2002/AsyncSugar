//
//  Publishers+MapTask.swift
//  
//
//  Created by pbk on 2023/01/04.
//

import Foundation
@preconcurrency import Combine

/**
 
    underlying task will receive task cancellation signal if the subscription is cancelled
 
    
    **There is an issue when using with PassthroughSubject or CurrentValueSubject**
 
    - Since Swift does not support running Task inline way (run in sync until suspension point), Subject's value can lost.
    - Use the workaround like below to prevent this kind of issue
    - wrap the mapTask with `flatMap` or use `buffer` before `mapTask`

 
```
    import Combine

    let subject = PassthroughSubject<Int,Never>()
    subject.flatMap(maxPublishers: .max(1)) { value in
        Just(value).mapTask{ \**do async job**\ }
    }
    subject.buffer(size: 1, prefetch: .keepFull, whenFull: .customError{ fatalError() })
        .mapTask{ \**do async job**\ }
        
 ```
 
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
    
    public init(upstream: Upstream, handler: @escaping @Sendable (Upstream.Output) async -> Result<Output,Failure>) {
        self.upstream = upstream
        self.transform = handler
    }

    public func receive<S>(subscriber: S) where S : Subscriber, Upstream.Failure == S.Failure, Output == S.Input {
        let processor = Inner(subscriber: subscriber, transform: transform)
        let task = Task(operation: processor.run)
        processor.resumeCondition(task)
        upstream.subscribe(processor)
    }
    
}

extension MapTask: Sendable where Upstream: Sendable {}

extension MapTask {
    
    
    struct TaskState<S:Subscriber> where S.Failure == Failure, S.Input == Output {
        
        var subscriber:S? = nil
        var upstreamSubscription = SubscriptionContinuation.waiting
        var condition = TaskValueContinuation.waiting
    }
    
    struct Inner<S:Subscriber>: CustomCombineIdentifierConvertible, Sendable where S.Failure == Failure, S.Input == Output {
        
        private let valueSource = AsyncStream<Result<Upstream.Output,Failure>>.makeStream(bufferingPolicy: .bufferingNewest(2))
        private let demandSource = AsyncStream<Subscribers.Demand>.makeStream()
        private let state: some UnfairStateLock<TaskState<S>> = createUncheckedStateLock(uncheckedState: .init())
        private let transform:@Sendable (Upstream.Output) async -> Result<Output,Failure>
        let combineIdentifier = CombineIdentifier()
        
        init(
            subscriber:S,
            transform: @Sendable @escaping (Upstream.Output) async -> Result<Output, Failure>
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
                    state.withLock{
                        $0.upstreamSubscription.transition(.suspend(coninuation))
                    }?.run()
                }
            } onCancel: { [state] in
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
            defer { terminateStream() }
            state.withLockUnchecked{
                $0.subscriber
            }?.receive(subscription: self)
            guard let subscription else {
                return
            }
            await withTaskCancellationHandler {
                var iterator =  valueSource.stream.makeAsyncIterator()
                for await var demand in demandSource.stream {
                    while demand > .none {
                        demand -= 1
                        subscription.request(.max(1))
                        let upstreamResult = await iterator.next()
                        let upstreamValue:Upstream.Output
                        switch upstreamResult {
                        case .failure(let error):
                            send(completion: .failure(error), cancel: false)
                            return
                        case .none:
                            send(completion: .finished, cancel: false)
                            return
                        case .success(let value):
                            upstreamValue = value
                        }
                        // enqueue to separate task to prevent transformer cancelling root task using `UnsafeCurrentTask`
                        async let job = transform(upstreamValue)
                        switch (await job) {
                        case .success(let value):
                            if let newDemand = send(value) {
                                demand += newDemand
                            } else {
                                return
                            }
                        case .failure(let error):
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

extension MapTask.Inner: Subscriber {
    
    func receive(subscription: any Subscription) {
        state.withLockUnchecked {
            $0.upstreamSubscription.transition(.resume(subscription))
        }?.run()
    }
    
    func receive(_ input: Upstream.Output) -> Subscribers.Demand {
        let result = valueSource.continuation.yield(.success(input))
        switch result {
        case .terminated:
            break
        case .enqueued:
            break
        case .dropped:
            preconditionFailure("buffer overflow")
        @unknown default:
            fatalError("unknown case")
        }
        return .none
    }
    
    func receive(completion: Subscribers.Completion<Upstream.Failure>) {
        switch completion {
        case .finished:
            break
        case .failure(let failure):
            valueSource.continuation.yield(.failure(failure))
        }
        valueSource.continuation.finish()
    }
    
    
}

extension MapTask.Inner: Subscription {
    
    func cancel() {
        state.withLock{
            $0.condition.transition(.cancel)
        }?.run()
    }
    
    func request(_ demand: Subscribers.Demand) {
        demandSource.continuation.yield(demand)
    }
    
    
}

extension MapTask.Inner: CustomStringConvertible, CustomPlaygroundDisplayConvertible {
    
    var playgroundDescription: Any { description }
    
    var description: String { "MapTask" }
    
}

