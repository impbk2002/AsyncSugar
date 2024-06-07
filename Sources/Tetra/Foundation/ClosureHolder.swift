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
internal final class ClosureHolder<R,Failure:Error> {
    @usableFromInline let closure: () throws(Failure) -> R
    
    @inlinable
    init(closure: @escaping  () throws(Failure) -> R) {
        self.closure = closure
    }
    
    @inlinable
    func callAsFunction() throws(Failure) -> R {
        return try closure()
    }
}

#if canImport(CoreData)
@usableFromInline
internal final class CoreDataContextClosureHolder<R, Failure:Error> {
    @usableFromInline let closure: (NSManagedObjectContext) throws(Failure) -> R
    
    @inlinable
    init(closure: @escaping  (NSManagedObjectContext) throws(Failure) -> R) {
        self.closure = closure
    }
    
    @inlinable
    func callAsFunction(_ context:NSManagedObjectContext) throws(Failure) -> R {
        return try closure(context)
    }
}
#endif
