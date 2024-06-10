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
    public var transform:@Sendable @isolated(any) (Upstream.Output) async -> Result<Output,Failure>

    public init(
        upstream: Upstream,
        transform: @escaping @Sendable @isolated(any) (Upstream.Output) async -> Output
    ) {
        self.upstream = upstream
        self.transform = {
            Result.success(await transform($0))
        }
    }
    
    public init(
        upstream: Upstream,
        handler: @escaping @Sendable @isolated(any) (Upstream.Output) async -> Result<Output,Failure>
    ) {
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
        var upstreamSubscription = AsyncSubscriptionState.waiting
        var condition = TaskValueContinuation.waiting
        var isSleeping = true
        var pending = Subscribers.Demand.none
    }
    
    struct Inner<S:Subscriber>: CustomCombineIdentifierConvertible, Sendable where S.Failure == Failure, S.Input == Output {
        
        private let valueSource = AsyncStream<Result<Upstream.Output,Failure>>.makeStream(bufferingPolicy: .bufferingNewest(2))
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
            let (subscriber, effect) = state.withLockUnchecked{
                let old = $0.subscriber
                $0.subscriber = nil
                let effect = if cancel {
                    $0.upstreamSubscription.transition(.cancel)
                } else {
                    $0.upstreamSubscription.transition(.finish)
                }
                return (old, effect)
            }
            effect?.run()
            if let completion {
                subscriber?.receive(completion: completion)
            }
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
        
        private func waitForUpStream() async throws {
            try await withTaskCancellationHandler {
                try await withUnsafeThrowingContinuation { coninuation in
                    state.withLockUnchecked{
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
            let success: Void? = try? await waitForUpStream()
            defer { terminateStream() }
            state.withLockUnchecked{
                $0.subscriber
            }?.receive(subscription: self)
            guard success != nil else {
                return
            }
            try? await withTaskCancellationHandler {
                for await upstreamResult in valueSource.stream {
                    let upValue: Upstream.Output
                    switch upstreamResult {
                    case .failure(let error):
                        send(completion: .failure(error), cancel: false)
                        throw CancellationError()
                    case .success(let value):
                        upValue = value
                    }
                    // enqueue to separate task to prevent transformer cancelling root task using `UnsafeCurrentTask`
                    async let job = transform(upValue)
                    switch (await job) {
                    case .failure(let error):
                        send(completion: .failure(error), cancel: true)
                        throw CancellationError()
                    case .success(let value):
                        try send(value)
                    }
                }
                send(completion: .finished)
            } onCancel: {
                send(completion: nil, cancel: true)
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

extension MapTask.Inner: CustomStringConvertible, CustomPlaygroundDisplayConvertible {
    
    var playgroundDescription: Any { description }
    
    var description: String { "MapTask" }
    
}

