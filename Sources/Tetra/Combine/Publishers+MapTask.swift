//
//  Publishers+MapTask.swift
//  
//
//  Created by pbk on 2023/01/04.
//

import Foundation
@preconcurrency import Combine
internal import CriticalSection

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
public struct MapTask<Upstream:Publisher, Output>: Publisher where Upstream.Output:Sendable {

    public typealias Output = Output
    public typealias Failure = Upstream.Failure
    public typealias Transform = @Sendable @isolated(any) (Upstream.Output) async -> sending Result<Output,Failure>
    public var priority: TaskPriority? = nil
    public let upstream:Upstream
    public var transform:Transform

    public init(
        priority: TaskPriority? = nil,
        upstream: Upstream,
        transform: @escaping @Sendable @isolated(any) (Upstream.Output) async -> sending Output
    ) {
        self.priority = priority
        self.upstream = upstream
        self.transform = {
            Result.success(await transform($0))
        }
    }
    
    public init(
        priority: TaskPriority? = nil,
        upstream: Upstream,
        handler: @escaping Transform
    ) {
        self.priority = priority
        self.upstream = upstream
        self.transform = handler
    }

    public func receive<S>(subscriber: S) where S : Subscriber, Upstream.Failure == S.Failure, Output == S.Input {
        
        let processor = Inner(subscriber: subscriber, transform: transform)
        let task = Task(priority: priority, operation: processor.run)
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
            effect?.run()
            if let completion {
                subscriber?.receive(completion: completion)
            }
            taskEffect?.run()
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
            await runIn(isolation: transform.isolation)

        }
        
        internal func runIn(
            isolation actor:isolated (any Actor)? = #isolation
        ) async {
            let block = { @Sendable in
                let value = await transform($0)
                return value.map(Suppress.init)
            }
            for await upstreamResult in valueSource.stream {
                let upValue: Upstream.Output
                switch upstreamResult {
                case .failure(let error):
                    send(completion: .failure(error), cancel: false)
                    return
                case .success(let value):
                    upValue = value
                }

                // enqueue to separate task to prevent transformer cancelling root task using `UnsafeCurrentTask`
                async let job = block(upValue)
                switch (await job).map(\.value) {
                case .failure(let error):
                    send(completion: .failure(error), cancel: true)
                    return
                case .success(let value):
                    do {
                        try send(value)
                    } catch {
                        return
                    }
                }
            }
            send(completion: .finished)
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
        state.withLockUnchecked {
            $0.upstreamSubscription.transition(.finish)
        }?.run()
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

extension MapTask.Inner: CustomStringConvertible, CustomPlaygroundDisplayConvertible {
    
    var playgroundDescription: Any { description }
    
    var description: String { "MapTask" }
    
}

