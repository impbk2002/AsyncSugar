//
//  File.swift
//  
//
//  Created by pbk on 2022/09/16.
//

import Foundation
import Combine

public extension AsyncSequence {
    
    var omittedPublisher:AnyPublisher<Element,Never> {
        Just(self).flatMap(maxPublishers: .max(1)) { source in
            let subject = PassthroughSubject<Element,Never>()
            let task = Task {
                await withTaskCancellationHandler {
                    print("asyncSequence cancelled")
                } operation: {
                    var iterator = source.makeAsyncIterator()
                    while let i = try? await iterator.next() {
                        subject.send(i)
                    }
                    subject.send(completion: .finished)
                }

            }
            return subject.handleEvents(receiveCancel: task.cancel)
        }.eraseToAnyPublisher()
    }
    
    var publisher:AnyPublisher<Element,Error> {
        if #available(iOS 14.0, tvOS 14.0, macCatalyst 14.0, watchOS 7.0, macOS 11.0, *) {
            return Just(self).flatMap(maxPublishers: .max(1)) { source in
                let subject = PassthroughSubject<Element,Error>()
                let task = Task {
                    await withTaskCancellationHandler {
                        print("asyncSequence cancelled")
                    } operation: {
                        do {
                            for try await i in source {
                                subject.send(i)
                            }
                            subject.send(completion: .finished)
                        } catch {
                            subject.send(completion: .failure(error))
                        }
                    }
                }
                return subject.handleEvents(receiveCancel: task.cancel)
            }.eraseToAnyPublisher()
        } else {
            return Just(self).setFailureType(to: Error.self).flatMap(maxPublishers: .max(1)) { source in
                let subject = PassthroughSubject<Element,Error>()
                let task = Task {
                    await withTaskCancellationHandler {
                        print("asyncSequence cancelled")
                    } operation: {
                        do {
                            for try await i in source {
                                subject.send(i)
                            }
                            subject.send(completion: .finished)
                        } catch {
                            subject.send(completion: .failure(error))
                        }
                    }

                }
                    
                return subject.handleEvents(receiveCancel: task.cancel)
            }.eraseToAnyPublisher()
        }

    }
}


public struct CompatAsyncPublisher<P:Publisher>: AsyncSequence where P.Failure == Never {

    public typealias AsyncIterator = Iterator
    public typealias Element = P.Output
    
    public var publisher:P
    
    public func makeAsyncIterator() -> AsyncIterator {
        Iterator(source: publisher)
    }
    
    public struct Iterator: AsyncIteratorProtocol {
        
        public typealias Element = P.Output
        
        let source:P
        private var subscriber:AsyncSubscriber?
        
        public mutating func next() async -> P.Output? {
            if Task.isCancelled {
                subscriber = nil
                return nil
            } else if let subscriber {
                return await subscriber.awaitNext()
            } else {
                let a = AsyncSubscriber()
                source.receive(subscriber: a)
                subscriber = a
                return await a.awaitNext()
            }
        }
        
        fileprivate init(source: P) {
            self.source = source
        }
        
    }
    
    final class AsyncSubscriber: Subscriber {
        
        typealias Input = Element
        
        typealias Failure = Never
        
        private var token:AnyCancellable?
        private var subscription:Subscription?
        private let store = ContinuationStore()
        func receive(_ input: Element) -> Subscribers.Demand {
            store.mutate { list in
                list.forEach { $0.resume(returning: input) }
                list = []
            }
            return .none
        }
        
        func receive(completion: Subscribers.Completion<Never>) {
            store.mutate {
                $0.forEach { continuation in continuation.resume(returning: nil) }
                $0 = []
                subscription = nil
            }
            token = nil
        }
        

        func awaitNext() async -> Element? {
            return await withTaskCancellationHandler {
                self.dispose()
            } operation: {
                let cancelled = Task.isCancelled
               return await withUnsafeContinuation { continuation in
                   if let subscription, !cancelled {
                       store.mutate {
                           $0.append(continuation)
                       }
                       subscription.request(.max(1))

                   } else {
                       continuation.resume(returning: nil)
                   }

                }
            }
        }
        
        
        func receive(subscription: Subscription) {
            self.subscription = subscription

            token = AnyCancellable(subscription)
        }
        
        
        private func dispose() {
            token = nil
            subscription = nil
            store.mutate { list in
                list.forEach{ $0.resume(returning: nil) }
                list = []
            }
        }
        
        fileprivate init() {}
    }

    final class ContinuationStore {
        private let lock = NSLock()
        var list:[UnsafeContinuation<Element?,Never>] = []
        func mutate(operation: (inout [UnsafeContinuation<Element?,Never>]) -> Void) {
            lock.lock()
            operation(&list)
            lock.unlock()
        }
        fileprivate init() {}
    }

    
}

public struct CompatAsyncThrowingPublisher<P:Publisher>: AsyncSequence {

    public typealias AsyncIterator = Iterator
    public typealias Element = P.Output
    
    public var publisher:P
    
    public func makeAsyncIterator() -> AsyncIterator {
        Iterator(source: publisher)
    }
    
    public struct Iterator: AsyncIteratorProtocol {
        
        public typealias Element = P.Output
        
        let source:P
        private var subscriber:AsyncThrowingSubscriber?
        
        public mutating func next() async throws -> P.Output? {
            if Task.isCancelled {
                subscriber = nil
                return nil
            } else if let subscriber {
                return try await subscriber.awaitNext()
            } else {
                let a = AsyncThrowingSubscriber()
                source.receive(subscriber: a)
                subscriber = a
                return try await a.awaitNext()
            }
        }
        
        fileprivate init(source: P) {
            self.source = source
        }
        
    }
    
    final class AsyncThrowingSubscriber: Subscriber{
        
        typealias Input = Element
        
        typealias Failure = P.Failure
        
        private var token:AnyCancellable?
        private var subscription:Subscription?
        private let store = ContinuationThrowingStore()
        func receive(_ input: Element) -> Subscribers.Demand {
            store.mutate { list in
                list.forEach { $0.resume(returning: input) }
                list = []
            }
            return .none
        }
        
        func receive(completion: Subscribers.Completion<Failure>) {
            store.mutate {
                switch completion {
                case .finished:
                    $0.forEach { continuation in continuation.resume(returning: nil) }
                case .failure(let failure):
                    $0.forEach { continuation in continuation.resume(throwing: failure) }
                }
                $0 = []
                subscription = nil
            }
        }
        

        func awaitNext() async throws -> Element? {
            return try await withTaskCancellationHandler {
                self.dispose()
            } operation: {
                let cancelled = Task.isCancelled
               return try await withUnsafeThrowingContinuation { continuation in
                   if let subscription, !cancelled {
                       store.mutate {
                           $0.append(continuation)
                       }
                       subscription.request(.max(1))

                   } else {
                       continuation.resume(returning: nil)
                   }

                }
            }
        }
        
        
        func receive(subscription: Subscription) {
            self.subscription = subscription
            token = AnyCancellable(subscription)
        }
        
        
        private func dispose() {
            token = nil
            subscription = nil
            store.mutate { list in
                list.forEach{ $0.resume(returning: nil) }
                list = []
            }
        }
        
        fileprivate init() {}
    }

    final class ContinuationThrowingStore {
        private let lock = NSLock()
        private var list:[UnsafeContinuation<Element?,Error>] = []
        internal func mutate(operation: (inout [UnsafeContinuation<Element?,Error>]) -> Void) {
            lock.lock()
            operation(&list)
            lock.unlock()
        }
        
        fileprivate init() {}
    }

    
}

