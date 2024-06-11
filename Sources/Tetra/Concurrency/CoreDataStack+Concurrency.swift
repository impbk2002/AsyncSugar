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

extension NSPersistentContainer: TetraExtended {}
extension NSPersistentStoreCoordinator: TetraExtended {}
extension NSManagedObjectContext: TetraExtended {}

extension TetraExtension where Base: NSPersistentStoreCoordinator {
    
    @usableFromInline
    internal func _perform<T>(_ body: () throws -> T) async rethrows -> T {
        let result:Result<T,Error>
        do {
            let value: T = try await withoutActuallyEscaping(body) { escapingClosure in
                let closureHolder = ClosureHolder(closure: escapingClosure)
                defer {
                    withExtendedLifetime(closureHolder) {}
                }
                return try await withUnsafeThrowingContinuation { continuation in
                    base.perform{ [unowned closureHolder, continuation] in
                        continuation.resume(with: Result { try closureHolder.closure() })
                    }
                }
            }
            result = .success(value)
        } catch {
            result = .failure(error)
        }
        switch result {
        case .success(let success):
            return success
        case .failure:
            try result._rethrowOrFail()
        }
    }
    
    @inlinable
    public func perform<T>(_ body: () throws -> T) async rethrows -> T {
        return if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
            try await withoutActuallyEscaping(body) {
                let holder = ClosureHolder(closure: $0)
                defer { withExtendedLifetime(holder, {})}
                return try await base.perform{ [unowned holder] in
                    try holder.closure()
                }
            }
        } else {
            try await _perform(body)
        }
    }
    
    @usableFromInline
    internal func _performAndWait<T>(_ body: () throws -> T) rethrows -> T {
        var result:Result<T,any Error>? = nil
        base.performAndWait {
            result = Result { try body() }
        }
        guard let result else {
            preconditionFailure("performAndWait didn't run")
        }
        switch result {
        case .success(let success):
            return success
        case .failure:
            try result._rethrowOrFail()
        }
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
    internal func _performImmediate<T>(
        _ body: () throws -> T
    ) rethrows -> Result<T,Never>? {
        // Suppress deprecation
        let lock:any ObjcLocking = base
        // NSManagedObjectContext has Reentrant Locking
        guard lock.tryLock() else { return nil }
        defer { lock.unlock() }
        let value = try performAndWait(body)
        return .success(value)
    }
    
    @usableFromInline
    internal func _performEnqueue<T>(
        _ body: () throws -> T
    ) async rethrows -> T {
        let result:Result<T,any Error>
        do {
            let value: T = try await withoutActuallyEscaping(body) { escapingClosure in
                let closureHolder = ClosureHolder(closure: escapingClosure)
                defer {
                    withExtendedLifetime(closureHolder) {}
                }
                return try await withUnsafeThrowingContinuation { continuation in
                    base.perform{ [unowned closureHolder, continuation] in
                        continuation.resume(with: Result { try closureHolder.closure() })
                    }
                }
            }
            result = .success(value)
        } catch {
            result = .failure(error)
        }
        switch result {
        case .success(let success):
            return success
        case .failure:
            try result._rethrowOrFail()
        }
    }
    
    /// Asynchronously performs the specified closure on the context’s queue.
    @inlinable
    @_unsafeInheritExecutor
    public func perform<T>(
        schedule: CoreDataScheduledTaskType = .immediate,
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
                let holder = ClosureHolder(closure: $0)
                defer {
                    withExtendedLifetime(holder, { })
                }
                return try await base.perform(schedule: schedule.platformValue) { [unowned holder] in
                    try holder.closure()
                }
            }
        } else if schedule == .enqueued {
            try await _performEnqueue(body)
        } else {
            if let result = try _performImmediate(body) {
                switch result {
                case .success(let success):
                    success
                }
            } else {
                try await _performEnqueue(body)
            }
        }
    }
    
    @usableFromInline
    internal func _performAndWait<T>(_ body: () throws -> T) rethrows -> T {
        var result:Result<T,any Error>? = nil
        base.performAndWait {
            result = Result { try body() }
        }
        guard let result else {
            preconditionFailure("performAndWait didn't run")
        }
        switch result {
        case .success(let success):
            return success
        case .failure:
            try result._rethrowOrFail()
        }
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
                let holder = CoreDataContextClosureHolder(closure: $0)
                defer {
                    withExtendedLifetime(holder, { })
                }
                return try await base.performBackgroundTask{ [unowned holder] in
                    try holder.closure($0)
                }
            }
        } else {
            try await _performBackground(body)
        }
    }
    
    @usableFromInline
    internal func _performBackground<T>(_ body: (NSManagedObjectContext) throws -> T) async rethrows -> T {
        let result:Result<T,Error>
        do {
            let value: T = try await withoutActuallyEscaping(body) { escapingClosure in
                let closureHolder = CoreDataContextClosureHolder(closure: escapingClosure)
                defer {
                    withExtendedLifetime(closureHolder) {}
                }
                return try await withUnsafeThrowingContinuation { continuation in
                    base.performBackgroundTask { [unowned closureHolder, continuation] newContext in
                        continuation.resume(with: Result{ try closureHolder.closure(newContext) })
                    }
                }
            }
            result = .success(value)
        } catch {
            result = .failure(error)
        }
        switch result {
        case .success(let success):
            return success
        case .failure:
            try result._rethrowOrFail()
        }
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
