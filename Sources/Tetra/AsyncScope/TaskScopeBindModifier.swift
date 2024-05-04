//
//  TaskScopeBindModifier.swift
//  
//
//  Created by pbk on 2022/12/31.
//

import Foundation
import SwiftUI

@available(*, deprecated, message: "This implementation is experimantal, and likely to change in future")
public struct TaskScopeBindModifier: ViewModifier {
    
    @LazyTaskScopeState private var taskScope
    
    @MainActor
    public func body(content: Content) -> some View {
        content
            .onAppear{
                if taskScope.isCancelled {
                    taskScope = StandaloneTaskScope(detached: ())
                }
            }
            .onDisappear(perform: taskScope.cancel)
            .environment(\.viewTaskScope, .init(taskScope: taskScope))

    }
    
    @inlinable
    public init() {
        
    }
    
}

