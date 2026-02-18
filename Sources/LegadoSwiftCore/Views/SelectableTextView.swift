import SwiftUI
import AppKit

/// A simple wrapper around NSTextView for SwiftUI with custom context menu
struct SelectableTextView: NSViewRepresentable {
    let text: String
    let font: NSFont
    let textColor: NSColor
    let backgroundColor: NSColor
    let lineSpacing: CGFloat
    let kerning: CGFloat
    let isSelectable: Bool
    
    var onSelectionChange: ((String) -> Void)?
    var onAddNote: ((String) -> Void)?
    
    init(
        text: String,
        font: NSFont,
        textColor: NSColor,
        backgroundColor: NSColor = .clear,
        lineSpacing: CGFloat = 0,
        kerning: CGFloat = 0,
        isSelectable: Bool = true,
        onSelectionChange: ((String) -> Void)? = nil,
        onAddNote: ((String) -> Void)? = nil
    ) {
        self.text = text
        self.font = font
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.lineSpacing = lineSpacing
        self.kerning = kerning
        self.isSelectable = isSelectable
        self.onSelectionChange = onSelectionChange
        self.onAddNote = onAddNote
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        
        let textView = NSTextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = isSelectable
        textView.isRichText = false
        textView.font = font
        textView.textColor = textColor
        textView.autoresizingMask = [.width]
        textView.translatesAutoresizingMaskIntoConstraints = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        
        // Set delegate
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.onAddNote = onAddNote
        
        // Apply attributed string with paragraph style
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
        
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
        
        scrollView.documentView = textView
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        
        // Update text if changed
        if textView.string != text {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = lineSpacing
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle
            ]
            
            textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
        }
        
        context.coordinator.onAddNote = onAddNote
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView?
        var onAddNote: ((String) -> Void)?
        
        // NSTextViewDelegate - custom context menu
        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            // Get selected text
            let selectedRange = view.selectedRange()
            var selectedText = ""
            
            if selectedRange.length > 0, let textStorage = view.textStorage {
                selectedText = textStorage.attributedSubstring(from: selectedRange).string
            }
            
            // Create new menu with custom items
            let customMenu = NSMenu(title: "")
            
            // Add "添加笔记" menu item if there's selected text
            if !selectedText.isEmpty {
                let addNoteItem = NSMenuItem(
                    title: "添加笔记",
                    action: #selector(addNoteAction(_:)),
                    keyEquivalent: ""
                )
                addNoteItem.representedObject = selectedText
                addNoteItem.target = self
                customMenu.addItem(addNoteItem)
                
                customMenu.addItem(NSMenuItem.separator())
            }
            
            // Add standard items
            let copyItem = NSMenuItem(
                title: "复制",
                action: #selector(NSText.copy(_:)),
                keyEquivalent: "c"
            )
            copyItem.target = view
            customMenu.addItem(copyItem)
            
            let selectAllItem = NSMenuItem(
                title: "全选",
                action: #selector(NSText.selectAll(_:)),
                keyEquivalent: "a"
            )
            selectAllItem.target = view
            customMenu.addItem(selectAllItem)
            
            return customMenu
        }
        
        @objc private func addNoteAction(_ sender: NSMenuItem) {
            guard let selectedText = sender.representedObject as? String else { return }
            onAddNote?(selectedText)
        }
    }
}