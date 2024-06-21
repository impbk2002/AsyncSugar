//
//  File.swift
//  
//
//  Created by 박병관 on 5/16/24.
//

//@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, macCatalyst 17.0, visionOS 1.0, *)
//extension DiscardingTaskGroup: CompatDiscardingTaskGroup {
//    @usableFromInline
//    package typealias Failure = Never
//}
//
//extension TaskGroup: CompatDiscardingTaskGroup where ChildTaskResult == Void {
//    @usableFromInline
//    package typealias Failure = Never
//
//    
//}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, macCatalyst 17.0, visionOS 1.0, *)
extension ThrowingDiscardingTaskGroup: CompatDiscardingTaskGroup {

}


extension ThrowingTaskGroup: CompatDiscardingTaskGroup where ChildTaskResult == Void {

}

