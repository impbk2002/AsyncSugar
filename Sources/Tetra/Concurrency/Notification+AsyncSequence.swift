//
//  Notification+AsyncSequence.swift
//  
//
//  Created by pbk on 2022/12/09.
//  NotificationCenter.notifications를 Mirror로 내부 property를 확인한 것을 바탕으로 구현했습니다.
//

import Foundation
import _Concurrency
internal import BackPortAsyncSequence
import Namespace

public import CriticalSection


extension TetraExtension where Base: NotificationCenter {
    
    @inlinable
    func notifications(named: Notification.Name, object: AnyObject? = nil) -> NotificationSequence {
        return NotificationSequence(center: base, named: named, object: object)
    }
    
}


public final class NotificationSequence: AsyncSequence, Sendable, TypedAsyncSequence {
    
    public typealias AsyncIterator = Iterator
    public typealias Failure = Never
    
    public func makeAsyncIterator() -> Iterator {
        Iterator(parent: self)
    }
    
    @usableFromInline
    let center: NotificationCenter
    @usableFromInline
    let lock:some UnfairStateLock<NotficationState> = createUncheckedStateLock(uncheckedState: NotficationState())

    public struct Iterator: AsyncIteratorProtocol, TypedAsyncIteratorProtocol {
        public typealias Element = Notification
        public typealias Failure = Never
        
        @usableFromInline
        let parent:NotificationSequence
        
        @inlinable
        public func next(isolation actor: isolated (any Actor)? = #isolation) async throws(Never) -> Notification? {
            //            next를 호출한 동안에 task cancellation이 발생하면 observer Token이 무효화되는 것이 확인되므로 아래와 같이 canellation을 추가한다.
            await withTaskCancellationHandler(
                operation: { [parent] in
                    await parent.next(isolation: actor)
                },
                onCancel: parent.cancel
            )
        }
        
        @_disfavoredOverload
        @inlinable
        public func next() async throws(Never) -> Notification? {
            await next(isolation: nil)
        }

    }
    
    @usableFromInline
    internal struct NotficationState {
        @usableFromInline
        var buffer:[Notification] = []
        @usableFromInline
        var pending:[UnsafeContinuation<Notification?,Never>] = []
        @usableFromInline
        var observer:NSObjectProtocol?
    }
    
    @inlinable
    public init(
        center: NotificationCenter,
        named name: Notification.Name,
        object: AnyObject? = nil
    ) {
        self.center = center
        let observer = center.addObserver(forName: name, object: object, queue: nil) { [lock] notification in

            let continuation = lock.withLockUnchecked { state in
                let captured = state.pending.first

                if state.pending.isEmpty {
                    state.buffer.append(notification)
                } else {
                    state.pending.removeFirst()
                }
                return captured
            }
            continuation?.resume(returning: Suppress(value: notification).value)
        }
        lock.withLockUnchecked{
            $0.observer = observer
        }
    }
    
    @inlinable
    deinit {
        cancel()
    }
    
    @usableFromInline
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
    
    @usableFromInline
    func next(isolation: isolated (any Actor)?) async -> Notification? {
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
