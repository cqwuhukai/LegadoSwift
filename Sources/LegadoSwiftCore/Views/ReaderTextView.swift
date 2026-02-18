import AppKit
import SwiftUI

// MARK: - AppKit Text View with Context Menu

/// AppKit 文本视图，支持右键菜单和文本选择
public class ReaderTextView: NSView {
    
    // MARK: - Properties
    
    private var scrollView: NSScrollView!
    private var textView: NSTextView!
    
    // 回调
    public var onAddNote: ((String) -> Void)?
    public var onScrollPositionChange: ((Bool, Bool) -> Void)?
    public var onAtTop: (() -> Void)?
    public var onAtBottom: (() -> Void)?
    
    // 配置
    public var fontSize: CGFloat = 18
    public var lineSpacing: CGFloat = 8
    public var paragraphSpacing: CGFloat = 12
    public var fontFamily: String = "Times New Roman"
    public var textColor: NSColor = .textColor
    public var bgColor: NSColor = .textBackgroundColor
    public var firstLineIndent: Bool = true
    public var letterSpacing: CGFloat = 0.5
    
    // 内容
    private var rawContent: String = ""
    private var chapterTitle: String = ""
    
    // 滚动状态
    public var isAtTop: Bool = true
    public var isAtBottom: Bool = false
    private var isScrolling: Bool = false
    
    // 静态键盘监听器（全局只有一个）
    private static var keyboardMonitor: Any?
    private static weak var activeView: ReaderTextView?
    
    // MARK: - Initialization
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    // 让视图接受键盘事件
    public override var acceptsFirstResponder: Bool { true }
    
    public override func becomeFirstResponder() -> Bool {
        return true
    }
    
    // 处理键盘事件（作为备用）
    public override func keyDown(with event: NSEvent) {
        if handleKeyEvent(event) {
            return
        }
        super.keyDown(with: event)
    }
    
