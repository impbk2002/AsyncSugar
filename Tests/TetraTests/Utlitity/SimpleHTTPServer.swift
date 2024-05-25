//
//  File.swift
//  
//
//  Created by 박병관 on 5/25/24.
//

import Foundation
import Network

class SimpleHTTPServer {
    
    var port: NWEndpoint.Port? {
        listener.port
    }
    
    let queue:DispatchQueue
    let listener: NWListener
    let errorHandler: (any Error) -> Void
    var response:String = "Hello, World!"
    init(
        queue:DispatchQueue,
        port: NWEndpoint.Port,
        errorHandle: @escaping (any Error) -> Void
    ) throws {
        self.listener = try NWListener(using: .tcp, on: port)
        self.queue = queue
        self.errorHandler = errorHandle
    }

    func start() {
        listener.newConnectionHandler = { [weak self, queue] newConnection in
            if let server = self {
                newConnection.start(queue: queue)
                server.handleConnection(newConnection)
            } else {
                newConnection.cancel()
            }

        }
        listener.stateUpdateHandler = { [errorHandler] newState in
            switch newState {
            case .ready:
                break
            case .failed(let error):
                errorHandler(error)
            default:
                break
            }
        }

        listener.start(queue: queue)
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) {[weak self, errorHandler] data, context, isComplete, error in
            guard let server = self else {
                connection.cancel()
                return
            }
            if let data = data, !data.isEmpty {
                if let _ = String(data: data, encoding: .utf8) {
                    server.sendResponse(connection: connection)
                }
            }
            if isComplete {
                connection.cancel()
            } else if let error = error {
                errorHandler(error)
                connection.cancel()
            } else {
                server.handleConnection(connection)
            }
        }
    }
    
    func cancel() {
        listener.cancel()
        listener.newConnectionHandler = nil
        listener.stateUpdateHandler = nil
    }

    private func sendResponse(connection: NWConnection) {
        
        let httpResponse = """
        HTTP/1.1 200 OK
        Content-Type: text/plain
        Content-Length: \(response.count)

        \(response)
        """

        let responseData = httpResponse.data(using: .utf8)
        connection.send(content: responseData, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [errorHandler] error in
            if let error = error {
                errorHandler(error)
                connection.cancel()
            }
        })
    }
}

