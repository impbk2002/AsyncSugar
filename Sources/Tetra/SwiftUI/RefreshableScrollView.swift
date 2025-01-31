//
//  RefreshableScrollView.swift
//
//
//  Created by pbk on 2022/09/30.
//

import Foundation
import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

@available(iOS, deprecated: 16, renamed: "ScrollView")
@available(tvOS, deprecated: 16, renamed: "ScrollView")
@available(macCatalyst, deprecated: 16, renamed: "ScrollView")
@available(macOS, deprecated: 13, renamed: "ScrollView")
@available(watchOS, deprecated: 9, renamed: "ScrollView")
public struct RefreshableScrollView<Content:View>: View {
    
    @State private var task:Task<Void,Never>? = nil
    @State private var flag = false
    
    public var content:Content
    public var axes: Axis.Set = .vertical
    public var showsIndicators: Bool = true
    
    
    public var body: some View {
        ScrollView(axes, showsIndicators: showsIndicators) {
#if os(iOS) || targetEnvironment(macCatalyst)
            if #available(iOS 16.0, macCatalyst 16.0, *) {
                content
            } else if #available(iOS 15.0, macCatalyst 15.0, *) {
                content
                    .modifier(RefreshActionModifier(task: $task, refreshing: $flag))
            }
#else
            content
#endif

        }
        .onDisappear{
            task?.cancel()
            task = nil
            flag = false
        }
    }
    
    @inlinable
    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.axes = axes
        self.showsIndicators = showsIndicators
    }
    
}

public extension View {
    
    @available(iOS, deprecated: 16, renamed: "refreshable")
    @available(tvOS, deprecated: 16, renamed: "refreshable")
    @available(macCatalyst, deprecated: 16, renamed: "refreshable")
    @available(macOS, deprecated: 13, renamed: "refreshable")
    @available(watchOS, deprecated: 9, renamed: "refreshable")
    @inlinable
    @ViewBuilder
    func refreshControl(action: @escaping @Sendable () async -> Void) -> some View {
        if #available(iOS 15.0, tvOS 15.0, macOS 12.0, macCatalyst 15.0, watchOS 8.0, *) {
            self.refreshable(action: action)
        } else {
            #if os(iOS) || targetEnvironment(macCatalyst)
            self.environment(\.refreshControl, .init(action: action))
            #else
            self
            #endif
        }
    }
    
}

@usableFromInline internal
struct RefreshActionModifier: ViewModifier {
    
    @Binding var task:Task<Void,Never>?
    @Binding var refreshing:Bool
    @Environment(\.self) private var environment
    
    @usableFromInline
    func body(content: Content) -> some View {
#if os(iOS) || targetEnvironment(macCatalyst)
        content.background(
            Group{
                let action = if #available(iOS 15.0, tvOS 15.0, macOS 12.0, macCatalyst 15.0, watchOS 8.0, *) {
                    environment.refresh?.callAsFunction
                } else {
                    environment.refreshControl?.action
                }
                if let action {
                    ScrollRefreshImp(task: $task, refreshing: refreshing) {
                        refreshing = true
                        defer { refreshing = false }
                        await action()
                    }.frame(width: 0, height: 0)
                }
                
            }
        )
#else
        content
#endif
    }
    

}


internal struct RefreshControlKey: EnvironmentKey {
    static var defaultValue: RefreshableControl? { nil }
}

@usableFromInline
internal struct RefreshableControl {
    
    internal var action:@Sendable () async -> Void

    @usableFromInline
    init(action: @Sendable @escaping () async -> Void) {
        self.action = action
    }
    
}

extension EnvironmentValues {
    @usableFromInline
    var refreshControl: RefreshableControl? {
        get {
            return self[RefreshControlKey.self]
        }
        set {
            self[RefreshControlKey.self] = newValue
        }
        
    }
}

#if os(iOS) || targetEnvironment(macCatalyst)

@usableFromInline
internal struct ScrollRefreshImp: UIViewRepresentable {
    
    public typealias UIViewType = SuperViewCallbackUIView
    public typealias Coordinator = RefreshingCoordinator
    @usableFromInline
    @Binding var task:Task<Void,Never>?
    @usableFromInline
    var refreshing:Bool
    @usableFromInline
    let operation: () async -> Void
    
    @usableFromInline
    internal init(
        task: Binding<Task<Void, Never>?>,
        refreshing: Bool,
        operation: @escaping () async -> Void
    ) {
        self._task = task
        self.refreshing = refreshing
        self.operation = operation
    }
    
    @inlinable
    public func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(parent: self)
        return coordinator
    }
    
    @inlinable
    public func makeUIView(context: Context) -> UIViewType {
        let uiView = UIViewType()
        uiView.isUserInteractionEnabled = false
        uiView.isHidden = true
        context.coordinator.control.addTarget(context.coordinator, action: #selector(RefreshingCoordinator.refresh), for: .valueChanged)
        uiView.callBack = { [coordinator = context.coordinator] superView in
            if let scrollView = superView?.target(forAction: #selector(UIScrollView.scrollRectToVisible(_:animated:)), withSender: nil) as? UIScrollView {
                scrollView.refreshControl = coordinator.control
                coordinator.scrollView = scrollView
            } else {
                coordinator.scrollView = nil
            }
        }
        return uiView
    }
    
    @inlinable
    public func updateUIView(_ uiView: UIViewType, context: Context) {
        uiView.callBack = { [coordinator = context.coordinator] superView in
            if let scrollView = superView?.target(forAction: #selector(UIScrollView.scrollRectToVisible(_:animated:)), withSender: nil) as? UIScrollView {
                scrollView.refreshControl = coordinator.control
                coordinator.scrollView = scrollView
            } else {
                coordinator.scrollView = nil
            }
        }
        context.coordinator.parent = self
        if !refreshing && context.coordinator.control.isRefreshing {
            context.coordinator.control.endRefreshing()
        } else if refreshing && !context.coordinator.control.isRefreshing {
            context.coordinator.control.beginRefreshing()
        }
    }
    
    @inlinable
    public static func dismantleUIView(_ uiView: UIViewType, coordinator: Coordinator) {
        uiView.callBack = nil
        if let scrollView = coordinator.scrollView, scrollView.refreshControl === coordinator.control {
            scrollView.refreshControl = nil
        }
        coordinator.parent.task?.cancel()
    }
    
    
}

@usableFromInline
@MainActor
internal final class RefreshingCoordinator: NSObject {
    
    @usableFromInline
    weak var scrollView:UIScrollView? = nil
    
    @usableFromInline
    internal init(parent: ScrollRefreshImp) {
        self.parent = parent
        self.control = UIRefreshControl()
        super.init()
    }
    
    @usableFromInline
    let control:UIRefreshControl
    @usableFromInline
    var parent:ScrollRefreshImp
    
    @usableFromInline
    @objc func refresh() {
        parent.task?.cancel()
        parent.task = Task{  await parent.operation() }
    }
    
}
#endif

