//
//  AsyncTypedSequence.swift
//  
//
//  Created by pbk on 2022/09/26.
//

import Combine
import _Concurrency
import Foundation


public protocol AsyncTypedSequence<Element,Failure>:AsyncSequence {}


@available(iOS 15.0, macOS 12.0, macCatalyst 15.0, tvOS 15.0, watchOS 8.0, *)
extension AsyncThrowingPublisher: AsyncTypedSequence {}
@available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *)
extension AsyncPublisher: AsyncTypedSequence {}

extension AsyncThrowingStream: AsyncTypedSequence {}
extension AsyncStream: AsyncTypedSequence {}

@available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *)
extension NotificationCenter.Notifications: AsyncTypedSequence {}

