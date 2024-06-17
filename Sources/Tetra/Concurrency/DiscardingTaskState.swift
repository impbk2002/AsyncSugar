//
//  DiscardingTaskState.swift
//  
//
//  Created by 박병관 on 6/17/24.
//

enum DiscardingTaskState {
    
    case waiting
    case suspend(UnsafeContinuation<Void,any Error>)
    case cancel
    case finish
    
    enum Effect {
        case resume(UnsafeContinuation<Void,any Error>)
        case raise(UnsafeContinuation<Void,any Error>)
        
        func run() {
            switch self {
            case .resume(let unsafeContinuation):
                unsafeContinuation.resume()
            case .raise(let unsafeContinuation):
                unsafeContinuation.resume(throwing: CancellationError())
            }
        }
    }
    
    enum Event {
        case cancel
        case suspend(UnsafeContinuation<Void,any Error>)
        case finish
    }
    
    mutating func transition(_ event:Event) -> Effect? {
        switch event {
        case .cancel:
            return cancel()
        case .suspend(let unsafeContinuation):
            return suspend(unsafeContinuation)
        case .finish:
            return finish()
        }
    }
    
    private mutating func suspend(_ cont:UnsafeContinuation<Void, any Error>) -> Effect? {
        switch self {
        case .waiting:
            self = .suspend(cont)
            return nil
        case .suspend(let unsafeContinuation):
            self = .suspend(cont)
            assertionFailure("received suspend more than once")
            return .raise(unsafeContinuation)
        case .cancel:
            return .raise(cont)
        case .finish:
            return .resume(cont)
        }
    }
    
    private mutating func finish() -> Effect? {
        switch self {
        case .waiting:
            self = .finish
            return nil
        case .suspend(let unsafeContinuation):
            self = .finish
            return .resume(unsafeContinuation)
        case .cancel:
            return nil
        case .finish:
            return nil
        }
    }
    
    private mutating func cancel() -> Effect? {
        switch self {
        case .waiting:
            self = .cancel
            return nil
        case .suspend(let unsafeContinuation):
            self = .cancel
            return .raise(unsafeContinuation)
        case .cancel:
            return nil
        case .finish:
            return nil
        }
    }
    
}
