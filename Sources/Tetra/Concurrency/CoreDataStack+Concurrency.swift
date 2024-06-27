//
//  CoreDataStack+Concurrency.swift
//  
//
//  Created by pbk on 2022/12/07.
//

import Foundation
import _Concurrency

#if canImport(CoreData)
import CoreData
import Namespace



extension TetraExtension where Base: NSPersistentStoreCoordinator {
    
    @usableFromInline
    internal func _perform<T,Failure:Error>(_ body: () throws(Failure) -> T) async throws(Failure) -> T {
        let value:Result<T,Failure> = await withoutActuallyEscaping(body) { escapingClosure in
            let block = ClosureHolder(closure: escapingClosure)
            defer {
                withExtendedLifetime(block, {})
            }
            return await withUnsafeContinuation { continuation in
                base.perform { [unowned block, continuation] in
                    continuation.resume(returning: block())
                }
            }
        }
        return try value.get()
    }
    
    @inlinable
    public func perform<T>(_ body: () throws -> T) async rethrows -> T {
        return if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
            try await withoutActuallyEscaping(body) { 
                let block = ClosureHolder(closure: $0)
                defer {
                    withExtendedLifetime(block, {})
                }
                return try await base.perform{ [unowned block] in
                    try block().get()
                }
            }
        } else {
            try await _perform(body)
        }
    }
    
    @usableFromInline
    internal func _performAndWait<T,Failure:Error>(_ body: () throws(Failure) -> T) throws(Failure) -> T {
        var result:Result<T,Failure>? = nil
        base.performAndWait {
            result = wrapToResult(body)
        }
        guard let result else {
            preconditionFailure("performAndWait didn't run")
        }
        return try result.get()
    }
    
    @inlinable
    public func performAndWait<T>(_ body: () throws -> T) rethrows -> T {
        return if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
            try base.performAndWait(body)
        } else {
            try _performAndWait(body)
        }
    }
    
}

@usableFromInline
internal protocol ObjcLocking:NSLocking {
    
    func tryLock() -> Bool
}
// To suppress deprecation
extension NSManagedObjectContext: ObjcLocking {}

extension TetraExtension where Base: NSManagedObjectContext {
    
    /// Try to submits a closure to the context’s queue for synchronous execution.
    /// - Parameter body: The closure to perform.
    /// - Returns: `nil` if it can not run immedately
    /// - throws: rethrow the error if it can run immedately
    ///
    /// This method supports reentrancy — meaning it’s safe to call the method again, from within the closure, before the previous invocation completes.
    @usableFromInline
    internal func _performImmediate<T,Failure:Error>(
        _ body: () throws(Failure) -> T
    ) throws(Failure) -> Result<T,Never>? {
        // Suppress deprecation
        let lock:any ObjcLocking = base
        // NSManagedObjectContext has Reentrant Locking
        guard lock.tryLock() else { return nil }
        defer { lock.unlock() }
        let value = try _performAndWait(body)
        return .success(value)
    }
    
    @usableFromInline
    internal func _performEnqueue<T,Failure:Error>(
        _ body: () throws(Failure) -> T
    ) async throws(Failure) -> T {
        let result: Result<T,Failure> = await withoutActuallyEscaping(body) { escapingClosure in
            let holder = ClosureHolder(closure: escapingClosure)
            defer {
                withExtendedLifetime(holder, {})
            }

            return await withUnsafeContinuation { continuation in
                base.perform{ [unowned holder, continuation] in
                    nonisolated(unsafe)
                    let result = wrapToResult(holder.closure)
                    continuation.resume(returning: result)
                }
            }
        }
        return try result.get()
    }
    
    /// Asynchronously performs the specified closure on the context’s queue.
    @inlinable
    @_unsafeInheritExecutor
    public func perform<T>(
        schedule:CoreDataScheduledTaskType = .immediate,
        _ body: () throws -> T
    ) async rethrows -> T {
        /*
         
         Since this method and NSManagedObjectContext peform has no actor preference and isolation restriction.
         These two are always called on global nonisolated context (Actor switching happen).
         Which means that `immediate` execution option is totally no-op.
         
         
         - `_performImmediate:` is never called when using `NSManagedObjectContext.perform(schedule: .immediate)` in iOS 15 ~ iOS 17
         - @_unsafeInheritExecutor do fix the above problem
         */
        return if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
            try await withoutActuallyEscaping(body) {
                let block = ClosureHolder(closure: $0)
                defer {
                    withExtendedLifetime(block, {})
                }
                return try await base.perform(schedule: schedule.platformValue) { [unowned block] in
                    return try block().get()
                }
            }
        } else if schedule == .enqueued {
            try await _performEnqueue(body)
        } else {
            if let result = try _performImmediate(body) {
                result.get()
            } else {
                try await _performEnqueue(body)
            }
        }
    }
    
    @usableFromInline
    internal func _performAndWait<T,Failure:Error>(_ body: () throws(Failure) -> T) throws(Failure) -> T {
        var result:Result<T,Failure>? = nil
        base.performAndWait {
            result = wrapToResult(body)
        }
        guard let result else {
            preconditionFailure("performAndWait didn't run")
        }
        return try result.get()
    }
    
    @inlinable
    public func performAndWait<T>(_ body: () throws -> T) rethrows -> T {
        return if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
            try base.performAndWait(body)
        } else {
            try _performAndWait(body)
        }
    }
    
}

extension TetraExtension where Base: NSPersistentContainer {
    
    @inlinable
    public func performBackground<T>(_ body: (NSManagedObjectContext) throws -> T) async rethrows -> T {
        return if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
            try await withoutActuallyEscaping(body) {
                let block = CoreDataContextClosureHolder(closure: $0)
                defer { withExtendedLifetime(block, {}) }
                return try await base.performBackgroundTask{ [unowned block] in
                    try block($0).get()
                }
            }
        } else {
            try await _performBackground(body)
        }
    }
    
    @inline(__always)
    @usableFromInline
    internal func _convertToResult<T,Failure:Error>(_ context:NSManagedObjectContext, _ body: (NSManagedObjectContext) throws(Failure) -> T) -> Result<T,Failure> {
        do {
            let value = try body(context)
            return .success(value)
        } catch {
            return .failure(error)
        }
    }

    
    @usableFromInline
    internal func _performBackground<T,Failure:Error>(_ body: (NSManagedObjectContext) throws(Failure) -> T) async throws(Failure) -> T {
        let result:Result<T,Failure> = await withoutActuallyEscaping(body) { escapingClosure in
            let holder = CoreDataContextClosureHolder(closure: escapingClosure)
            defer {
                withExtendedLifetime(holder, {})
            }
            return await withUnsafeContinuation { continuation in
                base.performBackgroundTask { [unowned holder, continuation] newContext in
                    nonisolated(unsafe)
                    let result = _convertToResult(newContext, holder.closure)
                    continuation.resume(returning: result)
                }
            }
        }
        return try result.get()
    }
    
}


public enum CoreDataScheduledTaskType: Sendable, Hashable {
    
    case immediate
    
    case enqueued
    
    @usableFromInline
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
    var platformValue: NSManagedObjectContext.ScheduledTaskType {
        switch self {
        case .immediate:
            return .immediate
        case .enqueued:
            return .enqueued
        }
    }
}

#endif