    // 统一的键盘事件处理
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        // Command 快捷键
        if flags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "f":
                NotificationCenter.default.post(name: .toggleFullscreen, object: nil)
                return true
            case "l":
                NotificationCenter.default.post(name: .toggleChapterList, object: nil)
                return true
            case "b":
                NotificationCenter.default.post(name: .addBookmark, object: nil)
                return true
            default:
                break
            }
        }
        
        // 功能键
        switch event.keyCode {
        case 126: // Up arrow
            if isAtTop {
                NotificationCenter.default.post(name: .previousChapter, object: nil)
            } else {
                pageUp()
            }
            return true
        case 125: // Down arrow
            if isAtBottom {
                NotificationCenter.default.post(name: .nextChapter, object: nil)
            } else {
                pageDown()
            }
            return true
        case 123: // Left arrow
            NotificationCenter.default.post(name: .previousChapter, object: nil)
            return true
        case 124: // Right arrow
            NotificationCenter.default.post(name: .nextChapter, object: nil)
            return true
        case 49: // Space
            if flags.isEmpty {
                if isAtBottom {
                    NotificationCenter.default.post(name: .nextChapter, object: nil)
                } else {
                    pageDown()
                }
                return true
            }
        case 53: // Escape
            NotificationCenter.default.post(name: .closeReader, object: nil)
            return true
        default:
            break
        }
        
        return false
    }
    
    private func setupViews() {
        wantsLayer = true
        
        // 创建滚动视图
        scrollView = NSScrollView(frame: bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        
        // 创建文本视图
        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: 0))
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.importsGraphics = false
        textView.drawsBackground = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        
        // 配置文本容器
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 8
        
        // 设置文本内边距
        textView.textContainerInset = NSSize(width: 60, height: 50)
        
        // 添加右键菜单
        setupContextMenu()
        
        scrollView.documentView = textView
        addSubview(scrollView)
        
        // 监听滚动
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        
        // 监听翻页通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePageUp(_:)),
            name: .pageUp,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePageDown(_:)),
            name: .pageDown,
            object: nil
        )
    }
    
    // MARK: - Page Navigation Notifications
    
    @objc private func handlePageUp(_ notification: Notification) {
        pageUp()
    }
    
    @objc private func handlePageDown(_ notification: Notification) {
        pageDown()
    }
    
    // MARK: - Context Menu
    
    private func setupContextMenu() {
        let menu = NSMenu()
        
        // 添加笔记
        let addNoteItem = NSMenuItem(title: "添加笔记", action: #selector(addNoteAction(_:)), keyEquivalent: "")
        addNoteItem.target = self
        menu.addItem(addNoteItem)
        
        // 添加书签
        let addBookmarkItem = NSMenuItem(title: "添加书签", action: #selector(addBookmarkAction(_:)), keyEquivalent: "b")
        addBookmarkItem.target = self
        addBookmarkItem.keyEquivalentModifierMask = .command
        menu.addItem(addBookmarkItem)
        
        // 分隔线
        menu.addItem(NSMenuItem.separator())
        
        // 复制
        let copyItem = NSMenuItem(title: "复制", action: #selector(copyAction(_:)), keyEquivalent: "c")
        copyItem.target = self
        copyItem.keyEquivalentModifierMask = .command
        menu.addItem(copyItem)
        
        // 分隔线
        menu.addItem(NSMenuItem.separator())
        
        // 搜索
        let searchItem = NSMenuItem(title: "搜索选中文字", action: #selector(searchAction(_:)), keyEquivalent: "")
        searchItem.target = self
        menu.addItem(searchItem)
        
        textView.menu = menu
    }
    
    @objc private func addNoteAction(_ sender: NSMenuItem) {
        let selectedText = getSelectedText()
        if !selectedText.isEmpty {
            onAddNote?(selectedText)
        } else {
            let paragraph = getCurrentParagraph()
            if !paragraph.isEmpty {
                onAddNote?(paragraph)
            }
        }
    }
    
    @objc private func addBookmarkAction(_ sender: NSMenuItem) {
        NotificationCenter.default.post(name: .addBookmark, object: nil)
    }
    
    @objc private func copyAction(_ sender: NSMenuItem) {
        let selectedText = getSelectedText()
        if !selectedText.isEmpty {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(selectedText, forType: .string)
        }
    }
    
    @objc private func searchAction(_ sender: NSMenuItem) {
        let selectedText = getSelectedText()
        if !selectedText.isEmpty {
            if let url = URL(string: "https://www.google.com/search?q=\(selectedText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    // MARK: - Text Helpers
    
    private func getSelectedText() -> String {
        guard let selectedRange = textView.selectedRanges.first as? NSRange,
              selectedRange.length > 0 else {
            return ""
        }
        
        let text = textView.string
        if selectedRange.location < text.count {
            let start = text.index(text.startIndex, offsetBy: selectedRange.location)
            let end = text.index(start, offsetBy: min(selectedRange.length, text.count - selectedRange.location))
            return String(text[start..<end])
        }
        return ""
    }
    
    private func getCurrentParagraph() -> String {
        guard let selectedRange = textView.selectedRanges.first as? NSRange else {
            return ""
        }
        
        let text = textView.string as NSString
        let paragraphRange = text.paragraphRange(for: NSRange(location: selectedRange.location, length: 0))
        return text.substring(with: paragraphRange).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Content Management
    
    /// 更新内容和配置 - 主入口
    public func update(content: String, title: String, config: ReaderConfig) {
        var needsFullUpdate = false
        
        // 检查内容是否变化
        if content != rawContent || title != chapterTitle {
            rawContent = content
            chapterTitle = title
            needsFullUpdate = true
        }
        
        // 检查配置是否变化
        if fontSize != config.fontSize ||
           lineSpacing != config.lineSpacing ||
           paragraphSpacing != config.paragraphSpacing ||
           fontFamily != config.fontFamily ||
           textColor != config.textColor ||
           bgColor != config.bgColor ||
           firstLineIndent != config.firstLineIndent ||
           letterSpacing != config.letterSpacing {
            
            fontSize = config.fontSize
            lineSpacing = config.lineSpacing
            paragraphSpacing = config.paragraphSpacing
            fontFamily = config.fontFamily
            textColor = config.textColor
            bgColor = config.bgColor
            firstLineIndent = config.firstLineIndent
            letterSpacing = config.letterSpacing
            
            needsFullUpdate = true
        }
        
        // 需要更新时才刷新
        if needsFullUpdate {
            refreshDisplay(scrollToTop: content != rawContent || title != chapterTitle)
        }
    }
    
    /// 刷新显示
    private func refreshDisplay(scrollToTop: Bool = false) {
        // 构建全文
        var fullText = ""
        
        if !chapterTitle.isEmpty {
            fullText = chapterTitle + "\n\n"
        }
        
        let paragraphs = rawContent.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        let formattedParagraphs = paragraphs.map { formatParagraph($0) }
        fullText += formattedParagraphs.joined(separator: "\n\n")
        
        // 创建属性字符串
        let attributedString = NSMutableAttributedString(string: fullText)
        applyAttributes(to: attributedString)
        
        // 设置文本
        textView.textStorage?.setAttributedString(attributedString)
        textView.backgroundColor = bgColor
        scrollView.backgroundColor = bgColor
        
        // 强制布局更新
        textView.needsLayout = true
        textView.layout()
        
        // 需要滚动到顶部时
        if scrollToTop {
            DispatchQueue.main.async { [weak self] in
                self?.scrollToTopImmediate()
            }
        }
    }
    
    private func formatParagraph(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "" }
        
        if !firstLineIndent {
            return trimmed
        }
        
        if trimmed.hasPrefix("　　") || trimmed.hasPrefix("  ") {
            return trimmed
        }
        
        if let firstChar = trimmed.first {
            if firstChar.unicodeScalars.first.map({ scalar in
                let value = scalar.value
                return (value >= 0x4E00 && value <= 0x9FFF) ||
                       (value >= 0x3000 && value <= 0x303F) ||
                       (value >= 0xFF00 && value <= 0xFFEF)
            }) ?? false {
                return "　　" + trimmed
            }
        }
        
        return trimmed
    }
    
    private func applyAttributes(to attributedString: NSMutableAttributedString) {
        let font = NSFont(name: fontFamily, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = paragraphSpacing
        paragraphStyle.alignment = .left
        
        let range = NSRange(location: 0, length: attributedString.length)
        
        attributedString.addAttribute(.font, value: font, range: range)
        attributedString.addAttribute(.foregroundColor, value: textColor, range: range)
        attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        attributedString.addAttribute(.kern, value: letterSpacing, range: range)
        
        // 标题样式
        if !chapterTitle.isEmpty {
            let titleRange = (attributedString.string as NSString).range(of: chapterTitle)
            if titleRange.location != NSNotFound {
                let titleFont = NSFont(name: fontFamily, size: fontSize + 10) ?? NSFont.systemFont(ofSize: fontSize + 10, weight: .bold)
                attributedString.addAttribute(.font, value: titleFont, range: titleRange)
                
                let titleStyle = NSMutableParagraphStyle()
                titleStyle.alignment = .center
                titleStyle.paragraphSpacing = fontSize * 2
                attributedString.addAttribute(.paragraphStyle, value: titleStyle, range: titleRange)
            }
        }
    }
    
    // MARK: - Page Navigation
    
    private func pageUp() {
        guard let documentView = scrollView.documentView else { return }
        let visibleRect = scrollView.contentView.documentVisibleRect
        let documentRect = documentView.bounds
        
        // 计算新位置（向上翻一页，留一点重叠）
        let pageHeight = visibleRect.height - 60
        let newOrigin = max(0, visibleRect.origin.y - pageHeight)
        
        // 平滑滚动
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: newOrigin))
        } completionHandler: { [weak self] in
            self?.checkScrollPosition()
        }
    }
    
    private func pageDown() {
        guard let documentView = scrollView.documentView else { return }
        let visibleRect = scrollView.contentView.documentVisibleRect
        let documentRect = documentView.bounds
        
        // 计算新位置（向下翻一页，留一点重叠）
        let pageHeight = visibleRect.height - 60
        let maxOrigin = max(0, documentRect.height - visibleRect.height)
        let newOrigin = min(maxOrigin, visibleRect.origin.y + pageHeight)
        
        // 平滑滚动
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: newOrigin))
        } completionHandler: { [weak self] in
            self?.checkScrollPosition()
        }
    }
    
    // MARK: - Scrolling
    
    private func scrollToTopImmediate() {
        guard let documentView = scrollView.documentView else { return }
        let point = NSPoint(x: 0, y: documentView.bounds.height)
        scrollView.contentView.scroll(to: point)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        isAtTop = true
        isAtBottom = false
    }
    
    @objc private func boundsDidChange(_ notification: Notification) {
        guard !isScrolling else { return }
        isScrolling = true
        defer { isScrolling = false }
        
        checkScrollPosition()
    }
    
    private func checkScrollPosition() {
        guard let documentView = scrollView.documentView else { return }
        
        let contentView = scrollView.contentView
        let documentRect = documentView.bounds
        let visibleRect = contentView.documentVisibleRect
        
        let wasAtTop = isAtTop
        let wasAtBottom = isAtBottom
        
        isAtTop = visibleRect.origin.y <= 5
        
        let bottomY = documentRect.height - visibleRect.height - 5
        isAtBottom = visibleRect.origin.y >= bottomY && documentRect.height > visibleRect.height
        
        if wasAtTop != isAtTop || wasAtBottom != isAtBottom {
            onScrollPositionChange?(isAtTop, isAtBottom)
        }
    }
    
    // MARK: - Layout
    
    public override func layout() {
        super.layout()
        scrollView.frame = bounds
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            // 设置为活动视图
            ReaderTextView.activeView = self
            // 设置全局键盘监听器
            setupGlobalKeyboardMonitor()
            // 让窗口成为键盘窗口
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.window?.makeKeyAndOrderFront(nil)
            }
        } else {
            // 窗口移除时清除活动视图引用
            if ReaderTextView.activeView === self {
                ReaderTextView.activeView = nil
            }
        }
    }
    
    // MARK: - Global Keyboard Monitor
    
    private func setupGlobalKeyboardMonitor() {
        // 如果已经有监听器，先移除
        if let monitor = ReaderTextView.keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            ReaderTextView.keyboardMonitor = nil
        }
        
        // 添加全局键盘监听器
        ReaderTextView.keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 检查是否有活动视图
            guard let activeView = ReaderTextView.activeView,
                  activeView.window != nil,
                  activeView.isHidden == false else {
                return event
            }
            
            // 让活动视图处理键盘事件
            if activeView.handleKeyEvent(event) {
                return nil // 事件已处理
            }
            
            return event
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        // 清除活动视图引用
        if ReaderTextView.activeView === self {
            ReaderTextView.activeView = nil
        }
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Reader Config

