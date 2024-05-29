//
//  File.swift
//  
//
//  Created by 박병관 on 5/16/24.
//

import Foundation

internal protocol CompatThrowingDiscardingTaskGroup {
    
    var isCancelled:Bool { get }
    var isEmpty:Bool { get }
    func cancelAll()
    mutating func addTaskUnlessCancelled(
        priority: TaskPriority?,
        operation: @escaping @Sendable () async throws -> Void
    ) -> Bool
    mutating func addTask(
        priority: TaskPriority?,
        operation: @escaping @Sendable () async throws -> Void
    )

}
@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, macCatalyst 17.0, visionOS 1.0, *)
extension ThrowingDiscardingTaskGroup: CompatThrowingDiscardingTaskGroup {

}

extension ThrowingTaskGroup: CompatThrowingDiscardingTaskGroup where ChildTaskResult == Void {

}
