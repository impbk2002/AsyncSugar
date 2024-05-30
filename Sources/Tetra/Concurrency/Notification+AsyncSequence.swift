//
//  Notification+AsyncSequence.swift
//  
//
//  Created by pbk on 2022/12/09.
//  NotificationCenter.notifications를 Mirror로 내부 property를 확인한 것을 바탕으로 구현했습니다.
//

import Foundation
import _Concurrency


@available(iOS 13.0, tvOS 13.0, macCatalyst 13.0, watchOS 6.0, macOS 10.15, *)
public extension NotificationCenter {
    
    
    @available(iOS, introduced: 13.0, deprecated: 15.0, renamed: "notifications")
    @available(tvOS, introduced: 13.0, deprecated: 15.0, renamed: "notifications")
    @available(macCatalyst, introduced: 13.0, deprecated: 15.0, renamed: "notifications")
    @available(watchOS, introduced: 6.0, deprecated: 8.0, renamed: "notifications")
    @available(macOS, introduced: 10.15, deprecated: 12.0, renamed: "notifications")
    func sequence(named:Notification.Name, object:AnyObject? = nil) -> WrappedAsyncSequence<Notification> {
        if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
            return WrappedAsyncSequence(base: self.notifications(named: named, object: object))
        } else {
            return WrappedAsyncSequence(base: NotificationSequence(center: self, named: named, object: object))
        }
    }
    
}

@available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *)
extension NotificationCenter.Notifications.AsyncIterator: NonThrowingAsyncIteratorProtocol {}

public final class NotificationSequence: AsyncSequence, Sendable {
    
    public typealias Element = Notification
    public typealias AsyncIterator = Iterator
    
    public func makeAsyncIterator() -> Iterator {
        Iterator(parent: self)
    }
    
    let center: NotificationCenter
    private let lock:some UnfairStateLock<NotficationState> = createUncheckedStateLock(uncheckedState: NotficationState())

    public struct Iterator: NonThrowingAsyncIteratorProtocol {
        public typealias Element = Notification
        
        let parent:NotificationSequence

        public func next() async -> Notification? {
//            next를 호출한 동안에 task cancellation이 발생하면 observer Token이 무효화되는 것이 확인되므로 아래와 같이 canellation을 추가한다.
            await withTaskCancellationHandler(
                operation: parent.next,
                onCancel: parent.cancel
            )
        }

    }
    
    private struct NotficationState {
        var buffer:[Notification] = []
        var pending:[UnsafeContinuation<Notification?,Never>] = []
        var observer:NSObjectProtocol?
    }
    
    
    public init(
        center: NotificationCenter,
        named name: Notification.Name,
        object: AnyObject? = nil
    ) {
        
        self.center = center
        let observer = center.addObserver(forName: name, object: object, queue: nil) { [lock] notification in
            lock.withLockUnchecked { state in
                let captured = state.pending.first

                if state.pending.isEmpty {
                    state.buffer.append(notification)
                } else {
                    state.pending.removeFirst()
                }
                return captured
            }?.resume(returning: notification)
        }
        lock.withLockUnchecked{
            $0.observer = observer
        }
    }
    

    deinit {
        cancel()
    }
    
    @Sendable
    func cancel() {
        let snapShot = lock.withLockUnchecked {
            let oldValue = $0
            $0.observer = nil
            $0.buffer = []
            $0.pending = []
            return oldValue
        }
        if let observer = snapShot.observer {
            center.removeObserver(observer)
        }
        snapShot.pending.forEach{ $0.resume(returning: nil) }
    }
    
    func next() async -> Notification? {
        await withUnsafeContinuation { continuation in
            let (notification, isCancelled) = lock.withLockUnchecked { state in
                if !state.buffer.isEmpty {
                    return (state.buffer.removeFirst() as Notification?, false)
                } else if state.observer != nil {
                    state.pending.append(continuation)
                    return (nil as Notification?, false)
                } else {
                    return (nil as Notification?, true)
                }
            }
            if notification != nil || isCancelled {
                continuation.resume(returning: notification)
            }
        }
    }
    
}
