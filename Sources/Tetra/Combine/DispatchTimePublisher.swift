//
//  DispatchTimePublisher.swift
//  
//
//  Created by pbk on 2022/12/09.
//

import Foundation
import Dispatch
import Combine

extension DispatchSource: TetraExtended {}

public extension TetraExtension where Base:DispatchSource {
    
    static func timePublisher(
        interval: DispatchTimeInterval,
        leeway:DispatchTimeInterval = .nanoseconds(0),
        timerFlags: DispatchSource.TimerFlags = [],
        qos:DispatchQoS = .unspecified,
        workFlags: DispatchWorkItemFlags = [],
        queue: DispatchQueue? = nil) -> Publishers.MakeConnectable<DispatchTimePublisher> {
            DispatchTimePublisher(
                interval: interval,
                leeway: leeway,
                timerFlags: timerFlags,
                qos: qos,
                workFlags: workFlags,
                queue: queue
            ).makeConnectable()
        }
}


/**
    TimePublisher which emits `DisptachTime` using `DispatchSourceTimer`
 
 */
public struct DispatchTimePublisher: Publisher {
    
    public typealias Output = DispatchTime
    public typealias Failure = Never
    
    var interval: DispatchTimeInterval
    var leeway:DispatchTimeInterval = .nanoseconds(0)
    var timerFlags: DispatchSource.TimerFlags = []
    var qos:DispatchQoS = .unspecified
    var workFlags: DispatchWorkItemFlags = []
    var queue: DispatchQueue? = nil
    
    public init(
        interval: DispatchTimeInterval,
        leeway: DispatchTimeInterval = .nanoseconds(0),
        timerFlags: DispatchSource.TimerFlags = [],
        qos: DispatchQoS = .unspecified,
        workFlags: DispatchWorkItemFlags = [],
        queue: DispatchQueue? = nil
    ) {
        self.interval = interval
        self.leeway = leeway
        self.timerFlags = timerFlags
        self.qos = qos
        self.workFlags = workFlags
        self.queue = queue
    }
    
    public func receive<S>(subscriber: S) where S : Subscriber, Never == S.Failure, DispatchTime == S.Input {
        Inner(
            interval: interval,
            leeway: leeway,
            qos: qos,
            workFlags: workFlags,
            timerFlags: timerFlags,
            queue: queue
        )
        .attach(subscriber)
    }
    
}

extension DispatchTimePublisher {
    
    private final class Inner<S:Subscriber>:Subscription, CustomStringConvertible, CustomPlaygroundDisplayConvertible where S.Input == DispatchTime, S.Failure == Never {
        
        var description: String { "DispatchTimer" }
        
        var playgroundDescription: Any { description }
        
        private let lock:some UnfairStateLock<State> = createUncheckedStateLock(uncheckedState: State())
        private let source: DispatchSourceTimer
        
        struct State {
            
            var request = Subscribers.Demand.none
            var started = false
            var subscriber:S? = nil
        }
        
        fileprivate init(
            interval: DispatchTimeInterval,
            leeway: DispatchTimeInterval,
            qos: DispatchQoS,
            workFlags: DispatchWorkItemFlags,
            timerFlags: DispatchSource.TimerFlags,
            queue: DispatchQueue?
        ) {
            self.source = DispatchSource.makeTimerSource(flags: timerFlags, queue: queue)
            source.schedule(deadline: .now(), repeating: interval, leeway: leeway)
            source.setEventHandler(qos: qos, flags: workFlags) { [weak self] in
                self?.fire(shouldFinish: interval == .never)
            }
        }
        
        func cancel() {
            let _ = lock.withLockUnchecked {
                $0.request = .none
                let sub = $0.subscriber
                $0.subscriber = nil
                return sub
            }
            source.cancel()
            source.setEventHandler(handler: nil)
        }
        
        func request(_ demand: Subscribers.Demand) {
           let startTimer = lock.withLock{
                $0.request += demand
                if $0.request > 0 && !$0.started {
                    $0.started = true
                   return true
                } else {
                    return false
                }
            }
            if startTimer {
                source.activate()
            }
        }
        
        func attach(_ subscriber:S) {
            lock.withLockUnchecked {
                $0.subscriber = subscriber
            }
            subscriber.receive(subscription: self)
        }
        
        func fire(shouldFinish:Bool = false) {
            let time = DispatchTime.now()
            let sub = lock.withLockUnchecked{
                if $0.request > 0 {
                    $0.request -= 1
                } else {
                    return nil as S?
                }
                return $0.subscriber
            }
            guard let sub else { return }
            let demand = sub.receive(time)
            if shouldFinish {
                sub.receive(completion: .finished)
                lock.withLock { state in
                    state.subscriber = nil
                    state.request = .none
                }
                source.setEventHandler(handler: nil)
            } else if demand > .none {
                lock.withLock{
                    $0.request += demand
                }
            }
        }
    }
    
}
