//
//  KeyAwareScrollView.swift
//  LegadoSwift
//
//  A scroll view that handles arrow key navigation for reading.
//  - Up/Down arrows: scroll one page at a time
//  - Left/Right arrows: directly change chapter
//  - Auto chapter navigation when reaching top/bottom boundary
//

import SwiftUI
import AppKit

/// A scroll view that intercepts keyboard events for page navigation
struct KeyAwareScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    let onUpArrow: () -> Void      // Called when at top and up arrow pressed (go to previous chapter)
    let onDownArrow: () -> Void    // Called when at bottom and down arrow pressed (go to next chapter)
    let onLeftArrow: () -> Void    // Previous chapter
    let onRightArrow: () -> Void   // Next chapter
    let onSpace: () -> Void        // Called when at bottom and space pressed (go to next chapter)
    let isEnabled: Bool            // Whether keyboard navigation is enabled
    
    // Callback to track scroll position
    let onScrollPositionChange: ((isAtTop: Bool, isAtBottom: Bool)) -> Void
    
    init(
        isEnabled: Bool = true,
        onUpArrow: @escaping () -> Void,
        onDownArrow: @escaping () -> Void,
        onLeftArrow: @escaping () -> Void,
        onRightArrow: @escaping () -> Void,
        onSpace: @escaping () -> Void,
        onScrollPositionChange: @escaping ((isAtTop: Bool, isAtBottom: Bool)) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isEnabled = isEnabled
        self.onUpArrow = onUpArrow
        self.onDownArrow = onDownArrow
        self.onLeftArrow = onLeftArrow
        self.onRightArrow = onRightArrow
        self.onSpace = onSpace
        self.onScrollPositionChange = onScrollPositionChange
        self.content = content()
    }
    
    func makeNSView(context: Context) -> NSView {
        let container = KeyboardHandlingContainerView()
        
        // Create scroll view
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        // Create hosting view for SwiftUI content
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = hostingView
        
        // Add scroll view to container
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        
        // Store references
        container.scrollView = scrollView
        container.onUpArrow = onUpArrow
        container.onDownArrow = onDownArrow
        container.onLeftArrow = onLeftArrow
        container.onRightArrow = onRightArrow
        container.onSpace = onSpace
        container.onScrollPositionChange = onScrollPositionChange
        container.isKeyboardEnabled = isEnabled
        
        // Set up notification for scroll position tracking
        context.coordinator.scrollView = scrollView
        context.coordinator.onScrollPositionChange = onScrollPositionChange
        context.coordinator.containerView = container
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollPositionChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        
        // Set up local keyboard event monitor
        context.coordinator.setupKeyboardMonitor(container: container)
        
        return container
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let container = nsView as? KeyboardHandlingContainerView,
              let scrollView = container.scrollView,
              let hostingView = scrollView.documentView as? NSHostingView<Content> else {
            return
        }
        
        // Update content
        hostingView.rootView = content
        
        // Update callbacks
        container.onUpArrow = onUpArrow
        container.onDownArrow = onDownArrow
        container.onLeftArrow = onLeftArrow
        container.onRightArrow = onRightArrow
        container.onSpace = onSpace
        container.onScrollPositionChange = onScrollPositionChange
        container.isKeyboardEnabled = isEnabled
        context.coordinator.onScrollPositionChange = onScrollPositionChange
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var scrollView: NSScrollView?
        var containerView: KeyboardHandlingContainerView?
        var onScrollPositionChange: ((isAtTop: Bool, isAtBottom: Bool)) -> Void = { _ in }
        private var keyboardMonitor: Any?
        
        deinit {
            if let monitor = keyboardMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        
        func setupKeyboardMonitor(container: KeyboardHandlingContainerView) {
            // Remove existing monitor
            if let monitor = keyboardMonitor {
                NSEvent.removeMonitor(monitor)
            }
            
            // Add local monitor for keyboard events
            keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak container] event in
                guard let container = container else { return event }
                
                // Only handle if container is in a window and visible
                guard container.window != nil && container.isHidden == false else { return event }
                
                // Check if keyboard navigation is enabled
                guard container.isKeyboardEnabled else { return event }
                
                let keyCode = Int(event.keyCode)
                
                // macOS key codes
                // Up arrow: 126
                // Down arrow: 125
                // Left arrow: 123
                // Right arrow: 124
                // Space: 49
                
                switch keyCode {
                case 126: // Up arrow
                    // Check if already at top BEFORE trying to scroll
                    if container.isAtTop {
                        // At top, trigger chapter change
                        _ = container.onUpArrow()
                    } else {
                        // Not at top, try to scroll first
                        container.scrollPageUp()
                    }
                    return nil
                    
                case 125: // Down arrow
                    // Check if already at bottom BEFORE trying to scroll
                    if container.isAtBottom {
                        // At bottom, trigger chapter change
                        _ = container.onDownArrow()
                    } else {
                        // Not at bottom, try to scroll first
                        container.scrollPageDown()
                    }
                    return nil
                    
                case 123: // Left arrow
                    container.onLeftArrow()
                    return nil
                    
                case 124: // Right arrow
                    container.onRightArrow()
                    return nil
                    
                case 49: // Space
                    // Check if already at bottom BEFORE trying to scroll
                    if container.isAtBottom {
                        // At bottom, trigger chapter change
                        _ = container.onSpace()
                    } else {
                        // Not at bottom, scroll down
                        container.scrollPageDown()
                    }
                    return nil
                    
                default:
                    return event
                }
            }
        }
        
        @objc func scrollPositionChanged(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView else { return }
            
            let documentView = clipView.documentView
            let visibleRect = clipView.documentVisibleRect
            let contentHeight = documentView?.frame.height ?? 0
            let visibleHeight = visibleRect.height
            
            // Check if at top (within 5 points of top)
            let isAtTop = visibleRect.origin.y <= 5
            
            // Check if at bottom (within 50 points of bottom)
            let bottomOffset = visibleRect.origin.y + visibleHeight
            let isAtBottom = contentHeight > 0 && bottomOffset >= contentHeight - 50
            
            // Update container view
            containerView?.isAtTop = isAtTop
            containerView?.isAtBottom = isAtBottom
            
            DispatchQueue.main.async { [weak self] in
                self?.onScrollPositionChange((isAtTop, isAtBottom))
            }
        }
    }
}

