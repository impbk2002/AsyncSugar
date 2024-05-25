//
//  URLSessionDownloadTests.swift
//  
//
//  Created by pbk on 2023/01/27.
//

import XCTest
@testable import Tetra

final class URLSessionDownloadTests: XCTestCase {
    
    
    private static let text = UUID().uuidString
    private static var webserver:SimpleHTTPServer? = nil
    
    private var portNumber: UInt16 {
        get throws {
            try XCTUnwrap(Self.webserver?.port?.rawValue)
        }
    }
    
    override class func setUp() {
        super.setUp()
        XCTAssertNoThrow(try {
            webserver = try SimpleHTTPServer(queue: .main, port: .any) { error in
                XCTAssertNoThrow(Result{ throw error }.get)
            }
        }())
        webserver?.response = text
        webserver?.start()
    }
    
    override class func tearDown() {
        super.tearDown()
        webserver?.cancel()
        webserver = nil
    }
    

    func testDefaultDownload() async throws {
        let (fileURL, response) = try await TetraExtension(base: URLSession.shared).download(
            from:  URL(string: "http://localhost:\(portNumber)")!
        )
        let httpResponse = response as! HTTPURLResponse
        addTeardownBlock {
            XCTAssertNoThrow(try FileManager.default.removeItem(at: fileURL))
        }
        let fileData = try Data(contentsOf: fileURL)
        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertEqual(fileData, Data(Self.text.utf8))
    }
    
    func testCancelledDownload() async throws {
        let result = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await TetraExtension(base: URLSession.shared).download(
                from:  URL(string: "http://localhost:\(portNumber)")!
            )
        }.result
        XCTAssertThrowsError(try result.get()) {
            let urlError = $0 as! URLError
            XCTAssertEqual(urlError.code, .cancelled)
        }
    }
    
    func testCancellDuringDownload() async throws {
        let cancelTask2 = Task {
            try await TetraExtension(base: URLSession.shared).download(
                from:  URL(string: "http://localhost:\(portNumber)")!
            )
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        cancelTask2.cancel()
        let result = await cancelTask2.result
        XCTAssertThrowsError(try result.get()) {
            let urlError = $0 as! URLError
            XCTAssertEqual(urlError.code, .cancelled)
        }
    }


}
