# Tetra

A description of this package.
This provides some features that were only available at least iOS 15 and macOS 12.

iOS 15, macOS 12 등에서만 사용이 가능한 API를 iOS 13, iOS 10.15 등에서 사용할 수 있도록 하는 것으로 목표로 개발되었습니다.

## Backport
[async await URLSession download, upload](./Sources/Tetra/Concurrency/TetraExtension+URLSession.swift)
    
[async await NSManagedContext peform](./Sources/Tetra/Concurrency/CoreDataStack+Concurrency.swift)    

Combine <-> AsyncSequence interchanging 

<details closed>
    
[CompatAsyncPublisher](./Sources/Tetra/Combine/CompatAsyncPublisher.swift)
    
[CompatAsyncThrowingPublisher](./Sources/Tetra/Combine/CompatAsyncThrowingPublisher.swift)

[MapTask](./Sources/Tetra/Combine/Publishers+MapTask.swift)

[TryMapTask](./Sources/Tetra/Combine/Publishers+TryMapTask.swift)

[MultiMapTask](./Sources/Tetra/Combine/ExperimentalMapTask.swift)

</details>

[SwiftUI.AsyncImage](./Sources/Tetra/SwiftUI/AsyncImage+BackPort.swift)
[SwiftUI.Binding Collction conformance](./Sources/Tetra/SwiftUI/Binding+Collection.swift)
[SwiftUI.List Pull to Refresh](./Sources/Tetra/SwiftUI/RefreshableScrollView.swift)

## Usage
<details open>

  <summary>(Try)MapTask</summary>
  
  
  Transform upstream value using async (throwing) closure in Serial manner.
  Only one transformer runs at a time.
  Wil be migrated to `MultiMapTask`.
  
```swift
import Combine
import Tetra
        
        let cancellable = (0..<20).publisher
            .tryMapTask { _ in
                // Underlying Task is cancelled if subscription is cancelled before task completes.
                try await URLSession.shared.data(from: URL(string: "https://google.com")!)
            }.map(\.0).sink { completion in
                
            } receiveValue: { data in
                
            }

```
</details>

<details open>
    <summary>MultiMapTask</summary>
    !Experimantal
    
Transform upstream value using async closure in Concurrent manner.
Transformer runs up to `maxTasks` in concurrent manner managed by TaskGroup.
`maxTasks = 1` has same behavior with (Try)MapTask.
    
```swift
import Combine
@_spi(Experimental) import Tetra
        
        let cancellable = (0..<20).publisher
            .setFailureType(to: URLError.self)
            .multiMapTask(maxTasks: .unlimited) { _ throws(URLError) in
                
                // Underlying Task is cancelled if subscription is cancelled before task completes.
                do {
                    let (data, response) = try await URLSession.shared.data(from: URL(string: "https://google.com")!)
                    // below unsafe cancel is no-op, throw appropriate error to interrupt combine pipeline
                    // withUnsafeCurrentTask { $0?.cancel() }
                    return data
                } catch {
                    throw (error as! URLError)
                }
            }.sink { completion in
                
            } receiveValue: { data in
                
            }

```
</details>

<details open>
  <summary>AsyncSequencePublisher</summary>
  Transform AsyncSequence to Publisher
  
```swift
import Combine
import Tetra
        
        let cancellable = AsyncStream<Int> { continuation in
            continuation.yield(0)
            continuation.yield(1)
            continuation.finish()
            // Underlying AsyncIterator and Task receive task cancellation if subscription is cancelled.
        }.tetra.bridge.tetra.publisher
            .sink { number in
                
            }

```
</details>

<details open>
  <summary>[NotificationSequence]</summary>
  AsyncSequence compatible with `NotificationCenter.Notifications`
  Available even in iOS 13
  
```swift
import Combine
import Tetra
import UIKit
        
        // use NotificationCenter.Notifications if available otherwise use NotficationSequence under the hood
        for await notification in NotificationCenter.default.tetra.notifications(named: UIApplication.didFinishLaunchingNotification) {
            
        }
```
</details>

<details open>
  <summary>CompatAsync(Throwing)Publisher</summary>
  AsyncSequence compatible with `Async(Throwing)Publisher`
  Available even in iOS 13
  
```swift
import Combine
import Tetra
        
        let publisher = URLSession.shared.dataTaskPublisher(for: URL(string: "https://google.com")!)
        // use AsyncThrowingPublisher if available otherwise use CompatAsyncThrowingPublisher under the hood.
        for try await (data, response) in publisher.tetra.values {
            
        }
```
</details>

<details open>
  <summary>RefreshableScrollView</summary>
  Compatible pull to refresh feature in all version for iOS
  
```swift
import SwiftUI
import Tetra
        
struct ContentView: View {
    
    var body: some View {
        RefreshableScrollView {
            
        }
        .refreshControl {
            await fetchData()
        }
    }
}

```
</details>


## Known Issues

`MapTask` and `TryMapTask`, `MultiMapTask` could lose the value when using with `PublishSubject` or `CurrentValueSubject`.

- This is because, Swift does not allow running task inline(run task until reaching suspending point). So `MapTask` operators need additional time to for warmup.

- To fix this issue, use `MapTask` family inside the `FlatMap` or attach `buffer` before them.


## TODO

- Add more Tests

- Swift 6 Concurrency model

- FullTypedThrow for powerful generic failure

- more fine grained way to introduce extension methods (maybe something like `.af` in Alamofire?)

- remove all `AsyncTypedSequence` and `WrappedAsyncSequence` dummy protocol when `FullTypedThrow` is implemented.

## WIP

[PriorityRunLoop](./Sources/Tetra/Concurrency/PriorityRunLoop.swift)

TaskPriority aware NSRunLoop based `Concurrency Serial Executor`.

Can be useful for old Apple Framework that does not support `libDispatch` and only support `CFRunLoop` like `CoreLocation`, `perform(_:on:with:waitUntilDone:)`

Reorder the jobs in Priority Order, and increase QoS level, according to the TaskPriority.


[AsyncFlatMap](./Sources/Tetra/Combine/Publishers+AsyncFlatMap.swift)

Combine operator which convert the Upstream to AsyncSequence and transfer the elements to the downstream.

uses actor based cooperative control to minimize contention.

Investingating for a way to backport rich asyncSequence features before Swift 6 platform.


[BackportDiscardingTaskGroup](./Sources/BackportDiscardingTaskGroup/ThrowingTaskGroup.swift)

Backport the behavior of `Discarding(Throwing)TaskGroup`. This now possbile thanks to Swift 6 generalized AsyncSequnce. Because we can wrap the `TaskGroup` into isolation.

Investingating for a way to merge it with existing `Discarding(Throwing)TaskGroup` using some kind of opaque types rather than erased types.

Investigating a way to merge NonFailure type and Failing type using typedThrow, which is currently not possible due to Swift 6 compiler bug.


[MemorySafe Data/String](./Sources/Tetra/Foundation/PruneMemory.swift)

`Data` and `String` which erase its memory footprints when deallocated. implemented by `CoreFoundation` API.

Still can not erase memory footprints caused by Swift Briding copy and os level memory paging.
