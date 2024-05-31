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
    
    public func perform<T>(_ body: () throws -> T) async rethrows -> T {
//        if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
//            return try await withoutActuallyEscaping(body) { try await base.perform($0) }
//        }
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
    
    public func performAndWait<T>(_ body: () throws -> T) rethrows -> T {
//        if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
//            return try base.performAndWait(body)
//        }
        let reference = UnsafeMutablePointer<Result<T,Error>>.allocate(capacity: 1)
        defer { reference.deallocate() }
        base.performAndWait {
            reference.initialize(to: Result{ try body() })
        }
        let result = reference.move()
        switch result {
        case .success(let value):
            return value
        case .failure:
            try result._rethrowOrFail()
        }
    }
    
}

extension TetraExtension where Base: NSManagedObjectContext {
    
    public func perform<T>(_ body: () throws -> T) async rethrows -> T {
//        if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
//            return try await withoutActuallyEscaping(body) { try await base.perform($0) }
//        }
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
    
    public func performAndWait<T>(_ body: () throws -> T) rethrows -> T {
//        if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
//            return try base.performAndWait(body)
//        }
        let reference = UnsafeMutablePointer<Result<T,Error>>.allocate(capacity: 1)
        defer { reference.deallocate() }
        base.performAndWait {
            reference.initialize(to: Result{ try body() })
        }
        let result = reference.move()
        switch result {
        case .success(let value):
            return value
        case .failure:
            try result._rethrowOrFail()
        }
    }
    
}

extension TetraExtension where Base: NSPersistentContainer {
    
    public func performBackground<T>(_ body: (NSManagedObjectContext) throws -> T) async rethrows -> T {
//        if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
//            return try await withoutActuallyEscaping(body) { try await base.performBackgroundTask($0) }
//        }
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
