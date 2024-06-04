//
//  AsyncSequencePublisher.swift
//  
//
//  Created by pbk on 2022/09/16.
//

import Foundation
@preconcurrency import Combine

public extension AsyncSequence where Self:Sendable {
    
    var tetra:TetraExtension<Self> {
        .init(self)
    }
    
}

public extension TetraExtension where Base: AsyncSequence & Sendable {
    
    @inlinable
    var publisher:AsyncSequencePublisher<Base> {
        .init(base: base)
    }
    
}

public struct AsyncSequencePublisher<Base: AsyncSequence & Sendable>: Publisher {

    public typealias Output = Base.Element
    public typealias Failure = Base.Failure
    
    public var base:Base
    
    @inlinable
    public init(base: Base) {
        self.base = base
    }
    
    public func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Base.Element == S.Input {
        let processor = Inner(subscriber: subscriber)
        let task = Task { [base] in
            await processor.run(base)
        }
        processor.resumeCondition(task)
    }
    
}

extension AsyncSequencePublisher: Sendable where Base: Sendable, Base.Element: Sendable {}

extension AsyncSequencePublisher {
    
    internal struct TaskState<S:Subscriber> where S.Input == Output, S.Failure == Failure {
        
        var subscriber:S? = nil
        var condition = TaskValueContinuation.waiting
        
    }
    
    internal struct Inner<S:Subscriber>: Subscription, CustomStringConvertible, CustomPlaygroundDisplayConvertible, Sendable where S.Input == Output, S.Failure == Failure {
        
        var description: String { "AsyncSequence" }
        
        var playgroundDescription: Any { description }
        let combineIdentifier = CombineIdentifier()
        private let demandSource = AsyncStream<Subscribers.Demand>.makeStream()
        private let state:some UnfairStateLock<TaskState<S>> = createUncheckedStateLock(uncheckedState: .init())
        
        init(subscriber:S) {
            state.withLockUnchecked{
                $0.subscriber = subscriber
            }
        }
        
        
        func cancel() {
            state.withLock{
                return $0.condition.transition(.cancel)
            }?.run()
        }
        
        func request(_ demand: Subscribers.Demand) {
            demandSource.continuation.yield(demand)
        }
        
        private func send(_ value:S.Input) -> Subscribers.Demand? {
            state.withLockUnchecked{ $0.subscriber }?.receive(value)
        }
        
        private func send(completion: Subscribers.Completion<S.Failure>?) {
            let subscriber = state.withLockUnchecked{
                let old = $0.subscriber
                $0.subscriber = nil
                return old
            }
            if let completion {
                subscriber?.receive(completion: completion)
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
        
        func run(_ base: Base) async {
            let token:Void? = try? await waitForCondition()
            defer {
                demandSource.continuation.finish()
            }
            if token == nil {
                withUnsafeCurrentTask { $0?.cancel() }
            }
            defer { clearCondition() }
            state.withLockUnchecked{
                $0.subscriber
            }?.receive(subscription: self)
            var iterator = base.makeAsyncIterator()
            await withTaskCancellationHandler {
                for await var pending in demandSource.stream {
                    while pending > .none {
                        pending -= 1
                        guard let result = await wrapToResult(&iterator) else {
                            send(completion: .finished)
                            return
                        }
                        switch result {
                        case .failure(let error):
                            send(completion: .failure(error))
                            return
                        case .success(let value):
                            if let newDemand = send(value) {
                                pending += newDemand
                            } else {
                                return
                            }
                        }
                    }
                }
                send(completion: .finished)
            } onCancel: {
                demandSource.continuation.finish()
                send(completion: nil)
            }

        }
        
    }
    
}
