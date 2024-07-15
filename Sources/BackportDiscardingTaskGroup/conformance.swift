//
//  File.swift
//  
//
//  Created by 박병관 on 5/16/24.
//

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, macCatalyst 17.0, visionOS 1.0, *)
extension DiscardingTaskGroup: CompatDiscardingTaskGroup {
    
    @usableFromInline
    package typealias Err = NoThrow
//    @usableFromInline
//    package typealias Failure = NoThrow
//    
    @_disfavoredOverload
    @inlinable
    package mutating func addTaskUnlessCancelled(priority: TaskPriority?, operation: @escaping Block) -> Bool {
        let block = { @Sendable () async throws(Never) -> Void in
            try? await operation()
        }
        return addTaskUnlessCancelled(priority: priority, operation: block)
    }
    
    @_disfavoredOverload
    @inlinable
    package mutating func addTask(priority: TaskPriority?, operation: @escaping Block) {
        let block = { @Sendable () async throws(Never) -> Void in
            try? await operation()
        }
        return addTask(priority: priority, operation: block)
    }
    
    @_disfavoredOverload
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @inlinable
    package mutating func addTask(executorPreference taskExecutor: (any TaskExecutor)?, priority: TaskPriority?, operation: @escaping Block) {
        let block = { @Sendable () async throws(Never) -> Void in
            try? await operation()
        }
        addTask(executorPreference: taskExecutor, priority: priority, operation: block)
    }
    
    @_disfavoredOverload
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @inlinable
    package mutating func addTaskUnlessCancelled(executorPreference taskExecutor: (any TaskExecutor)?, priority: TaskPriority?, operation: @escaping Block) -> Bool {
        let block = { @Sendable () async throws(Never) -> Void in
            try? await operation()
        }
        return addTaskUnlessCancelled(executorPreference: taskExecutor, priority: priority, operation: block)

    }
    
}

extension TaskGroup: CompatDiscardingTaskGroup where ChildTaskResult == Void {
    
    @_disfavoredOverload
    @inlinable
    package mutating func addTaskUnlessCancelled(priority: TaskPriority?, operation: @escaping Block) -> Bool {
        let block = { @Sendable in
            try? await operation()
            return
        }
        return addTaskUnlessCancelled(priority: priority, operation: block)
    }
    
    @_disfavoredOverload
    @inlinable
    package mutating func addTask(priority: TaskPriority?, operation: @escaping Block) {
        let block = { @Sendable in
            try? await operation()
            return
        }
        return addTask(priority: priority, operation: block)
    }
    
    @_disfavoredOverload
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @inlinable
    package mutating func addTask(executorPreference taskExecutor: (any TaskExecutor)?, priority: TaskPriority?, operation: @escaping Block) {
        let block = { @Sendable in
            try? await operation()
            return
        }
        addTask(executorPreference: taskExecutor, priority: priority, operation: block)
    }
    
    @_disfavoredOverload
    @available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
    @inlinable
    package mutating func addTaskUnlessCancelled(executorPreference taskExecutor: (any TaskExecutor)?, priority: TaskPriority?, operation: @escaping Block) -> Bool {
        let block = { @Sendable  in
            try? await operation()
            return
        }
        return addTaskUnlessCancelled(executorPreference: taskExecutor, priority: priority, operation: block)

    }
    
    @usableFromInline
    package typealias Err = NoThrow

    
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, macCatalyst 17.0, visionOS 1.0, *)
extension ThrowingDiscardingTaskGroup: CompatDiscardingTaskGroup {

    @usableFromInline
    package typealias Err = any Error
}


extension ThrowingTaskGroup: CompatDiscardingTaskGroup where ChildTaskResult == Void {
    @usableFromInline
    package typealias Err = any Error
}


@usableFromInline
package enum NoThrow: Error {
    
    case failure(Never)
    
}
