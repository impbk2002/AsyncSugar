//
//  ClosureHolder.swift
//  https://forums.swift.org/t/withoutactuallyescaping-async-functions/63198/12
//
//  Created by 박병관 on 6/8/24.
//

import Foundation
#if canImport(CoreData)
import CoreData
#endif

@usableFromInline
final class ClosureHolder<R> {
    @usableFromInline let closure: () throws -> R
    
    @inlinable
    init(closure: @escaping  () throws -> R) {
        self.closure = closure
    }
}

#if canImport(CoreData)
@usableFromInline
final class CoreDataContextClosureHolder<R> {
    @usableFromInline let closure: (NSManagedObjectContext) throws -> R
    
    @inlinable
    init(closure: @escaping  (NSManagedObjectContext) throws -> R) {
        self.closure = closure
    }
}
#endif
