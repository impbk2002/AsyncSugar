//
//  File.swift
//
//
//  Created by 박병관 on 6/7/24.
//

import Foundation
@preconcurrency import Combine
internal import BackPortAsyncSequence
internal import CriticalSection
internal import BackportDiscardingTaskGroup

struct AsyncFlatMap<Upstream:Publisher, Segment:AsyncSequence>: Publisher where Upstream.Output:Sendable, Segment.AsyncIterator.Err == Upstream.Failure, Segment.AsyncIterator: TypedAsyncIteratorProtocol {
    
    typealias Output = Segment.Element
    typealias Failure = Upstream.Failure
    typealias Transform = @Sendable (Upstream.Output) async throws(Failure) -> Segment
    var priority: TaskPriority? = nil
    let taskExecutor: (any Executor)?
    var maxTasks:Subscribers.Demand
    let upstream:Upstream
    let transform:Transform
    
    func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Segment.Element == S.Input {
        let processor = Inner(maxTasks: maxTasks, subscriber: subscriber, transform: transform)
        let task = if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *), let executor = taskExecutor as? (any TaskExecutor) {
            Task(executorPreference: executor, priority: priority, operation: processor.run)
        } else {
            Task(priority: priority, operation: processor.run)
        }
        processor.resumeCondition(task)
        upstream.subscribe(processor)
    }
    
    @usableFromInline
    init(
        priority: TaskPriority? = nil,
        maxTasks: Subscribers.Demand,
        upstream: Upstream,
        transform: @escaping Transform
    ) {
        self.priority = priority
        self.maxTasks = maxTasks
        self.upstream = upstream
        self.transform = transform
        self.taskExecutor = nil
    }
    
    @usableFromInline
    init<Source>(
        priority: TaskPriority? = nil,
        maxTasks: Subscribers.Demand,
        upstream: Upstream,
        transform: @escaping @Sendable (Upstream.Output) async throws(Failure) -> Source
    ) where Source: AsyncSequence, Segment == LegacyTypedAsyncSequence<Source>, Failure == any Error {
        self.priority = priority
        self.maxTasks = maxTasks
        self.upstream = upstream
        self.transform = { (value) throws(Failure) in
            try await .init(base: transform(value))
        }
        self.taskExecutor = nil
    }

    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @usableFromInline
    init<Source>(
        priority: TaskPriority? = nil,
        taskExecutor: (any TaskExecutor)? = nil,
        maxTasks: Subscribers.Demand,
        upstream: Upstream,
        typedTransform: @escaping @Sendable (Upstream.Output) async throws(Failure) -> Source
    ) where Source: AsyncSequence, Segment == WrappedAsyncSequence<Source> {
        self.priority = priority
        self.maxTasks = maxTasks
        self.upstream = upstream
        self.transform = { (value) throws(Failure) in
            try await .init(base: typedTransform(value))
        }
        self.taskExecutor = taskExecutor
    }

    
}

extension AsyncFlatMap {
    
