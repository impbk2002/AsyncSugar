//
//  URLSessionDownloadTests.swift
//  
//
//  Created by pbk on 2023/01/27.
//

import XCTest
@testable import Tetra
import Namespace

@preconcurrency
final class URLSessionDownloadTests: XCTestCase {
    
    
    private static let text = UUID().uuidString
    nonisolated(unsafe) private static var webserver:Result<SimpleHTTPServer,Error>? = nil
    
    private var url: URL {
        get throws {
            let port = try XCTUnwrap(Self.webserver?.get().port?.rawValue)
            return try XCTUnwrap(URL(string: "http://localhost:\(port)"))
        }
    }
    
    override class func setUp() {
        super.setUp()
        webserver = Result {
            let server = try SimpleHTTPServer(queue: DispatchQueue(label: "webserver"), port: .any) { error in
                dump(error)
                XCTFail(error.localizedDescription)
            }
            server.response = text
            server.start()
            return server
        }
    }
    
    override class func tearDown() {
        super.tearDown()
        try? webserver?.get().cancel()
        webserver = nil
    }
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        let _ = try Self.webserver?.get()
    }
    

    func testDefaultDownload() async throws {
        let (fileURL, response) = try await TetraExtension(base: URLSession.shared)
            .download(from: url)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        addTeardownBlock {
            XCTAssertNoThrow(try FileManager.default.removeItem(at: fileURL))
        }
        let fileData = try Data(contentsOf: fileURL)
        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertEqual(fileData, Data(Self.text.utf8))
    }
    
    func testCancelledDownload() async {
        let result = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await TetraExtension(base: URLSession.shared)
                .download(from: url)
        }.result
        XCTAssertThrowsError(try result.get()) {
            if let urlError = $0 as? URLError {
                XCTAssertEqual(urlError.code, .cancelled)
            } else {
                dump($0)
                XCTFail($0.localizedDescription)
            }
        }
    }
    
    func testCancellDuringDownload() async throws {
        let cancelTask2 = Task {
            try await TetraExtension(base: URLSession.shared)
                .download(from: url)
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        cancelTask2.cancel()
        let result = await cancelTask2.result
        XCTAssertThrowsError(try result.get()) {
            if let urlError = $0 as? URLError {
                XCTAssertEqual(urlError.code, .cancelled)
            } else {
                dump($0)
                XCTFail($0.localizedDescription)
            }
        }
    }

}
