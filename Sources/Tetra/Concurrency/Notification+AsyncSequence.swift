//
//  Notification+AsyncSequence.swift
//  
//
//  Created by pbk on 2022/12/09.
//  NotificationCenter.notifications를 Mirror로 내부 property를 확인한 것을 바탕으로 구현했습니다.
//

import Foundation
import _Concurrency

extension NotificationCenter: TetraExtended {}


extension TetraExtension where Base: NotificationCenter {
    
    @inlinable
    func notifications(named: Notification.Name, object: AnyObject? = nil) -> NotificationSequence {
        return NotificationSequence(center: base, named: named, object: object)
    }
    
}



public final class NotificationSequence: AsyncSequence, Sendable {
    
    public typealias AsyncIterator = Iterator
    public typealias Failure = Never
    
    public func makeAsyncIterator() -> Iterator {
        Iterator(parent: self)
    }
    
    let center: NotificationCenter
    private let lock:some UnfairStateLock<NotficationState> = createUncheckedStateLock(uncheckedState: NotficationState())

    public struct Iterator: TypedAsyncIteratorProtocol {
        public typealias Element = Notification
        public typealias Failure = Never
        
        let parent:NotificationSequence

        public func next() async -> Notification? {
            await next(isolation: nil)
        }
        
        @_implements(TypedAsyncIteratorProtocol, tetraNext(isolation:))
        public func next(isolation actor: isolated (any Actor)?) async throws(Never) -> Notification? {
            //            next를 호출한 동안에 task cancellation이 발생하면 observer Token이 무효화되는 것이 확인되므로 아래와 같이 canellation을 추가한다.
            await withTaskCancellationHandler(
                operation: { [parent] in
                    await parent.next(isolation: actor)
                },
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
            nonisolated(unsafe)
            let noti2 = notification
            let continuation = lock.withLockUnchecked { state in
                let captured = state.pending.first

                if state.pending.isEmpty {
                    state.buffer.append(noti2)
                } else {
                    state.pending.removeFirst()
                }
                return captured
            }
            continuation?.resume(returning: noti2)
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