/// Container view that handles keyboard events and contains a scroll view
class KeyboardHandlingContainerView: NSView {
    var scrollView: NSScrollView?
    var onUpArrow: () -> Void = { }
    var onDownArrow: () -> Void = { }
    var onLeftArrow: () -> Void = { }
    var onRightArrow: () -> Void = { }
    var onSpace: () -> Void = { }
    var onScrollPositionChange: ((isAtTop: Bool, isAtBottom: Bool)) -> Void = { _ in }
    var isKeyboardEnabled: Bool = true  // Control keyboard navigation
    
    // Track scroll position internally - public for Coordinator access
    var isAtTop: Bool = true
    var isAtBottom: Bool = false
    
    override var acceptsFirstResponder: Bool { true }
    
    override func becomeFirstResponder() -> Bool {
        return true
    }
    
    override func resignFirstResponder() -> Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        // This is a fallback - the local monitor should handle most events
        let keyCode = Int(event.keyCode)
        
        switch keyCode {
        case 126: // Up arrow
            if isAtTop {
                onUpArrow()
            } else {
                scrollPageUp()
            }
            
        case 125: // Down arrow
            if isAtBottom {
                onDownArrow()
            } else {
                scrollPageDown()
            }
            
        case 123: // Left arrow
            onLeftArrow()
            
        case 124: // Right arrow
            onRightArrow()
            
        case 49: // Space
            if isAtBottom {
                onSpace()
            } else {
                scrollPageDown()
            }
            
        default:
            super.keyDown(with: event)
        }
    }
    
    func scrollPageUp() {
        guard let scrollView = scrollView,
              let documentView = scrollView.documentView else { return }
        
        let clipView = scrollView.contentView
        let visibleRect = clipView.documentVisibleRect
        let pageHeight = visibleRect.height - 40
        
        var newOrigin = visibleRect.origin
        newOrigin.y = max(0, newOrigin.y - pageHeight)
        
        // 使用平滑滚动动画
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            clipView.animator().setBoundsOrigin(newOrigin)
        }, completionHandler: {
            // 动画完成后更新滚动条
            scrollView.reflectScrolledClipView(clipView)
        })
    }
    
    func scrollPageDown() {
        guard let scrollView = scrollView,
              let documentView = scrollView.documentView else { return }
        
        let clipView = scrollView.contentView
        let visibleRect = clipView.documentVisibleRect
        let contentHeight = documentView.frame.height
        let pageHeight = visibleRect.height - 40
        
        var newOrigin = visibleRect.origin
        newOrigin.y = min(max(0, contentHeight - visibleRect.height), newOrigin.y + pageHeight)
        
        // 使用平滑滚动动画
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            clipView.animator().setBoundsOrigin(newOrigin)
        }, completionHandler: {
            // 动画完成后更新滚动条
            scrollView.reflectScrolledClipView(clipView)
        })
    }
}