public struct ReaderConfig: Equatable {
    public var fontSize: CGFloat
    public var lineSpacing: CGFloat
    public var paragraphSpacing: CGFloat
    public var fontFamily: String
    public var textColor: NSColor
    public var bgColor: NSColor
    public var firstLineIndent: Bool
    public var letterSpacing: CGFloat
    
    public init(
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat,
        fontFamily: String,
        textColor: NSColor,
        bgColor: NSColor,
        firstLineIndent: Bool,
        letterSpacing: CGFloat
    ) {
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
        self.fontFamily = fontFamily
        self.textColor = textColor
        self.bgColor = bgColor
        self.firstLineIndent = firstLineIndent
        self.letterSpacing = letterSpacing
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let addBookmark = Notification.Name("addBookmark")
    static let addNote = Notification.Name("addNote")
    static let previousChapter = Notification.Name("previousChapter")
    static let nextChapter = Notification.Name("nextChapter")
    static let toggleFullscreen = Notification.Name("toggleFullscreen")
    static let toggleChapterList = Notification.Name("toggleChapterList")
    static let closeReader = Notification.Name("closeReader")
    static let pageUp = Notification.Name("pageUp")
    static let pageDown = Notification.Name("pageDown")
}

// MARK: - SwiftUI Wrapper

public struct ReaderTextViewWrapper: NSViewRepresentable {
    let content: String
    let chapterTitle: String
    let config: ReaderConfig
    
