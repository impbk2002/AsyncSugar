//
//  ViewBoundTaskScope.swift
//  
//
//  Created by pbk on 2023/01/02.
//

import Foundation
import SwiftUI

@available(*, deprecated, message: "This protocol and implementation is experimantal, likely to change in futue")
public struct ViewBoundTaskScope: TaskScopeProtocol {
    
    @discardableResult
    @inlinable
    public func launch(operation: @escaping PendingWork) -> Bool {
        switch scope {
        case .invalid:
            return InvalidTaskScope().launch(operation: operation)
        case .local(let taskScope):
            return taskScope.launch(operation: operation)
        }
    }
    
    @inlinable
    public func cancel() {
        switch scope {
        case .local(let taskScope):
            taskScope.cancel()
        case .invalid:
            InvalidTaskScope().cancel()
        }
    }
    
    @inlinable
    public var isCancelled: Bool {
        switch scope {
        case .invalid:
            return InvalidTaskScope().isCancelled
        case .local(let taskScope):
            return taskScope.isCancelled
        }
    }
    
    
    @usableFromInline
    internal enum InnerScope: Hashable, Sendable {
        case invalid
        case local(StandaloneTaskScope)
    }
    
    @usableFromInline
    var scope:InnerScope
    
    init() {
        self.scope = .invalid
    }
    
    init(taskScope:StandaloneTaskScope) {
        self.scope = .local(taskScope)
    }
    
    @usableFromInline
    struct Key: EnvironmentKey {
        
        @usableFromInline
        static var defaultValue: ViewBoundTaskScope { .init() }
        
    }
    
}
