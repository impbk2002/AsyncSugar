//
//  File.swift
//
//
//  Created by 박병관 on 6/7/24.
//

import Foundation
@preconcurrency import Combine

struct AsyncFlatMap<Upstream:Publisher,Segment:AsyncSequence, TransformFail:Error>: Publisher where Upstream.Output:Sendable {
    
    typealias Output = Segment.Element
    typealias Failure = AsyncFlatMapError<Upstream.Failure, TransformFail, Segment.Failure>
    typealias Transform = @Sendable (Upstream.Output) async throws(TransformFail) -> Segment
    let maxTasks:Subscribers.Demand
    let upstream:Upstream
    let transform:Transform
    
    func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Segment.Element == S.Input {
        let processor = Inner(maxTasks: maxTasks, subscriber: subscriber, transform: transform)
        let task = Task(operation: processor.run)
        processor.resumeCondition(task)
        upstream.subscribe(processor)
    }
    
    init(
        maxTasks: Subscribers.Demand,
        upstream: Upstream,
        transform: @escaping @isolated(any) Transform
    ) {
        self.maxTasks = maxTasks
        self.upstream = upstream
        self.transform = transform
    }
    
}

extension AsyncFlatMap {
    
    struct Inner<Down:Subscriber>: Subscriber, Sendable, Subscription, CustomStringConvertible, CustomPlaygroundDisplayConvertible
    where Segment.Element == Down.Input, Down.Failure == AsyncFlatMap.Failure {
        
        typealias Transformer = @Sendable (Upstream.Output) async throws(TransformFail) -> Segment
        typealias Input = Upstream.Output
        typealias Failure = Upstream.Failure
        
        
        let lock:some UnfairStateLock<TaskState> = createUncheckedStateLock(uncheckedState: TaskState())
        
        struct TaskState {
            var demandState = AsyncFlatMapDemandState()
            var subscriber:Down? = nil
            var upstreamSubscription = AsyncSubscriptionState.waiting
            var taskCondition = TaskValueContinuation.waiting
        }
        
        let maxTasks:Subscribers.Demand
        let transform:Transformer
        let valueSource = AsyncStream<Result<Upstream.Output,Upstream.Failure>>.makeStream()
        let combineIdentifier = CombineIdentifier()
        
        
        init(maxTasks:Subscribers.Demand ,subscriber: Down,transform: @escaping Transformer) {
            self.transform = transform
            self.maxTasks = maxTasks
            lock.withLockUnchecked{
                $0.subscriber = subscriber
            }
        }
        
        @Sendable
        func run() async {
            let token:Void? = try? await waitForCondition()
            if token == nil {
                withUnsafeCurrentTask{
                    $0?.cancel()
                }
            }
            defer {
                clearCondition()
            }
            let success:Void? = try? await waitForUpStream()
            lock.withLockUnchecked{
                $0.subscriber
            }?.receive(subscription: self)
            guard success != nil else {
                terminateStream()
                return
            }
            await withTaskCancellationHandler {
                let isCancelled:Bool
                if #available(iOS 17.0, tvOS 17.0, macCatalyst 17.0, macOS 14.0, watchOS 10.0, visionOS 1.0, *) {
                    let void:Void? = try? await withThrowingDiscardingTaskGroup {  group in
                        defer { terminateStream() }
                        try await localTask(group: &group)
                    }
                    
                    isCancelled = void == nil
                } else {
                    let void:Void? = try? await withThrowingTaskGroup(of: Void.self) { group in
                        defer { terminateStream() }
                        nonisolated(unsafe)
                        let unsafe = group.makeAsyncIterator()
                        async let subTask:() = {
                            var iterator = unsafe
                            while let _ = try await iterator.next() {
                                
                            }
                        }()
                        try await localTask(group: &group)
                        try await subTask
                    }
                    isCancelled = void == nil
                }
                if !isCancelled {
                    send(completion: .finished)
                }
            } onCancel: {
                send(completion: nil)
            }
        }
        
        var playgroundDescription: Any { description }
        
