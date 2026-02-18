
import SwiftUI
import AppKit

struct FocusableOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> FocusableView {
        let view = FocusableView()
        return view
    }

    func updateNSView(_ nsView: FocusableView, context: Context) {
        // No updates needed
    }

    class FocusableView: NSView {
        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // When added to window, try to become first responder
            DispatchQueue.main.async {
                self.window?.makeFirstResponder(self)
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
        
        // Forward key events to SwiftUI environment if needed, 
        // or just let them bubble up to the SwiftUI view hierarchy which handles onKeyPress
        // But for arrow keys to work on the SwiftUI view, the SwiftUI view needs focus.
        // If we make THIS view the first responder, we might intercept keys.
        // Actually, SwiftUI's focus system coordinates with AppKit.
        // If this view is the first responder, the SwiftUI view hosting it might not get key events unless we forward them.
        
        // HOWEVER, the user says "click to enter".
        // The issue is likely that NOTHING is first responder consistently.
        // If we make the Window's content view the first responder?
        
        // Better approach:
        // Use this view to TRIGGER window to make the SwiftUI focus system work.
        // But SwiftUI's .focusable() should work if window is key.
        // The issue might be Sidebar or SplitView stealing focus.
        
        // Let's try to just use this view to Hide Cursor and ensuring Window is Key.
    }
}
