//
//  Dispatch+Extension.swift
//  
//
//  Created by pbk on 2023/01/26.
//

import Foundation
import Dispatch

public extension TetraExtension where Base == Task<Never,Never> {
    
    /**
     Suspends the current task until the given deadline within a tolerance.
     - Parameters:
        - Throws: `CancellationError` if task is cancelled
     */
    @inlinable
    static func sleep(deadline: DispatchTime, tolerance: DispatchTimeInterval? = nil) async throws {
        let source = DispatchSource.makeTimerSource(flags: [.strict])
        
        source.schedule(deadline: deadline, repeating: .never, leeway: tolerance ?? .nanoseconds(0))
        try await dispatchTimerSleep(source: source)
    }
    
    /**
     Suspends the current task until the given deadline within a tolerance.
     - Parameters:
        - Throws: `CancellationError` if task is cancelled
     */
    @inlinable
    static func sleep(wallDeadline: DispatchWallTime, tolerance: DispatchTimeInterval? = nil) async throws {
        let source = DispatchSource.makeTimerSource(flags: [.strict])
        source.schedule(wallDeadline: wallDeadline, repeating: .never, leeway: tolerance ?? .nanoseconds(0))
        try await dispatchTimerSleep(source: source)
    }
    
}


@usableFromInline
internal func dispatchTimerSleep(source:DispatchSourceTimer) async throws {
    
    let lock = createCheckedStateLock(checkedState: DispatchSleepState.waiting)
    source.setEventHandler{
        lock.withLock{
            $0.take()
        }?.resume()
    }
    source.setCancelHandler{
        lock.withLock{
            $0.take()
        }?.resume(throwing: CancellationError())
    }
    return try await withTaskCancellationHandler {
        return try await withUnsafeThrowingContinuation{ continuation in
            let snapShot = lock.withLock{
                let oldValue = $0
                switch oldValue {
                case .finished:
                    break
                case .waiting, .continuation:
                    $0 = .continuation(continuation)
                    
                }
                return oldValue
            }
            switch snapShot {
            case .continuation(let unsafeContinuation):
                assertionFailure("reached unexpected state")
                unsafeContinuation.resume(throwing: CancellationError())
            case .finished:
                continuation.resume(throwing: CancellationError())
            case .waiting:
                break
            }
            source.activate()
        }
    } onCancel: {
        lock.withLock{
            $0.take()
        }?.resume(throwing: CancellationError())
        source.cancel()
    }

}


private
enum DispatchSleepState: Sendable {
    
    case waiting
    case continuation(UnsafeContinuation<Void,Error>)
    case finished
    
    mutating func take() -> UnsafeContinuation<Void,Error>? {
        switch self {
        case .waiting, .finished:
            self = .finished
            return nil
        case .continuation(let unsafeContinuation):
            self = .finished
            return unsafeContinuation
        }
    }
}
