//
//  AsyncFlatMapDemandState.swift
//
//
//  Created by 박병관 on 6/7/24.
//

import Foundation
import Combine
import DequeModule

struct AsyncFlatMapDemandState: Sendable {
    
    private var suspended:Deque<Element> = []
    private(set) var pending = Subscribers.Demand.none
    private var isInterrupted = false
    typealias Element = UnsafeContinuation<Bool,any Error>
    
    enum Event {
        
        case interrupt
        case resume(Subscribers.Demand)
        case suspend(Element)
    }
    
    enum Effect {
        
        case resume(Deque<Element>, Bool)
        case raise(Deque<Element>)
        
        func run() {
            switch self {
            case .resume(let array, let demand):
                array.forEach{
                    $0.resume(returning: demand)
                }
            case .raise(let array):
                array.forEach{
                    $0.resume(throwing: CancellationError())
                }
            }
        }
    }
    
    mutating func transition(_ event:Event) -> Effect? {
        switch event {
        case .interrupt:
            return interrupt()
        case .resume(let demand):
            return resume(demand)
        case .suspend(let unsafeContinuation):
            return suspend(unsafeContinuation)
        }
    }
    
    private mutating func resume(_ demand:Subscribers.Demand) -> Effect? {
        if isInterrupted {
            return nil
        }
        pending += demand
        return populateResume()
    }
    
    private mutating func suspend(_ continuation: Element) -> Effect? {
        if isInterrupted {
            return .raise([continuation])
        }
        suspended.append(continuation)
        
        return populateResume()
    }
    
    
    private mutating func populateResume() -> Effect? {
        // unlimited
        guard let max = pending.max else {
            let jobs = suspended
            // zero capacity storage creation
            suspended = []
            return .resume(jobs, true)
        }
        if max == 0 || suspended.count == 0 {
            return nil
        }
        var buffer:Deque<Element> = []
        var count = min(suspended.count, max)
        pending -= count
        buffer.reserveCapacity(count)
        while let token = suspended.popFirst(), count > 0 {
            count -= 1
            buffer.append(token)
        }
        return .resume(buffer, false)
        
    }
    
    private mutating func interrupt() -> Effect? {
        pending = .none
        isInterrupted = true
        let jobs = suspended
        suspended = []
        return .raise(jobs)
    }
    
}
