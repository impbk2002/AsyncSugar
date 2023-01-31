//
//  NotificationSequenceTests.swift
//  
//
//  Created by pbk on 2023/01/27.
//

import XCTest
@testable import Tetra

final class NotificationSequenceTests: XCTestCase {

    func testNotificationSequence() async throws {
        let name = Notification.Name(UUID().uuidString)
        let object = NSObject()
        let sequence = NotificationSequence(center: .default, named: name, object: object)

        let task = Task {
            var count = 0
            for await _ in sequence {
                count += 1
            }
            return count
        }
        try await Task.sleep(nanoseconds: 1_000_000)
        NotificationCenter.default.post(name: name, object: nil)
        try await Task.sleep(nanoseconds: 1_000_000)
        NotificationCenter.default.post(name: name, object: object)
        try await Task.sleep(nanoseconds: 1_000_000)
        NotificationCenter.default.post(name: name, object: NSObject())
        try await Task.sleep(nanoseconds: 1_000_000)
        NotificationCenter.default.post(name: name, object: object, userInfo: ["":""])
        try await Task.sleep(nanoseconds: 1_000_000)
        task.cancel()
        NotificationCenter.default.post(name: name, object: object, userInfo: ["":""])
        let count = await task.value
        XCTAssertEqual(count, 2)
    }
    
    func testAlreadyCancelled() async throws {
        let name = Notification.Name(UUID().uuidString)
        let object = NSObject()
        let sequence = NotificationSequence(center: .default, named: name, object: object)


        try await Task.sleep(nanoseconds: 1_000_000)
        NotificationCenter.default.post(name: name, object: nil)
        try await Task.sleep(nanoseconds: 1_000_000)
        NotificationCenter.default.post(name: name, object: object)
        try await Task.sleep(nanoseconds: 1_000_000)
        NotificationCenter.default.post(name: name, object: NSObject())
        try await Task.sleep(nanoseconds: 1_000_000)
        NotificationCenter.default.post(name: name, object: object, userInfo: ["":""])
        try await Task.sleep(nanoseconds: 1_000_000)

        NotificationCenter.default.post(name: name, object: object, userInfo: ["":""])
        let task = Task {
            var count = 0
            for await _ in sequence {
                count += 1
            }
            return count
        }
        task.cancel()
        let count = await task.value
        XCTAssertEqual(count, 0)
    }

}
