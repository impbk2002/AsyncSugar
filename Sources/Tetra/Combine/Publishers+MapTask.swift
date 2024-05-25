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
 
    
    **There is an issue when using with PassthroughSubject or CurrentValueSubject**
 
    - Since Swift does not support running Task inline way (run in sync until suspension point), Subject's value can lost.
    - Use the workaround like below to prevent this kind of issue
 
```
    import Combine

    let subject = PassthroughSubject<Int,Never>()
    subject.flatMap(maxPublishers: .max(1)) { value in
        Just(value).mapTask{ \**do async job**\ }
    }
        
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
    
    
    internal struct SubscriptionState<S:Subscriber> where S.Input == Output, S.Failure == Failure {
        
        typealias AsyncSequenceSource = AsyncMapSequence<AsyncStream<Result<Upstream.Output,Failure>>,Result<Output,Failure>>
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
            transform: @escaping @Sendable (Upstream.Output) async -> Result<Output,Failure>
        ) async -> (AsyncSequenceSource, Subscription)? {
            let subscriptionLock = createCheckedStateLock(checkedState: SubscriptionContinuation.waiting)
            let (stream, continuation) = AsyncStream<Result<Upstream.Output,Failure>>.makeStream()
            continuation.onTermination = { _ in
                demandBuffer.close()
            }
            upstream
                .subscribe(
                    AnySubscriber(
                        receiveSubscription: subscriptionLock.received,
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
            guard let subscription = await subscriptionLock.consumeSubscription()
            else {
                continuation.finish()
                return nil
            }
            let source = stream.map{
                switch $0 {
                case .success(let success):
                    return await transform(success)
                case .failure(let failure):
                    return .failure(failure)
                }
            }
            return (source,subscription)
        }
        
        func runTask(
            _ source:AsyncSequenceSource,
            _ subscription: any Subscription
        ) async {
            await withTaskCancellationHandler {
                var iterator = source.makeAsyncIterator()
                for await var pending in demandBuffer {
                    if pending == .none {
                        subscription.request(.none)
                        continue
                    }
                    while pending > .none {
                        pending -= 1
                        subscription.request(.max(1))
                        guard let result = await iterator.next() else {
                            return
                        }
                        switch result {
                        case .success(let value):
                            if let nextDemand = receive(value) {
                                pending += nextDemand
                            } else {
                                return
                            }
                        case .failure(let failure):
                            receive(completion: .failure(failure))
                            return
                        }
                    }
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
        
        deinit { task.cancel() }
        


    }
    
}

extension Publishers {
    
    typealias MapTask = Tetra.MapTask
    
}
