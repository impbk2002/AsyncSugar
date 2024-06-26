//
//  File.swift
//  
//
//  Created by 박병관 on 5/29/24.
//

import Foundation

internal
enum TaskValueContinuation: Sendable {
    
    case waiting
    case suspending(UnsafeContinuation<Void,any Error>)
    case cached(Task<Void,Never>)
    case cancelled
    case finished
    
    enum Event: Sendable {
        case suspend(UnsafeContinuation<Void,any Error>)
        case resume(Task<Void,Never>)
        case finish
        case cancel
    }
    
    enum Effect: Sendable {
        case raise(UnsafeContinuation<Void,any Error>)
        case resume(UnsafeContinuation<Void,any Error>)
        case cancel(Task<Void,Never>)
        
        consuming func run() {
            switch consume self {
            case .raise(let unsafeContinuation):
                unsafeContinuation.resume(throwing: CancellationError())
            case .resume(let unsafeContinuation):
                unsafeContinuation.resume()
            case .cancel(let task):
                task.cancel()
            }
        }
    }
    
    mutating func transition(_ event: consuming Event) -> Effect? {
        switch consume event {
        case .suspend(let unsafeContinuation):
            return suspend(unsafeContinuation)
        case .resume(let task):
            return resume(task)
        case .finish:
            return onFinish()
        case .cancel:
            return onCancel()
        }
    }
    
    func shouldMutate(_ event: Event) -> Bool {
        switch self {
        case .waiting:
            return true
        case .suspending(let unsafeContinuation):
            if case .suspend(_) = event {
                return false
            } else {
                return true
            }
        case .cached(let task):
            if case .resume(_) = event {
                return false
            } else {
                return true
            }
        case .cancelled, .finished:
            return false
            
        }
    }
    
    private mutating func suspend(_ continuation:UnsafeContinuation<Void,any Error>) -> Effect? {
        switch self {
        case .waiting:
            self = .suspending(continuation)
            return nil
        case .suspending(let oldValue):
            self = .suspending(continuation)
            assertionFailure("received continuation more than Once")

            return .raise(oldValue)
        case .cancelled:
            return .raise(continuation)
        case .cached(_):
            fallthrough
        case .finished:
            return .resume(continuation)
        }
    }
    
    private mutating func resume(_ task:Task<Void,Never>) -> Effect? {
        switch self {
        case .waiting:
            self = .cached(task)
            return nil
        case .suspending(let unsafeContinuation):
            self = .cached(task)
            return .resume(unsafeContinuation)
        case .cancelled:
            return .cancel(task)
        case .cached(let oldValue):
            self = .cached(task)
            assertionFailure("can not handle Task on cached state")
            return .cancel(oldValue)
        case .finished:
            return nil
        }
    }
    
    private mutating func onCancel() -> Effect? {
        switch self {
        case .cancelled:
            fallthrough
        case .waiting:
            self = .cancelled
            fallthrough
        case .finished:
            return nil
        case .suspending(let unsafeContinuation):
            self = .cancelled
            return .raise(unsafeContinuation)
        case .cached(let task):
            self = .cancelled
            return .cancel(task)
        }
    }
    
    private mutating func onFinish() -> Effect? {
        switch self {
        case .suspending(let unsafeContinuation):
            self = .finished
            return .resume(unsafeContinuation)
        case .cached(_):
            fallthrough
        case .waiting:
            self = .finished
            fallthrough
        case .cancelled:
            fallthrough
        case .finished:
            return nil
        }
    }
    

    
}
