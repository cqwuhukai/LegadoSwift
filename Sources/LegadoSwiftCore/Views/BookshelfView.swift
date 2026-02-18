import SwiftUI
import UniformTypeIdentifiers

struct BookshelfView: View {
    @Environment(BookManager.self) private var bookManager
    @State private var showFileImporter = false
    @State private var hoveringBookId: String?
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .lastRead
    @State private var showDeleteAlert = false
    @State private var bookToDelete: Book?

    enum SortOrder: String, CaseIterable {
        case lastRead = "最近阅读"
        case name = "书名"
        case addTime = "添加时间"
    }

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                if sortedBooks.isEmpty {
                    if bookManager.books.isEmpty {
                        emptyState
                    } else {
                        noResultState
                    }
                } else {
                    booksGrid
                }
            }
            .padding(30)
        }
        .background(AppTheme.bgPrimary)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.plainText, .epub],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .alert("确认删除", isPresented: $showDeleteAlert, presenting: bookToDelete) { book in
            Button("删除", role: .destructive) { bookManager.removeBook(book) }
            Button("取消", role: .cancel) { }
        } message: { book in
            Text("确定要删除《\(book.name)》吗？此操作不可撤销。")
        }
    }

    // MARK: - Sorted & Filtered Books

    private var sortedBooks: [Book] {
        var books = bookManager.books
        if !searchText.isEmpty {
            books = books.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.author.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sortOrder {
        case .lastRead:
            return books.sorted {
                ($0.lastReadTime ?? .distantPast) > ($1.lastReadTime ?? .distantPast)
            }
        case .name:
            return books.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .addTime:
            return books.sorted { $0.addTime > $1.addTime }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("我的书架")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("\(bookManager.books.count) 本书")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                }
                Spacer()
                Button(action: { showFileImporter = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("打开文件")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(colors: [AppTheme.accent, AppTheme.accentPurple],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // Search & Sort Bar
            if !bookManager.books.isEmpty {
                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(AppTheme.textTertiary)
                        TextField("搜索书架...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                    }
                    .padding(8)
                    .background(AppTheme.bgTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Picker("排序", selection: $sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .frame(width: 120)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 60)

            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.08))
                    .frame(width: 120, height: 120)
                Circle()
                    .fill(AppTheme.accent.opacity(0.05))
                    .frame(width: 160, height: 160)
                Image(systemName: "book.closed")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(colors: [AppTheme.accent, AppTheme.accentPurple],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }

            VStack(spacing: 8) {
                Text("书架空空如也")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                Text("点击「打开文件」或拖放 TXT/EPUB 文件到此处")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textTertiary)
            }

            Button(action: { showFileImporter = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.badge.plus")
                    Text("打开文件")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(colors: [AppTheme.accent, AppTheme.accentPurple],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
    }

    private var noResultState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 40)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(AppTheme.textTertiary)
            Text("未找到匹配的书籍")
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textSecondary)
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Books Grid

    private var booksGrid: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(sortedBooks) { book in
                BookCard(book: book, isHovering: hoveringBookId == book.id)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            hoveringBookId = hovering ? book.id : nil
                        }
                    }
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.3)) {
                            bookManager.openBook(book)
                        }
                    }
                    .contextMenu {
                        Button("打开", systemImage: "book.fill") {
                            bookManager.openBook(book)
                        }
                        Divider()
                        if !bookManager.bookmarksForBook(book).isEmpty {
                            Button("导出笔记", systemImage: "note.text") {
                                exportNotes(for: book)
                            }
                            Divider()
                        }
                        Button("删除", systemImage: "trash", role: .destructive) {
                            bookToDelete = book
                            showDeleteAlert = true
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(duration: 0.4), value: sortedBooks.map(\.id))
    }

    // MARK: - File Import Handler

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            try? bookManager.addLocalBook(url: url)
        }
    }

    // MARK: - Drag & Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                let ext = url.pathExtension.lowercased()
                guard ext == "txt" || ext == "epub" else { return }
                DispatchQueue.main.async {
                    try? bookManager.addLocalBook(url: url)
                }
            }
        }
        return true
    }
    
    private func exportNotes(for book: Book) {
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
}

// MARK: - Book Card Component

struct BookCard: View {
    let book: Book
    let isHovering: Bool

    private var bookTypeIcon: String {
        switch book.bookType {
        case .online: return "globe"
        case .epub: return "doc.richtext"
        default: return "doc.text"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover
            ZStack(alignment: .bottomTrailing) {
                AppTheme.cardGradient(for: book.name)
                    .frame(height: 200)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: bookTypeIcon)
                                .font(.system(size: 32))
                                .foregroundColor(.white.opacity(0.2))
                            Text(String(book.name.prefix(1)))
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    )

                // Progress / Source badge
                if book.totalChapters > 0 {
                    Text(book.progressText)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            LinearGradient(colors: [AppTheme.accent, AppTheme.accentPurple],
                                           startPoint: .leading, endPoint: .trailing)
                                .opacity(0.9)
                        )
                        .clipShape(Capsule())
                        .padding(8)
                } else if book.isOnlineBook {
                    Text(book.originName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppTheme.accentPurple.opacity(0.8))
                        .clipShape(Capsule())
                        .padding(8)
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(book.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(2)

                Text(book.author.isEmpty ? (book.isOnlineBook ? book.originName : book.bookType.rawValue.uppercased()) : book.author)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(1)

                if let lastRead = book.lastReadTime {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 8))
                        Text(lastRead, style: .relative)
                            .font(.system(size: 10))
                    }
                    .foregroundColor(AppTheme.textTertiary)
                }
            }
            .padding(12)
        }
        .background(AppTheme.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isHovering
                        ? LinearGradient(colors: [AppTheme.accent.opacity(0.6), AppTheme.accentPurple.opacity(0.4)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [AppTheme.border], startPoint: .top, endPoint: .bottom),
                    lineWidth: isHovering ? 1.5 : 0.5
                )
        )
        .shadow(color: isHovering ? AppTheme.accent.opacity(0.15) : .clear, radius: 16, y: 4)
        .scaleEffect(isHovering ? 1.03 : 1.0)
    }
}

// MARK: - UTType Extensions

extension UTType {
    static let epub = UTType(filenameExtension: "epub") ?? .data
}
