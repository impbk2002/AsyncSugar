//
//  File.swift
//  
//
//  Created by 박병관 on 1/1/24.
//

import Foundation
import Namespace


@available(iOS 13.0, tvOS 13.0, macCatalyst 13.0, macOS 10.15, watchOS 6.0, *)
public extension TetraExtension where Base: URLSession {
    
    @inlinable
    func upload(request:URLRequest, file:URL) async throws -> (Data,URLResponse) {
        try await urltask_transformer(
            transform: { .success($0) },
            creator: {
                base.uploadTask(with: request, fromFile: file, completionHandler: $0)
            }
        )
    }
    
    @inlinable
    func upload(request:URLRequest, data:Data?) async throws -> (Data,URLResponse) {
        try await urltask_transformer(
            transform: { .success($0) },
            creator: {
                base.uploadTask(with: request, from: data, completionHandler: $0)
            }
        )
    }

    @available(iOS 17.0, tvOS 17.0, macCatalyst 17.0, watchOS 10.0, macOS 14.0, visionOS 1.0, *)
    @inlinable
    func upload(withResumeData resumeData:Data) async throws -> (Data,URLResponse) {
        try await urltask_transformer {
            .success($0)
        } creator: {
            base.uploadTask(withResumeData: resumeData, completionHandler: $0)
        }

    }
    
    @inlinable
    func data(request:URLRequest) async throws -> (Data, URLResponse) {
        try await urltask_transformer(
            transform: { .success($0) },
            creator: {
                base.dataTask(with: request, completionHandler: $0)
            }
        )
    }
    
    @inlinable
    func data(url:URL) async throws -> (Data, URLResponse) {
        try await urltask_transformer(
            transform: { .success($0) },
            creator: {
                base.dataTask(with: url, completionHandler: $0)
            }
        )
    }
    
    @inlinable
    func download(from url:URL) async throws -> (URL,URLResponse) {
        try await download_transformer {
            base.downloadTask(with: url, completionHandler: $0)
        }
    }
    
    @inlinable
    func download(for request:URLRequest) async throws -> (URL, URLResponse) {
        try await download_transformer {
            base.downloadTask(with: request, completionHandler: $0)
        }
    }
    
    @inlinable
    func download(resumeFrom data:Data) async throws -> (URL, URLResponse) {
        try await download_transformer {
            base.downloadTask(withResumeData: data, completionHandler: $0)
        }
    }
    
}