    let onAddNote: (String) -> Void
    let onScrollPositionChange: (Bool, Bool) -> Void
    let onAtTop: () -> Void
    let onAtBottom: () -> Void
    
    public init(
        content: String,
        chapterTitle: String,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        paragraphSpacing: CGFloat,
        fontFamily: String,
        textColor: Color,
        bgColor: Color,
        firstLineIndent: Bool,
        letterSpacing: CGFloat,
        onAddNote: @escaping (String) -> Void,
        onScrollPositionChange: @escaping (Bool, Bool) -> Void,
        onAtTop: @escaping () -> Void,
        onAtBottom: @escaping () -> Void
    ) {
        self.content = content
        self.chapterTitle = chapterTitle
        self.config = ReaderConfig(
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            paragraphSpacing: paragraphSpacing,
            fontFamily: fontFamily,
            textColor: NSColor(textColor),
            bgColor: NSColor(bgColor),
            firstLineIndent: firstLineIndent,
            letterSpacing: letterSpacing
        )
        self.onAddNote = onAddNote
        self.onScrollPositionChange = onScrollPositionChange
        self.onAtTop = onAtTop
        self.onAtBottom = onAtBottom
    }
    
    public func makeNSView(context: Context) -> ReaderTextView {
        let view = ReaderTextView()
        view.onAddNote = onAddNote
        view.onScrollPositionChange = onScrollPositionChange
        view.onAtTop = onAtTop
        view.onAtBottom = onAtBottom
        view.update(content: content, title: chapterTitle, config: config)
        return view
    }
    
    public func updateNSView(_ nsView: ReaderTextView, context: Context) {
        nsView.update(content: content, title: chapterTitle, config: config)
        
        nsView.onAddNote = onAddNote
        nsView.onScrollPositionChange = onScrollPositionChange
        nsView.onAtTop = onAtTop
        nsView.onAtBottom = onAtBottom
    }
}
