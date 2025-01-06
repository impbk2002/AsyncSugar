//
//  Publishers+TryMapTask.swift
//  
//
//  Created by pbk on 2023/01/04.
//

import Foundation
@preconcurrency import Combine
import _Concurrency
internal import CriticalSection

/**
 
    underlying task will receive task cancellation signal if the subscription is cancelled
 
    **There is an issue when using with PassthroughSubject or CurrentValueSubject**

    - Since Swift does not support running Task inline way (run in sync until suspension point), Subject's value can lost.
    - wrap the mapTask with `flatMap` or use `buffer` before `mapTask`

```
 import Combine

 let subject = PassthroughSubject<Int,Never>()
 subject.flatMap(maxPublishers: .max(1)) { value in
     Just(value).tryMapTask{ \**do async job**\ }
 }
 subject.buffer(size: 1, prefetch: .keepFull, whenFull: .customError{ fatalError() })
     .tryMapTask{ \**do async job**\ }
     
```
 */
public struct TryMapTask<Upstream:Publisher, Output>: Publisher where Upstream.Output:Sendable {

    public typealias Output = Output
    public typealias Failure = any Error
    public typealias Transform = @isolated(any) @Sendable (Upstream.Output) async throws -> sending Output
    public let upstream:Upstream
    public var transform: Transform
    public var priority: TaskPriority? = nil

    public init(
        priority:TaskPriority? = nil,
        upstream: Upstream,
        transform: @escaping Transform
    ) {
        self.upstream = upstream
        self.transform = transform
        self.priority = priority
    }
    
    public func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
//        let processor = Inner(subscriber: subscriber, transform: transform)
//        let task = Task(priority: priority, operation: processor.run)
//        processor.resumeCondition(task)
//        upstream.subscribe(processor)
        MultiMapTask(
            priority: priority,
            maxTasks: .max(1),
            upstream: upstream.mapError{ $0 as any Error },
            transform: transform
        ).subscribe(MapTaskInner(
            description: "TryMapTask",
            downstream: subscriber,
            upstream: nil
        ))
        
    }

}


extension TryMapTask: Sendable where Upstream: Sendable {}
