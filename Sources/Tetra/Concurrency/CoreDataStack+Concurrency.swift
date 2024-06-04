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
            let value = try await withoutActuallyEscaping(body) { escapingClosure in
                try await withUnsafeThrowingContinuation { continuation in
                    base.perform {
                        continuation.resume(with: Result{ try escapingClosure() })
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
            try await withoutActuallyEscaping(body) { try await base.perform($0) }
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

extension TetraExtension where Base: NSManagedObjectContext {
    
    
    @usableFromInline
    internal func _perform<T>(
        _ body: () throws -> T
    ) async rethrows -> T {
        let result:Result<T,Error>
        do {
            let value = try await withoutActuallyEscaping(body) { escapingClosure in
                try await withUnsafeThrowingContinuation { continuation in
                    base.perform {
                        continuation.resume(with: Result{ try escapingClosure() })
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
    public func perform<T>(_ body: () throws -> T) async rethrows -> T {
        return if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
            try await withoutActuallyEscaping(body) {
                try await base.perform(schedule: .enqueued, $0)
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

extension TetraExtension where Base: NSPersistentContainer {
    
    @inlinable
    public func performBackground<T>(_ body: (NSManagedObjectContext) throws -> T) async rethrows -> T {
        return if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
            try await withoutActuallyEscaping(body) { try await base.performBackgroundTask($0) }
        } else {
            try await _performBackground(body)
        }
    }
    
    @usableFromInline
    internal func _performBackground<T>(_ body: (NSManagedObjectContext) throws -> T) async rethrows -> T {
        let result:Result<T,Error>
        do {
            let value = try await withoutActuallyEscaping(body) { escapingClosure in
                try await withUnsafeThrowingContinuation { continuation in
                    base.performBackgroundTask { newContext in
                        continuation.resume(with: Result{ try escapingClosure(newContext) })
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


#endif
