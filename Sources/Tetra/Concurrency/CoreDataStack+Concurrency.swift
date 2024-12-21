//
//  CoreDataStack+Concurrency.swift
//  
//
//  Created by pbk on 2022/12/07.
//

import Foundation
import _Concurrency

#if canImport(CoreData)
@preconcurrency import CoreData
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
            do throws(Failure) {
                result = .success(try body())
            } catch {
                result = .failure(error)
            }
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
                base.perform{ [unowned(unsafe) holder, continuation] in
                    let result = holder()
                    continuation.resume(returning: result)
                }
            }
        }
        return try result.get()
    }
    
    @usableFromInline
    internal func _perform<T, Failure:Error>(
        schedule:CoreDataScheduledTaskType = .immediate,
        isolation: isolated (any Actor)? = #isolation,
        _ body: @escaping () throws(Failure) -> T
    ) async throws(Failure) -> Suppress<T> {
        nonisolated(unsafe)
        let callRef = self
        let ref = UnsafeClosureHolder(closure: body)
        defer {
            withExtendedLifetime(ref, {})
        }
        if schedule == .immediate, let result = try _performImmediate(body) {
            let value = result.get()
            return .init(value: value)
        } else {
            return try await callRef._performEnqueue { [unowned(unsafe) ref] in
                ref().map(Suppress.init)
            }.get()
        }
    }
    
    
    /// Asynchronously performs the specified closure on the context’s queue.
    @inlinable
    public func perform<T, Failure:Error>(
        schedule:CoreDataScheduledTaskType = .immediate,
        isolation: isolated (any Actor)? = #isolation,
        _ body: () throws(Failure) -> T
    ) async throws(Failure) -> T {
        let box: Suppress<T> = try await withoutActuallyEscaping(body) { escapingClosure async throws(Failure) in
            if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
                let ref:UnsafeClosureHolder<T,Failure> = UnsafeClosureHolder(closure: escapingClosure)
                defer {
                    withExtendedLifetime(ref, {})
                }
                let wrapped = await base.perform(schedule: schedule.platformValue) { [unowned(unsafe) ref] in
                    ref().map(Suppress.init)
                }
                return try wrapped.get()
            } else {
                return try await self._perform(schedule: schedule, isolation: isolation, escapingClosure)
            }
        }
        return box.value
    }
    
    @usableFromInline
    internal func _performAndWait<T,Failure:Error>(_ body: () throws(Failure) -> T) throws(Failure) -> T {
        var result:Result<T,Failure>? = nil
        base.performAndWait {
            do throws(Failure) {
                result = .success(try body())
            } catch {
                result = .failure(error)
            }
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
                    let result = holder(newContext)
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

extension TetraExtension: Sendable where Base: Sendable {}

@usableFromInline
internal final class UnsafeClosureHolder<R:~Copyable,Failure:Error>: @unchecked Sendable {
    
    @inline(__always)
    @usableFromInline let closure: () throws(Failure) -> R
    
    @inline(__always)
    @inlinable
    init(closure: @escaping  () throws(Failure) -> R) {
        self.closure = closure
    }
    
    @inline(__always)
    @inlinable
    func callAsFunction() -> Result<R,Failure> {
        do {
            let value = try closure()
            return .success(value)
        } catch {
            return .failure(error)
        }
    }
    
}

