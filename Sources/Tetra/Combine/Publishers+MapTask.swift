//
//  Publishers+MapTask.swift
//  
//
//  Created by pbk on 2023/01/04.
//

import Foundation
@preconcurrency import Combine
internal import CriticalSection

/**
 
    underlying task will receive task cancellation signal if the subscription is cancelled
 
    
    **There is an issue when using with PassthroughSubject or CurrentValueSubject**
 
    - Since Swift does not support running Task inline way (run in sync until suspension point), Subject's value can lost.
    - Use the workaround like below to prevent this kind of issue
    - wrap the mapTask with `flatMap` or use `buffer` before `mapTask`

 
```
    import Combine

    let subject = PassthroughSubject<Int,Never>()
    subject.flatMap(maxPublishers: .max(1)) { value in
        Just(value).mapTask{ \**do async job**\ }
    }
    subject.buffer(size: 1, prefetch: .keepFull, whenFull: .customError{ fatalError() })
        .mapTask{ \**do async job**\ }
        
 ```
 
 */
public struct MapTask<Upstream:Publisher, Output>: Publisher where Upstream.Output:Sendable {

    public typealias Output = Output
    public typealias Failure = Upstream.Failure
    public typealias Transform = @Sendable @isolated(any) (Upstream.Output) async -> sending Result<Output,Failure>
    public var priority: TaskPriority? = nil
    public let upstream:Upstream
    public var transform:Transform

    public init(
        priority: TaskPriority? = nil,
        upstream: Upstream,
        transform: @escaping @Sendable @isolated(any) (Upstream.Output) async -> sending Output
    ) {
        self.priority = priority
        self.upstream = upstream
        self.transform = {
            Result.success(await transform($0))
        }
    }
    
    public init(
        priority: TaskPriority? = nil,
        upstream: Upstream,
        handler: @escaping Transform
    ) {
        self.priority = priority
        self.upstream = upstream
        self.transform = handler
    }

    public func receive<S>(subscriber: S) where S : Subscriber, Upstream.Failure == S.Failure, Output == S.Input {
        
//        let processor = Inner(subscriber: subscriber, transform: transform)
//        let task = Task(priority: priority, operation: processor.run)
//        processor.resumeCondition(task)
//        upstream.subscribe(processor)
        MultiMapTask(
            priority: priority,
            maxTasks: .max(1),
            upstream: upstream,
            transform: { [transform] value throws(Failure) in
                Suppress(value: try await transform(value).get()).value
            })
        .subscribe(MapTaskInner(description: "MapTask", downstream: subscriber))
    }
    
}


extension MapTask: Sendable where Upstream: Sendable {}