    struct Inner<Down:Subscriber>: Subscriber, Sendable, Subscription, CustomStringConvertible, CustomPlaygroundDisplayConvertible
    where Segment.Element == Down.Input, Down.Failure == AsyncFlatMap.Failure {
        
        typealias Transformer = @Sendable (Upstream.Output) async throws(Failure) -> Segment
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
            if #available(iOS 17.0, tvOS 17.0, macCatalyst 17.0, macOS 14.0, watchOS 10.0, visionOS 1.0, *) {
                try? await withThrowingDiscardingTaskGroup {  group in
                    defer { terminateStream() }
                    await localTask(
                        group: &group
                    )
                }
            } else {
                try? await simuateThrowingDiscardingTaskGroup(isolation: SafetyRegion()) { barrier, group in
                    defer { terminateStream() }
                    nonisolated(unsafe)
                    var unsafe = Suppress(value: group)
                    await localTask(isolation: barrier, group: &unsafe.value)
                    group = unsafe.value
                }
            }
            send(completion: .finished, shouldCancel: false)

        }
        
        var playgroundDescription: Any { description }
        
        var description: String { "AsyncFlatMap" }
        
        
        func receive(_ input: Input) -> Subscribers.Demand {
            valueSource.continuation.yield(.success(input))
            return .none
        }
        
        func receive(completion: Subscribers.Completion<Upstream.Failure>) {
            lock.withLockUnchecked{
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
        
        func receive(subscription: any Subscription) {
            let (effect, requestValue) = lock.withLockUnchecked{
                let requestValue:Bool
                switch $0.upstreamSubscription {
                case .waiting, .suspending:
                    requestValue = true
                default:
                    requestValue = false
                }
                let effect = $0.upstreamSubscription.transition(.resume(subscription))
                return (effect, requestValue)
            }
            (consume effect)?.run()
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
            send(completion: nil, shouldCancel: true)
        }
        
        // almost uncontented call
        private func handleDownStream(
            isolation actor: isolated some Actor,
            event: Result<Suppress<Output>?, Failure>
        ) async {
            switch event {
            case .success(.none):
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
                    }
                }
            case .success(let success?):
                send(
                    isolation: actor,
                    success.value
                )
                return
            case .failure(let failure):
                send(completion: .failure(failure), shouldCancel: true)
                return
            }
            return
        }
        
        // almost uncontented call
        private func send(
            completion: Subscribers.Completion<Failure>?,
            shouldCancel:Bool
        ) {
            valueSource.continuation.finish()
            let (subscriber, effect, interruption, taskEffect) = lock.withLockUnchecked{
                let old = $0.subscriber
                $0.subscriber = nil
                let effect = if shouldCancel {
                    $0.upstreamSubscription.transition(.cancel)
                } else {
                    $0.upstreamSubscription.transition(.finish)
                }
                let interruption = $0.demandState.transition(.interrupt)
                let taskEffect = if shouldCancel {
                    $0.taskCondition.transition(.cancel)
                } else {
                    $0.taskCondition.transition(.finish)
                }
                return (old, effect, interruption, taskEffect)
            }
            // ensure compiler it is good to destroy the objects
            (consume effect)?.run()
            (consume interruption)?.run()
            (consume taskEffect)?.run()
            if let completion {
                (consume subscriber)?.receive(completion: completion)
            }
        }
        
        // almost uncontented call
        private func send(
            isolation actor: isolated some Actor,
            _ value:Down.Input
        ) {
            // use lock but this is isolated so we expect uncontended
            let subscriber = lock.withLockUnchecked {
                $0.subscriber
            }
            guard let newDemand = subscriber?.receive(value) else {
                return
            }
            lock.withLockUnchecked{
                $0.demandState.transition(.resume(newDemand))
            }?.run()
        }
        
        // contention case
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
        
        // contention case
        func resumeCondition(_ task:Task<Void,Never>) {
            lock.withLock{
                $0.taskCondition.transition(.resume(task))
            }?.run()
        }
        
        // contention case
        private func waitForCondition() async throws {
            try await withUnsafeThrowingContinuation{ continuation in
                lock.withLock{
                    $0.taskCondition.transition(.suspend(continuation))
                }?.run()
            }
        }
        // almost uncontented call
        private func clearCondition() {
            lock.withLock{
                $0.taskCondition.transition(.finish)
            }?.run()
        }
        
        private func terminateStream() {
            valueSource.continuation.finish()
        }
        
        private func makeSegment(_ input:Upstream.Output) async -> sending Result<Segment, Failure> {
            let result:Result<Segment,Failure>
            do {
                let seg = try await transform(input)
                result = .success(seg)
            } catch {
                result = .failure(error )
            }
            return result
        }
        
        // almost uncontented call
        /// whether demand is unlimited
        /// - Returns: `true` if demand is unlimited, `false` if demand is just `1`.
        /// - throws: `CancellationError` if internal state reached cancellation
        private func nextDemand(
            barrier:isolated some Actor
        ) async throws -> Bool {
            try await withUnsafeThrowingContinuation { continuation in
                lock.withLockUnchecked{
                    $0.demandState.transition(.suspend(continuation))
                }?.run()
            }
        }
        

        /// process next segment and send event to downstream
        /// - Returns: `false` if iterator reached termination otherwise `true`
        private func processNextSegment(
            iterator: inout Segment.AsyncIterator,
            barrier: some Actor
        ) async -> Bool {
//            let result:Result<Output, Failure>?
            do throws(Failure) {
//                let value = try await iterator.next(isolation: nil)
                
                if let value = try await iterator.next(isolation: nil) {
                    await handleDownStream(isolation: barrier, event: .success(.init(value: value)))
                    return true
                } else {
                    await handleDownStream(isolation: barrier, event: .success(.none))
                    return false
                }
            } catch {
                await handleDownStream(isolation: barrier, event: .failure(error))
                return false
            }
        }
        
        private func localTask(
            isolation actor: isolated (any Actor)? = #isolation,
            group: inout some CompatDiscardingTaskGroup<any Error>
        ) async {
            let barrier = actor as? SafetyRegion ?? .init()
            for await result in valueSource.stream {
                if await barrier.isFinished {
                    break
                }
                switch result {
                case .failure(let failure):
                    let block = { (actor: isolated (any Actor)?) in
                        send(completion: .failure(failure), shouldCancel: false)
                    }
                    await block(barrier)
                    return
                case .success(let value):
                    let isSuccess = group.addTaskUnlessCancelled(priority: nil) {
                        let segment:Segment
                        do throws(Failure) {
                            segment = try await transform(value)
                        } catch {
                            await barrier.markDone()
                            await handleDownStream(
                                isolation: barrier,
                                event: .failure(error)
                            )
                            return
                        }
                        var iterator = segment.makeAsyncIterator()
                        while true {
                            let isUnlimited = try await nextDemand(barrier: barrier)
                            if isUnlimited {
                                while await processNextSegment(iterator: &iterator, barrier: barrier) {
                                    
                                }
                                return
                            } else {
                                let hasNext = await processNextSegment(iterator: &iterator, barrier: barrier)
                                if !hasNext {
                                    return
                                }
                            }
                        }
                    }
                    if !isSuccess {
                        return
                    }
                    
                }
            }
        }
        
    }
    
}
