import SwiftUI
import AppKit
import SwiftUI

struct ReaderView: View {
    @Environment(BookManager.self) private var bookManager
    @Environment(ReadingConfig.self) private var config
    @State private var showChapterList = false
    @State private var showSettings = false
    @State private var showBookmarks = false
    @State private var isFullscreen = false

    @FocusState private var isFocused: Bool
    
    // Scroll position tracking
    @State private var isAtTop: Bool = true
    @State private var isAtBottom: Bool = false
    @State private var currentScrollOffset: Double = 0
    
    // Note taking - 使用 noteDialogText 作为对话框显示的文本快照
    @State private var showNoteDialog = false
    @State private var showNotes = false  // 查看笔记面板
    @State private var noteDialogText: String = ""  // 对话框中显示的原文
    @State private var selectedParagraphText: String = ""  // 当前选中的文本
    @State private var noteText: String = ""
    
    // 键盘事件监听器
    @State private var keyboardMonitor: Any?

    var body: some View {
        HStack(spacing: 0) {
            // Chapter sidebar - hidden by default when opening reader
            if showChapterList && !isFullscreen {
                chapterSidebar
                    .frame(width: 260)
                    .transition(.move(edge: .leading))
            }

            // Main content
            VStack(spacing: 0) {
                if !isFullscreen {
                    readerToolbar
                }
                readerContent
                readerBottomBar
            }
        }
        .background(config.theme.bgColor)
        .animation(.spring(duration: 0.3), value: showChapterList)
        .animation(.spring(duration: 0.3), value: isFullscreen)
        .onKeyPress(.escape) {
            if showNoteDialog {
                showNoteDialog = false
                return .handled
            }
            if isFullscreen {
                isFullscreen = false
            } else {
                bookManager.closeBook()
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            // 上翻页，如果在顶部则进入上一章
            if isAtTop {
                _ = bookManager.previousChapter()
            } else {
                NotificationCenter.default.post(name: .pageUp, object: nil)
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            // 下翻页，如果在底部则进入下一章
            if isAtBottom {
                _ = bookManager.nextChapter()
            } else {
                NotificationCenter.default.post(name: .pageDown, object: nil)
            }
            return .handled
        }
        .onKeyPress(.leftArrow) {
            _ = bookManager.previousChapter()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            _ = bookManager.nextChapter()
            return .handled
        }
        .onKeyPress(.space) {
            // 空格下翻页，如果在底部则进入下一章
            if isAtBottom {
                _ = bookManager.nextChapter()
            } else {
                NotificationCenter.default.post(name: .pageDown, object: nil)
            }
            return .handled
        }
        .onChange(of: bookManager.currentChapterIndex) { _, _ in
            // Reset scroll position flags when changing chapter
            isAtTop = true
            isAtBottom = false
        }
        .background {
            Button("") { isFullscreen.toggle() }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
        .background {
            Button("") { showChapterList.toggle() }
                .keyboardShortcut("l", modifiers: .command)
                .hidden()
        }
        .background {
            Button("") { addBookmarkAtCurrentPosition() }
                .keyboardShortcut("b", modifiers: .command)
                .hidden()
        }
        .focusable()
        .focused($isFocused)
        .background(FocusableOverlay())
        .onAppear {
            // Hide sidebar by default, focus immediately for keyboard control
            showChapterList = false
            // 延迟获取焦点，确保视图已完全加载
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFocused = true
                // 让应用成为活跃应用
                NSApplication.shared.activate(ignoringOtherApps: true)
                // 让主窗口成为键盘窗口
                if let window = NSApplication.shared.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
        .onDisappear {
            NSCursor.setHiddenUntilMouseMoves(false)
        }
    }

    // MARK: - Chapter Sidebar

    private var chapterSidebar: some View {
        VStack(spacing: 0) {
            // Sidebar header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("目　录")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                        .kerning(2)
                    if bookManager.chapters.isEmpty && bookManager.isLoading {
                        Text("加载中...")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    } else {
                        Text("共 \(bookManager.chapters.count) 章")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Divider()
                .overlay(AppTheme.border)

            if bookManager.chapters.isEmpty && bookManager.isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("正在获取目录...")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textTertiary)
                    Spacer()
                }
            } else {
                // Chapter list
                ScrollViewReader { proxy in
                    List(selection: Binding(
                        get: { bookManager.currentChapterIndex },
                        set: { if let idx = $0 { bookManager.loadChapter(idx) } }
                    )) {
                        ForEach(bookManager.chapters) { chapter in
                            HStack(spacing: 10) {
                                if chapter.index == bookManager.currentChapterIndex {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(AppTheme.accent)
                                        .frame(width: 3, height: 18)
                                } else {
                                    Color.clear
                                        .frame(width: 3, height: 18)
                                }
                                Text(chapter.title)
                                    .font(.system(size: 13, weight: chapter.index == bookManager.currentChapterIndex ? .medium : .regular))
                                    .foregroundColor(
                                        chapter.index == bookManager.currentChapterIndex
                                            ? AppTheme.accent
                                            : AppTheme.textSecondary
                                    )
                                    .lineLimit(2)
                                Spacer()
                            }
                            .tag(chapter.index)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .listRowBackground(
                                chapter.index == bookManager.currentChapterIndex
                                    ? RoundedRectangle(cornerRadius: 8)
                                        .fill(AppTheme.accent.opacity(0.08))
                                    : nil
                            )
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .onAppear {
                        proxy.scrollTo(bookManager.currentChapterIndex, anchor: .center)
                    }
                    .onChange(of: bookManager.currentChapterIndex) { _, newValue in
                        withAnimation {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(AppTheme.bgSecondary)
    }

    // MARK: - Toolbar

    private var readerToolbar: some View {
        HStack(spacing: 0) {
            // Left section
            HStack(spacing: 12) {
                // Back button
                Button(action: {
                    withAnimation(.spring(duration: 0.3)) {
                        bookManager.closeBook()
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                        Text("返回")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(config.theme.textColor.opacity(0.6))
                }
                .buttonStyle(.plain)
                
                // Separator
                Rectangle()
                    .fill(config.theme.textColor.opacity(0.1))
                    .frame(width: 1, height: 16)
                
                // Chapter list toggle
                Button(action: { showChapterList.toggle() }) {
                    Image(systemName: showChapterList ? "sidebar.left" : "sidebar.leading")
                        .font(.system(size: 14))
                        .foregroundColor(showChapterList ? AppTheme.accent : config.theme.textColor.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("切换目录 (⌘L)")
            }
            
            Spacer()
            
            // Center section - Book info
            if let book = bookManager.currentBook {
                VStack(spacing: 2) {
                    Text(book.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(config.theme.textColor.opacity(0.7))
                    if bookManager.currentChapterIndex < bookManager.chapters.count {
                        Text(bookManager.chapters[bookManager.currentChapterIndex].title)
                            .font(.system(size: 11))
                            .foregroundColor(config.theme.textColor.opacity(0.4))
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Right section
            HStack(spacing: 12) {
                // Bookmark button
                Button(action: { 
                    withAnimation(.easeIn(duration: 0.2)) {
                        showBookmarks.toggle() 
                    }
                }) {
                    Image(systemName: showBookmarks ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14))
                        .foregroundColor(showBookmarks ? AppTheme.accent : config.theme.textColor.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("书签 (⌘B)")
                
                // Separator
                Rectangle()
                    .fill(config.theme.textColor.opacity(0.1))
                    .frame(width: 1, height: 16)
                
                // Fullscreen button
                Button(action: { isFullscreen.toggle() }) {
                    Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13))
                        .foregroundColor(config.theme.textColor.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("全屏 (⌘F)")
                
                // Separator
                Rectangle()
                    .fill(config.theme.textColor.opacity(0.1))
                    .frame(width: 1, height: 16)
                
                // Settings button
                Button(action: { showSettings.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14))
                        Text("设置")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(config.theme.textColor.opacity(0.5))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSettings) {
                    readerSettingsPopover
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            config.theme.bgColor
                .overlay(
                    Rectangle()
                        .fill(config.theme.textColor.opacity(0.05))
                        .frame(height: 1),
                    alignment: .bottom
                )
        )
    }

    // MARK: - Content

    private var readerContent: some View {
        ZStack {
            // AppKit 文本视图 - 支持右键菜单
            ReaderTextViewWrapper(
                content: bookManager.currentContent,
                chapterTitle: bookManager.currentChapterIndex < bookManager.chapters.count 
                    ? bookManager.chapters[bookManager.currentChapterIndex].title : "",
                fontSize: config.fontSize,
                lineSpacing: config.lineSpacing,
                paragraphSpacing: config.paragraphSpacing,
                fontFamily: config.fontFamily.fontName,
                textColor: config.theme.textColor,
                bgColor: config.theme.bgColor,
                firstLineIndent: config.firstLineIndent,
                letterSpacing: config.letterSpacing,
                onAddNote: { selectedText in
                    // 设置对话框要显示的文本快照
                    noteDialogText = selectedText
                    selectedParagraphText = selectedText
                    noteText = ""
                    showNoteDialog = true
                },
                onScrollPositionChange: { atTop, atBottom in
                    isAtTop = atTop
                    isAtBottom = atBottom
                },
                onAtTop: {
                    // 不自动切换章节，由用户手动操作
                },
                onAtBottom: {
                    // 不自动切换章节，由用户手动操作
                }
            )
            .id("reader-\(bookManager.currentChapterIndex)")

            // Loading overlay
            if bookManager.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(AppTheme.accent)
                    if let msg = bookManager.loadingMessage {
                        Text(msg)
                            .font(.system(size: 13))
                            .foregroundColor(config.theme.textColor.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(config.theme.bgColor.opacity(0.9))
            }
            
            // Bookmarks panel overlay
            if showBookmarks {
                bookmarksPanel
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .addBookmark)) { _ in
            addBookmarkAtCurrentPosition()
        }
        .onReceive(NotificationCenter.default.publisher(for: .previousChapter)) { _ in
            _ = bookManager.previousChapter()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextChapter)) { _ in
            _ = bookManager.nextChapter()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleFullscreen)) { _ in
            isFullscreen.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleChapterList)) { _ in
            showChapterList.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeReader)) { _ in
            bookManager.closeBook()
        }
        .sheet(isPresented: $showNoteDialog) {
            // 判断是否是暗色主题（暗黑/夜间）
            let isDarkTheme = config.theme == .dark || config.theme == .night
            // 暗色主题用白色文字，其他用黑色
            let textColor: Color = isDarkTheme ? .white : .black
            
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("添加笔记")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(textColor)
                    Spacer()
                    Button(action: { 
                        noteText = ""
                        noteDialogText = ""
                        selectedParagraphText = ""
                        showNoteDialog = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(isDarkTheme ? .white.opacity(0.6) : .black.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                
                // 原文预览 - 始终显示
                VStack(alignment: .leading, spacing: 4) {
                    Text("原文:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isDarkTheme ? .white.opacity(0.7) : .black.opacity(0.6))
                    Text(noteDialogText.isEmpty ? "（未选中文本）" : noteDialogText)
                        .font(.system(size: 14))
                        .foregroundColor(textColor.opacity(noteDialogText.isEmpty ? 0.5 : 1))
                        .lineLimit(3)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isDarkTheme ? Color.white.opacity(0.1) : Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                
                // 多行输入框
                VStack(alignment: .leading, spacing: 4) {
                    Text("笔记:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isDarkTheme ? .white.opacity(0.7) : .black.opacity(0.6))
                    ZStack(alignment: .topLeading) {
                        if noteText.isEmpty {
                            Text("输入阅读心得...")
                                .font(.system(size: 14))
                                .foregroundColor(isDarkTheme ? .white.opacity(0.4) : .gray.opacity(0.5))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 14)
                        }
                        TextEditor(text: $noteText)
                            .font(.system(size: 14))
                            .foregroundColor(textColor)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                    }
                    .frame(minHeight: 150)
                    .padding(8)
                    .background(isDarkTheme ? Color.white.opacity(0.1) : Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Buttons
                HStack {
                    Spacer()
                    Button(action: { 
                        noteText = ""
                        noteDialogText = ""
                        selectedParagraphText = ""
                        showNoteDialog = false
                    }) {
                        Text("取消")
                            .foregroundColor(textColor)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(textColor.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        if !noteText.isEmpty || !noteDialogText.isEmpty {
                            let preview = String(noteDialogText.prefix(100))
                            bookManager.addBookmark(
                                chapterIndex: bookManager.currentChapterIndex,
                                chapterTitle: bookManager.chapters[safe: bookManager.currentChapterIndex]?.title ?? "",
                                scrollOffset: currentScrollOffset,
                                previewText: preview,
                                note: noteText.isEmpty ? nil : noteText
                            )
                        }
                        noteText = ""
                        noteDialogText = ""
                        selectedParagraphText = ""
                        showNoteDialog = false
                    }) {
                        Text("保存")
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(AppTheme.accent)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(width: 450, height: 400)
            .background(config.theme.bgColor)
        }
        .sheet(isPresented: $showNotes) {
            // 判断是否是暗色主题
            let isDarkTheme = config.theme == .dark || config.theme == .night
            let textColor: Color = isDarkTheme ? .white : .black
            
            // 获取当前书籍的笔记（带 note 的书签）
            let allBookmarks = bookManager.bookmarksForCurrentBook()
            let notes = allBookmarks.filter { $0.note != nil && !$0.note!.isEmpty }
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("笔记列表")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(textColor)
                    Spacer()
                    
                    // 导出笔记按钮
                    if !notes.isEmpty {
                        Button(action: {
                            exportNotes()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 12))
                                Text("导出")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(AppTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button(action: { 
                        showNotes = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(isDarkTheme ? .white.opacity(0.6) : .black.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                
                Divider()
                
                if notes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "note.text")
                            .font(.system(size: 40))
                            .foregroundColor(textColor.opacity(0.3))
                        Text("暂无笔记")
                            .font(.system(size: 14))
                            .foregroundColor(textColor.opacity(0.5))
                        Text("在阅读时选中文本右键添加笔记")
                            .font(.system(size: 12))
                            .foregroundColor(textColor.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(notes) { bookmark in
                                VStack(alignment: .leading, spacing: 8) {
                                    // 章节标题
                                    HStack {
                                        Image(systemName: "book.closed")
                                            .font(.system(size: 10))
                                        Text(bookmark.chapterTitle)
                                            .font(.system(size: 11, weight: .medium))
                                        Spacer()
                                        // 复制按钮
                                        Button(action: {
                                            copyNoteToClipboard(bookmark: bookmark)
                                        }) {
                                            Image(systemName: "doc.on.doc")
                                                .font(.system(size: 11))
                                                .foregroundColor(textColor.opacity(0.4))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .foregroundColor(AppTheme.accent)
                                    
                                    // 原文预览
                                    if !bookmark.previewText.isEmpty {
                                        Text(bookmark.previewText)
                                            .font(.system(size: 12))
                                            .foregroundColor(textColor.opacity(0.7))
                                            .lineLimit(2)
                                    }
                                    
                                    // 笔记内容
                                    if let note = bookmark.note {
                                        Text(note)
                                            .font(.system(size: 13))
                                            .foregroundColor(textColor)
                                            .padding(10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(isDarkTheme ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                            )
                                    }
                                    
                                    // 时间
                                    Text(formatBookmarkTime(bookmark.createTime))
                                        .font(.system(size: 10))
                                        .foregroundColor(textColor.opacity(0.4))
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isDarkTheme ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                                )
                                .onTapGesture {
                                    // 点击跳转到对应章节
                                    bookManager.jumpToBookmark(bookmark)
                                    showNotes = false
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .frame(width: 500, height: 450)
            .background(config.theme.bgColor)
        }
    }
    
    // MARK: - Bookmarks Panel
    
    private var bookmarksPanel: some View {
        let bookBookmarks = bookManager.bookmarksForCurrentBook()
        
        return ZStack {
            // Background overlay
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showBookmarks = false
                    }
                }
            
            // Panel
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("书签")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(config.theme.textColor)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showBookmarks = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(config.theme.textColor.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                
                Divider()
                    .background(config.theme.textColor.opacity(0.1))
                
                if bookBookmarks.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "bookmark.slash")
                            .font(.system(size: 40))
                            .foregroundColor(config.theme.textColor.opacity(0.3))
                        Text("暂无书签")
                            .font(.system(size: 14))
                            .foregroundColor(config.theme.textColor.opacity(0.5))
                        Text("按 ⌘B 添加书签")
                            .font(.system(size: 12))
                            .foregroundColor(config.theme.textColor.opacity(0.4))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(bookBookmarks) { bookmark in
                                bookmarkRow(bookmark)
                                if bookmark.id != bookBookmarks.last?.id {
                                    Divider()
                                        .background(config.theme.textColor.opacity(0.1))
                                }
                            }
                        }
                    }
                }
                
                // Add bookmark button
                HStack {
                    Button(action: {
                        addBookmarkAtCurrentPosition()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("添加当前位置")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .frame(width: 320)
            .frame(maxHeight: 450)
            .background(config.theme.bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.black.opacity(0.2), radius: 20)
            .padding()
        }
    }
    
    private func bookmarkRow(_ bookmark: Bookmark) -> some View {
        Button(action: {
            bookManager.jumpToBookmark(bookmark)
            withAnimation(.easeOut(duration: 0.2)) {
                showBookmarks = false
            }
        }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("第 \(bookmark.chapterIndex + 1) 章")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                    
                    Spacer()
                    
                    Text(formatBookmarkTime(bookmark.createTime))
                        .font(.system(size: 10))
                        .foregroundColor(config.theme.textColor.opacity(0.4))
                    
                    Button(action: {
                        bookManager.removeBookmark(bookmark)
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                
                Text(bookmark.chapterTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(config.theme.textColor)
                    .lineLimit(1)
                
                if !bookmark.previewText.isEmpty {
                    Text(bookmark.previewText)
                        .font(.system(size: 11))
                        .foregroundColor(config.theme.textColor.opacity(0.6))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(bookmark.chapterIndex == bookManager.currentChapterIndex ? 
                      AppTheme.accent.opacity(0.08) : Color.clear)
        )
    }
    
    private func formatBookmarkTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "今天 HH:mm"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "昨天 HH:mm"
        } else {
            formatter.dateFormat = "MM-dd HH:mm"
        }
        return formatter.string(from: date)
    }
    
    private func exportNotes() {
        guard let book = bookManager.currentBook else { return }
        
        let markdown = bookManager.exportNotesToMarkdown(for: book)
        guard !markdown.isEmpty else { return }
        
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(book.name)_笔记.md"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.title = "导出笔记"
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("导出失败: \(error)")
            }
        }
    }
    
    private func copyNoteToClipboard(bookmark: Bookmark) {
        var text = ""
        
        // 添加章节名称
        if !bookmark.chapterTitle.isEmpty {
            text += "【\(bookmark.chapterTitle)】\n\n"
        }
        
        // 添加原文
        if !bookmark.previewText.isEmpty {
            text += "原文: \(bookmark.previewText)\n\n"
        }
        
        // 添加笔记
        if let note = bookmark.note, !note.isEmpty {
            text += "笔记: \(note)"
        }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    private func addBookmarkAtCurrentPosition() {
        guard let chapter = bookManager.chapters[safe: bookManager.currentChapterIndex] else { return }
        
        // Get preview text from current content
        let previewText = String(bookManager.currentContent
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(100))
        
        bookManager.addBookmark(
            chapterIndex: bookManager.currentChapterIndex,
            chapterTitle: chapter.title,
            scrollOffset: currentScrollOffset,
            previewText: previewText
        )
    }

    // MARK: - Bottom Bar

    private var readerBottomBar: some View {
        HStack(spacing: 0) {
            // Previous chapter button
            Button(action: { _ = bookManager.previousChapter() }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text("上一章")
                        .font(.system(size: 12))
                }
                .foregroundColor(
                    bookManager.currentChapterIndex > 0
                        ? config.theme.textColor.opacity(0.5)
                        : config.theme.textColor.opacity(0.15)
                )
            }
            .buttonStyle(.plain)
            .disabled(bookManager.currentChapterIndex <= 0)
            .help("上一章 (←)")
            
            Spacer()
            
            // Progress section
            VStack(spacing: 6) {
                // Progress bar
                GeometryReader { geom in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(config.theme.textColor.opacity(0.08))
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(AppTheme.accent.opacity(0.6))
                            .frame(width: bookManager.chapters.isEmpty ? 0 :
                                geom.size.width * CGFloat(bookManager.currentChapterIndex + 1) / CGFloat(max(bookManager.chapters.count, 1)))
                    }
                }
                .frame(width: 140, height: 3)
                
                // Chapter progress text
                Text("第 \(bookManager.currentChapterIndex + 1) 章 / 共 \(bookManager.chapters.count) 章")
                    .font(.system(size: 11))
                    .foregroundColor(config.theme.textColor.opacity(0.35))
            }
            
            Spacer()
            
            // 查看笔记按钮
            Button(action: {
                showNotes = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "note.text")
                        .font(.system(size: 12))
                    Text("查看笔记")
                        .font(.system(size: 11))
                }
                .foregroundColor(config.theme.textColor.opacity(0.4))
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Next chapter button
            Button(action: { _ = bookManager.nextChapter() }) {
                HStack(spacing: 6) {
                    Text("下一章")
                        .font(.system(size: 12))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(
                    bookManager.currentChapterIndex < bookManager.chapters.count - 1
                        ? config.theme.textColor.opacity(0.5)
                        : config.theme.textColor.opacity(0.15)
                )
            }
            .buttonStyle(.plain)
            .disabled(bookManager.currentChapterIndex >= bookManager.chapters.count - 1)
            .help("下一章 (→)")
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(
            config.theme.bgColor
                .overlay(
                    Rectangle()
                        .fill(config.theme.textColor.opacity(0.05))
                        .frame(height: 1),
                    alignment: .top
                )
        )
    }

    // MARK: - Settings Popover

    private var readerSettingsPopover: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("阅读设置")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                }
                
                // ========== 字体设置 ==========
                settingsSection(title: "字体") {
                    // 字体大小 - 带快捷按钮
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("字号")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            // 快捷调整按钮
                            HStack(spacing: 8) {
                                Button(action: { 
                                    if config.fontSize > 12 { config.fontSize -= 2; config.save() }
                                }) {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                
                                Text("\(Int(config.fontSize))")
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .frame(minWidth: 30)
                                
                                Button(action: { 
                                    if config.fontSize < 36 { config.fontSize += 2; config.save() }
                                }) {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Slider(value: Bindable(config).fontSize, in: 12...36, step: 1)
                            .tint(AppTheme.accent)
                    }
                    
                    // 字体选择
                    VStack(alignment: .leading, spacing: 8) {
                        Text("字体风格")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            ForEach(FontFamily.allCases) { family in
                                Button(action: {
                                    config.fontFamily = family
                                    config.save()
                                }) {
                                    Text(family.displayName)
                                        .font(.custom(family.fontName, size: 12))
                                        .foregroundColor(config.fontFamily == family ? .white : .primary)
                                        .frame(minWidth: 50)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(config.fontFamily == family ? AppTheme.accent : Color.gray.opacity(0.15))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                
                // ========== 排版设置 ==========
                settingsSection(title: "排版") {
                    // 行距
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("行距")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(config.lineSpacing))")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        Slider(value: Bindable(config).lineSpacing, in: 2...24, step: 1)
                            .tint(AppTheme.accent)
                    }
                    
                    // 段间距
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("段距")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(config.paragraphSpacing))")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        Slider(value: Bindable(config).paragraphSpacing, in: 4...32, step: 2)
                            .tint(AppTheme.accent)
                    }
                    
                    // 页边距
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("边距")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(config.margins))")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        Slider(value: Bindable(config).margins, in: 20...120, step: 5)
                            .tint(AppTheme.accent)
                    }
                    
                    // 首行缩进开关
                    HStack {
                        Text("首行缩进")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                        Toggle("", isOn: Bindable(config).firstLineIndent)
                            .labelsHidden()
                            .tint(AppTheme.accent)
                    }
                }
                
                // ========== 主题设置 ==========
                settingsSection(title: "主题") {
                    // 主题选择 - 网格布局
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(ReadingTheme.allCases) { theme in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) { 
                                    config.theme = theme 
                                }
                                config.save()
                            }) {
                                VStack(spacing: 6) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(theme.bgColor)
                                            .frame(width: 52, height: 40)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(
                                                        config.theme == theme ? AppTheme.accent : Color.gray.opacity(0.2),
                                                        lineWidth: config.theme == theme ? 2 : 1
                                                    )
                                            )
                                        Text("文")
                                            .font(.system(size: 14, weight: .medium, design: .serif))
                                            .foregroundColor(theme.textColor)
                                    }
                                    Text(theme.displayName)
                                        .font(.system(size: 10))
                                        .foregroundColor(config.theme == theme ? AppTheme.accent : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // ========== 快捷键 ==========
                settingsSection(title: "快捷键") {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        shortcutChip("← →", description: "章节切换")
                        shortcutChip("↑ ↓", description: "翻页")
                        shortcutChip("Space", description: "下翻页")
                        shortcutChip("⌘L", description: "目录")
                        shortcutChip("⌘F", description: "全屏")
                        shortcutChip("Esc", description: "退出")
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 400, height: 580)
        .onChange(of: config.fontSize) { _, _ in config.save() }
        .onChange(of: config.lineSpacing) { _, _ in config.save() }
        .onChange(of: config.paragraphSpacing) { _, _ in config.save() }
        .onChange(of: config.margins) { _, _ in config.save() }
        .onChange(of: config.fontFamily) { _, _ in config.save() }
        .onChange(of: config.firstLineIndent) { _, _ in config.save() }
    }
    
    // 设置区块
    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(1)
            
            content()
        }
    }

    // MARK: - Helpers

    private func shortcutChip(_ key: String, description: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(description)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Array Safe Subscript Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
