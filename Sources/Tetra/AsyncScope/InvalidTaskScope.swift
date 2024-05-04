//
//  InvalidTaskScope.swift
//  
//
//  Created by pbk on 2023/01/02.
//

import Foundation

@available(*, deprecated, message: "This implementation is experimantal, and likely to change in future")
@usableFromInline
struct InvalidTaskScope: TaskScopeProtocol {
    
    @usableFromInline
    var isCancelled:Bool { true }
    
    @usableFromInline
    func launch(operation: @escaping PendingWork) -> Bool {
        print("InvalidTaskScope never launch")
        return false
    }
    
    @usableFromInline
    func cancel() {}
    

    @usableFromInline
    init() {}
    
}
