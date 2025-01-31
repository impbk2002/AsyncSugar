//
//  AsyncImage+BackPort.swift
//  
//
//  Created by pbk on 2022/12/08.
//  SwiftUI AsyncImage를 iOS 13에서도 사용이 가능하지만 15부터는 framework 구현체에 의존하도록 작성한 개체
//

import Foundation
import Combine
import Namespace


#if canImport(SwiftUI)
import SwiftUI

@available(iOS, deprecated: 15.0, renamed: "AsyncImagePhase")
@available(tvOS, deprecated: 15.0, renamed: "AsyncImagePhase")
@available(macCatalyst, deprecated: 15.0, renamed: "AsyncImagePhase")
@available(macOS, deprecated: 12.0, renamed: "AsyncImagePhase")
@available(watchOS, deprecated: 8.0, renamed: "AsyncImagePhase")
public enum CompatAsyncImagePhase {
    case empty
    case success(Image)
    case failure(Error)
    
    @inlinable
    var image: Image? {
        guard case .success(let image) = self else { return nil }
        return image
    }
    
    @inlinable
    var error: Error? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}

@available(iOS, deprecated: 15.0, renamed: "AsyncImage")
@available(tvOS, deprecated: 15.0, renamed: "AsyncImage")
@available(macCatalyst, deprecated: 15.0, renamed: "AsyncImage")
@available(macOS, deprecated: 12.0, renamed: "AsyncImage")
@available(watchOS, deprecated: 8.0, renamed: "AsyncImage")
public struct CompatAsyncImage<Content: View>: View {
    
    @usableFromInline
    var url: URL?
    @usableFromInline
    var scale: CGFloat = 1
    @usableFromInline
    var transaction = Transaction()
    @usableFromInline
    var content: ((Tetra.CompatAsyncImagePhase) -> Content)?
    @State private var phase = CompatAsyncImagePhase.empty
    @usableFromInline
    var someView:AnyView


    @usableFromInline
    @ViewBuilder
    var contentOrImage: some View {
        if let content = content {
            content(phase)
        } else if case let .success(image) = phase {
            image
        } else {
            Color(white: 0.16)
        }
    }
    @MainActor
    private func loadImage() async {
        guard let url else {
            phase = .empty
            return
        }
        switch phase {
        case .failure(let error) where (error as? URLError)?.code == .cancelled:
            phase = .empty
            fallthrough
        case .empty:
            do {
                let (location, _) =  try await TetraExtension(base: URLSession.shared).download(from: url)
                let image:CGImage?
                #if canImport(CoreImage)
                image = CIImage(contentsOf: location)?.cgImage
                #else
                image = UIImage(contentsOfFile: location.path)?.cgImage
                #endif
                if let image {
                    withTransaction(transaction) {
                        phase = .success(Image(decorative: image, scale: scale))
                    }
                } else {
                    throw URLError(.cannotDecodeContentData)
                }
            } catch {
                withTransaction(transaction) {
                    phase = .failure(error)
                }
            }
        default:
            break
        }
    }

    public var body: some View {
        if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
            someView
        } else if #available(iOS 14.0, tvOS 14.0, macCatalyst 14.0, watchOS 7.0, macOS 11.0, *) {
            contentOrImage
                .async(id: url) { @MainActor in
                    await loadImage()
                }
        } else {
            contentOrImage
                .background(
                    Spacer(minLength: 0)
                        .async { @MainActor in
                            await loadImage()
                        }
                        .id(url)
                )

        }
    }

    @inlinable
    public init(url: URL?, scale: CGFloat = 1) where Content == Image {
        self.url = url
        self.scale = scale
        if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
            self.someView = AnyView(AsyncImage(url: url, scale: scale))
        } else {
            self.someView = AnyView(EmptyView())
        }
    }

    @inlinable
    public init<I, P>(
        url: URL?,
        scale: CGFloat = 1,
        content: @escaping (Image) -> I,
        placeholder: @escaping () -> P
    ) where Content == _ConditionalContent<I, P> {
        self.init(url: url, scale: scale) { phase in
            if let image = phase.image {
                content(image)
            } else {
                placeholder()
            }
        }
        if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
            self.someView = AnyView(
                AsyncImage(
                    url: url,
                    scale: scale,
                    content: content,
                    placeholder: placeholder
                )
            )
        } else {
            self.someView = AnyView(EmptyView())
        }
    }

    @inlinable
    public init(
        url: URL?,
        scale: CGFloat = 1,
        transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (CompatAsyncImagePhase) -> Content
    ) {
        self.url = url
        self.scale = scale
        self.content = content
        self.transaction = transaction
        if #available(iOS 15.0, tvOS 15.0, macCatalyst 15.0, watchOS 8.0, macOS 12.0, *) {
            self.someView = AnyView(
                SwiftUI.AsyncImage(
                    url: url,
                    scale: scale,
                    transaction: transaction
                ) { phase in
                    switch phase {
                    case .empty:
                        content(.empty)
                    case .success(let image):
                        content(.success(image))
                    case .failure(let error):
                        content(.failure(error))
                    @unknown default:
                        EmptyView()
                    }
                }
            )
        } else {
            self.someView = AnyView(EmptyView())
        }
    }
}


#endif