        var description: String { "AsyncFlatMap" }
        
        
        func receive(_ input: sending Input) -> Subscribers.Demand {
            valueSource.continuation.yield(.success(input))
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
        
        func receive(subscription: any Subscription) {
            let (effect, requestValue) = lock.withLockUnchecked{
                let effect = $0.upstreamSubscription.transition(.resume(subscription))
                let requestValue = subscription.combineIdentifier == $0.upstreamSubscription.subscription?.combineIdentifier
                return (effect, requestValue)
            }
            effect?.run()
            if requestValue && maxTasks > .none {
                subscription.request(maxTasks)
            }
        }
        
        func request(_ demand: Subscribers.Demand) {
            lock.withLockUnchecked{
                $0.demandState.transition(.resume(demand))
            }?.run()
        }
        
        func cancel() {
            lock.withLockUnchecked{
                $0.taskCondition.transition(.cancel)
            }?.run()
        }
        
        private func send(completion: Subscribers.Completion<AsyncFlatMap.Failure>?) {
            let (subscriber, effect, interruption) = lock.withLockUnchecked{
                let old = $0.subscriber
                $0.subscriber = nil
                let effect = if completion == nil {
                    $0.upstreamSubscription.transition(.cancel)
                } else {
                    $0.upstreamSubscription.transition(.finish)
                }
                let interruption = $0.demandState.transition(.interrupt)
                return (old, effect, interruption)
            }
            if let completion {
                subscriber?.receive(completion: completion)
            }
            effect?.run()
            interruption?.run()
        }
        
        
        private func send(_ value:Down.Input) throws(CancellationError) {
            let subscriber = lock.withLockUnchecked {
                $0.subscriber
            }
            guard let newDemand = subscriber?.receive(value) else {
                throw CancellationError()
            }
            lock.withLockUnchecked{
                $0.demandState.transition(.resume(newDemand))
            }?.run()
        }
        
        private func waitForUpStream() async throws {
            try await withTaskCancellationHandler {
                try await withUnsafeThrowingContinuation { coninuation in
                    lock.withLockUnchecked{
                        $0.upstreamSubscription.transition(.suspend(coninuation))
                    }?.run()
                }
            } onCancel: {
                lock.withLockUnchecked{
                    $0.upstreamSubscription.transition(.cancel)
                }?.run()
            }
        }
        
        func resumeCondition(_ task:Task<Void,Never>) {
            lock.withLock{
                $0.taskCondition.transition(.resume(task))
            }?.run()
        }
        
        private func waitForCondition() async throws {
            try await withUnsafeThrowingContinuation{ continuation in
                lock.withLock{
                    $0.taskCondition.transition(.suspend(continuation))
                }?.run()
            }
        }
        
        private func clearCondition() {
            lock.withLock{
                $0.taskCondition.transition(.finish)
            }?.run()
        }
        
        private func terminateStream() {
            valueSource.continuation.finish()
        }
        
        private func makeSegment(_ input:Upstream.Output) async throws(CancellationError) -> Segment {
            let result:Result<Segment,TransformFail>
            do {
                let seg = try await transform(input)
                result = .success(seg)
            } catch {
                result = .failure(error )
            }
            switch result {
            case .success(let success):
                return success
            case .failure(let failure):
                send(completion: .failure(.transform(failure)))
                throw CancellationError()
            }
        }
        
        /// whether demand is unlimited
        /// - Returns: `true` if demand is unlimited, `false` if demand is just `1`.
        /// - throws: `CancellationError` if internal state reached cancellation
        private func nextDemand() async throws -> Bool {
            try await withUnsafeThrowingContinuation { continuation in
                lock.withLockUnchecked{
                    $0.demandState.transition(.suspend(continuation))
                }?.run()
            }
        }
        
        
        /// process next segment and send event to downstream
        /// - Returns: `false` if iterator reached termination otherwise `true`
        /// - throws: `CancellationError` if internal state reached cancellation
        private func processNextSegment(
            iterator: inout Segment.AsyncIterator
        ) async throws(CancellationError) -> Bool {
            let nextResult = await wrapToResult(nil, &iterator)
            switch nextResult {
            case .none:
                //finished
                // check and request more transformer
                // request one more from upstream subscription
                if maxTasks != .unlimited {
                    let (subscription, effect) = lock.withLockUnchecked{
                        let effect = if $0.demandState.pending == .unlimited {
                            $0.demandState.transition(.resume(.none))
                        } else {
                            // reclaim discarded demand
                            $0.demandState.transition(.resume(.max(1)))
                        }
                        let subscription = $0.upstreamSubscription.subscription
                        return (subscription, effect)
                    }
                    if let subscription {
                        subscription.request(.max(1))
                        effect?.run()
                    } else {
                        throw CancellationError()
                    }
                }
                return false
            case .failure(let error):
                send(completion: .failure(.segment(error)))
                throw CancellationError()
            case .success(let value):
                try send(value)
            }
            return true
        }
        
        private func localTask(
            group: inout some CompatThrowingDiscardingTaskGroup
        ) async throws {
            for await result in valueSource.stream {
                switch result {
                case .failure(let failure):
                    send(completion: .failure(.upstream(failure)))
                    throw CancellationError()
                case .success(let value):
                    let isSuccess = group.addTaskUnlessCancelled(priority: nil) {
                        let segment = try await makeSegment(value)
                        var iterator = segment.makeAsyncIterator()
                        while true {
                            let isUnlimited = try await nextDemand()
                            if isUnlimited {
                                while try await processNextSegment(iterator: &iterator) {
                                }
                                return
                            } else {
                                let hasNext = try await processNextSegment(iterator: &iterator)
                                if !hasNext {
                                    return
                                }
                            }
                        }
                    }
                    if !isSuccess {
                        throw CancellationError()
                    }
                    
                }
            }
        }
        
    }
    
}
