//
//  SchedulerTimePublisher.swift
//  
//
//  Created by pbk on 2022/12/19.
//

import Foundation
@preconcurrency import Combine
internal import CriticalSection


public struct SchedulerTimePublisher<T:Scheduler>: Publisher {
    
    public typealias Output = T.SchedulerTimeType
    public typealias Failure = Never
    
    public var scheduler:T
    public var interval:T.SchedulerTimeType.Stride
    public var tolerance:T.SchedulerTimeType.Stride? = nil
    public var options:T.SchedulerOptions? = nil
    
    public init(scheduler: T, interval: T.SchedulerTimeType.Stride, tolerance: T.SchedulerTimeType.Stride? = nil, options: T.SchedulerOptions? = nil) {
        self.scheduler = scheduler
        self.interval = interval
        self.tolerance = tolerance
        self.options = options
    }
    
    public func receive<S>(subscriber: S) where S : Subscriber, Never == S.Failure, Output == S.Input {
        subscriber.receive(
            subscription: Inner(
                publisher: self, subscriber: subscriber
            )
        )
    }

    private struct State<S:Subscriber> where S.Input == Output, S.Failure == Failure {
        
        var subscriber:S? = nil
        var request:Subscribers.Demand = .none
        var token = CancellabeState.waiting
        
    }
    
    final class Inner<S:Subscriber>: Subscription, CustomStringConvertible, CustomPlaygroundDisplayConvertible where S.Input == Output, S.Failure == Failure  {
        
        var description: String {
            "SchedulerTimePublisher"
        }
        
        var playgroundDescription: Any { description }
        
        private let publisher:SchedulerTimePublisher<T>
        private let lock:some UnfairStateLock<State<S>> = createUncheckedStateLock(uncheckedState: State<S>())
        
        init(publisher: SchedulerTimePublisher<T>, subscriber:S) {
            self.publisher = publisher
            lock.withLockUnchecked {
                $0.subscriber = subscriber
            }
        }
        
        func request(_ demand: Subscribers.Demand) {
            let shouldStart = lock.withLock{
                $0.request += demand
                return $0.token == .waiting
            }
            if shouldStart {
                let token = publisher.scheduler.schedule(after: publisher.scheduler.now, interval: publisher.interval, tolerance: publisher.tolerance ?? publisher.scheduler.minimumTolerance, options: publisher.options) { [weak self] in
                    self?.fire()
                }
                let oldValue = lock.withLockUnchecked{
                    let oldValue = $0.token
                    switch oldValue {
                    case .waiting, .cancellable:
                        $0.token = .cancellable(.init(token))
                    case .finished:
                        $0.request = .none
                        break
                    }
                    return oldValue
                }
                if case let .cancellable(cancellable) = oldValue {
                    cancellable.cancel()
                }
            }
        }
        
        private func fire() {
            let subscriber = lock.withLockUnchecked{
                if $0.request > .none {
                    $0.request -= 1
                    return $0.subscriber
                }
                return nil
            }
            if let demand = subscriber?.receive(publisher.scheduler.now), demand > .none {
                lock.withLock{
                    $0.request += demand
                }
            }
        }
        
        func cancel() {
            let (_, token) = lock.withLockUnchecked{
                let cancellable = $0.token
                $0.token = .finished
                $0.request = .none
                let sub = $0.subscriber
                $0.subscriber = nil
                return (sub, cancellable)
            }
            if case let .cancellable(cancellable) = token {
                cancellable.cancel()
            }
        }
        
    }
    
    private enum CancellabeState: Equatable {
        
        case waiting
        case cancellable(AnyCancellable)
        case finished
        
    }
    
}
