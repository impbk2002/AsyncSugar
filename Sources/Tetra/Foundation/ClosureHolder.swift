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
internal final class ClosureHolder<R:~Copyable,Failure:Error>: @unchecked Sendable {
    @usableFromInline let closure: () throws(Failure) -> R
    
    @inlinable
    init(closure: @escaping  () throws(Failure) -> R) {
        self.closure = closure
    }
    
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


#if canImport(CoreData)
@usableFromInline
internal final class CoreDataContextClosureHolder<R:~Copyable, Failure:Error> {
    @usableFromInline let closure: (NSManagedObjectContext) throws(Failure) -> R
    
    @inlinable
    init(closure: @escaping  (NSManagedObjectContext) throws(Failure) -> R) {
        self.closure = closure
    }
    
    @inlinable
    func callAsFunction(_ context:NSManagedObjectContext) -> Result<R,Failure> {
        do {
            let value = try closure(context)
            return .success(value)
        } catch {
            return .failure(error)
        }
    }
}
#endif
