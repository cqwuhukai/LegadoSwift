import SwiftUI

struct SearchView: View {
    @Environment(BookSourceManager.self) private var sourceManager
    @Environment(BookManager.self) private var bookManager
    @State private var searchKey = ""
    @State private var searchEngine = BookSearchEngine()
    @State private var selectedSource: BookSource?
    @State private var showErrors = false
    @State private var selectedBook: SearchBook?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                HStack {
                    Text("搜索")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Spacer()
                    if searchEngine.isSearching {
                        Button("取消") {
                            searchEngine.cancel()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                // Search Bar
                HStack(spacing: 10) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(AppTheme.textTertiary)
                        TextField("输入书名或作者...", text: $searchKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .onSubmit { performSearch() }
                    }
                    .padding(10)
                    .background(AppTheme.bgTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button(action: performSearch) {
                        HStack(spacing: 6) {
                            if searchEngine.isSearching {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.8)
                            }
                            Text("搜索")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(colors: [AppTheme.accent, AppTheme.accentPurple],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(searchKey.isEmpty || searchEngine.isSearching)
                }

                // Source filter
                if !sourceManager.enabledSources.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(title: "全部", isSelected: selectedSource == nil) {
                                selectedSource = nil
                            }
                            ForEach(sourceManager.enabledSources.prefix(10)) { source in
                                FilterChip(
                                    title: source.bookSourceName,
                                    isSelected: selectedSource?.bookSourceUrl == source.bookSourceUrl
                                ) {
                                    selectedSource = source
                                }
                            }
                        }
                    }
                }

                // Progress & Errors
                if !searchEngine.searchProgress.isEmpty || !searchEngine.searchErrors.isEmpty {
                    HStack {
                        Text(searchEngine.searchProgress)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textTertiary)
                        Spacer()
                        if !searchEngine.searchErrors.isEmpty {
                            Button {
                                showErrors.toggle()
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 9))
                                    Text("\(searchEngine.searchErrors.count)个错误")
                                        .font(.system(size: 10))
                                }
                                .foregroundColor(AppTheme.accentOrange)
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showErrors) {
                                errorPopover
                            }
                        }
                    }
                }
            }
            .padding(20)

            Divider().overlay(AppTheme.border)

            // Results
            if searchEngine.isSearching && searchEngine.results.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("正在搜索多个书源...")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                }
                Spacer()
            } else if searchEngine.results.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(colors: [AppTheme.textTertiary, AppTheme.textTertiary.opacity(0.3)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                    Text(searchKey.isEmpty ? "输入关键词开始搜索" : "未找到相关书籍")
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.textSecondary)
                    if sourceManager.enabledSources.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppTheme.accentOrange)
                            Text("请先在「书源」页面导入并启用书源")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.accentOrange)
                        }
                        .padding(.top, 4)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredResults) { book in
                            searchResultRow(book)
                            Divider().overlay(AppTheme.border.opacity(0.5))
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppTheme.bgPrimary)
        .sheet(item: $selectedBook) { book in
            BookDetailSheet(book: book, bookManager: bookManager)
        }
        .overlay(alignment: .bottom) {
            toastOverlay
        }
    }

    // MARK: - Error Popover

    private var errorPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("搜索错误")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(searchEngine.searchErrors, id: \.self) { error in
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding(12)
        .frame(width: 320)
        .background(AppTheme.bgSecondary)
    }

    // MARK: - Toast Overlay

    @ViewBuilder
    private var toastOverlay: some View {
        if let message = bookManager.toastMessage {
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(AppTheme.accentGreen.opacity(0.9))
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                )
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: bookManager.toastMessage)
        }
    }

    // MARK: - Filtered Results

    private var filteredResults: [SearchBook] {
        if let source = selectedSource {
            return searchEngine.results.filter { $0.bookSourceUrl == source.bookSourceUrl }
        }
        return searchEngine.results
    }

    // MARK: - Result Row

    private func searchResultRow(_ book: SearchBook) -> some View {
        HStack(spacing: 14) {
            // Cover placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.cardGradient(for: book.name))
                .frame(width: 50, height: 66)
                .overlay(
                    Text(String(book.name.prefix(1)))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(book.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)

                if !book.author.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 9))
                        Text(book.author)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(1)
                }

                if let intro = book.intro, !intro.isEmpty {
                    Text(intro)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                        .lineLimit(2)
                }

                if let latest = book.latestChapterTitle, !latest.isEmpty {
                    Text("最新: \(latest)")
                        .font(.system(size: 10))
                        .foregroundColor(AppTheme.accentGreen)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text(book.originName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.accent.opacity(0.12))
                    .clipShape(Capsule())

                if let kind = book.kind, !kind.isEmpty {
                    Text(kind)
                        .font(.system(size: 9))
                        .foregroundColor(AppTheme.textTertiary)
                        .lineLimit(1)
                }

                // Add to bookshelf button
                addToShelfButton(book)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedBook = book
        }
        .background(Color.clear)
    }

    // MARK: - Add to Shelf Button

    @ViewBuilder
    private func addToShelfButton(_ book: SearchBook) -> some View {
        let inShelf = bookManager.isBookInShelf(book.bookUrl)

        Button {
            if !inShelf {
                withAnimation(.spring(duration: 0.3)) {
                    _ = bookManager.addSearchBook(book)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: inShelf ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 11))
                Text(inShelf ? "已加入" : "加入书架")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(inShelf ? AppTheme.accentGreen : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                inShelf
                    ? AnyShapeStyle(AppTheme.accentGreen.opacity(0.15))
                    : AnyShapeStyle(LinearGradient(
                        colors: [AppTheme.accent, AppTheme.accentPurple],
                        startPoint: .leading, endPoint: .trailing
                    ))
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(inShelf)
    }

    // MARK: - Actions

    private func performSearch() {
        let sources: [BookSource]
        if let source = selectedSource {
            sources = [source]
        } else {
            sources = sourceManager.enabledSources
        }

        Task {
            await searchEngine.search(keyword: searchKey, sources: sources)
        }
    }
}

// MARK: - Book Detail Sheet

struct BookDetailSheet: View {
    let book: SearchBook
    let bookManager: BookManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("书籍详情")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider().overlay(AppTheme.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Book info header
                    HStack(alignment: .top, spacing: 16) {
                        // Cover
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppTheme.cardGradient(for: book.name))
                            .frame(width: 90, height: 120)
                            .overlay(
                                VStack(spacing: 4) {
                                    Text(String(book.name.prefix(1)))
                                        .font(.system(size: 36, weight: .bold, design: .rounded))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                            )

                        VStack(alignment: .leading, spacing: 8) {
                            Text(book.name)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(AppTheme.textPrimary)

                            if !book.author.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 11))
                                    Text(book.author)
                                        .font(.system(size: 14))
                                }
                                .foregroundColor(AppTheme.textSecondary)
                            }

                            HStack(spacing: 6) {
                                Image(systemName: "globe")
                                    .font(.system(size: 11))
                                Text(book.originName)
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(AppTheme.accent)

                            if let kind = book.kind, !kind.isEmpty {
                                HStack(spacing: 6) {
                                    ForEach(kind.components(separatedBy: CharacterSet(charactersIn: ",，、;；")), id: \.self) { tag in
                                        let trimmed = tag.trimmingCharacters(in: .whitespaces)
                                        if !trimmed.isEmpty {
                                            Text(trimmed)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(AppTheme.textSecondary)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(AppTheme.bgTertiary)
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Latest chapter
                    if let latest = book.latestChapterTitle, !latest.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("最新章节")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppTheme.textSecondary)
                            Text(latest)
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.accentGreen)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.bgTertiary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Intro
                    if let intro = book.intro, !intro.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("简介")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppTheme.textSecondary)
                            Text(intro)
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.textPrimary)
                                .lineSpacing(4)
                        }
                    }
                }
                .padding(20)
            }

            Divider().overlay(AppTheme.border)

            // Action bar
            HStack(spacing: 12) {
                Spacer()

                let inShelf = bookManager.isBookInShelf(book.bookUrl)

                Button {
                    if !inShelf {
                        _ = bookManager.addSearchBook(book)
                    }
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: inShelf ? "checkmark.circle.fill" : "plus.circle.fill")
                        Text(inShelf ? "已在书架中" : "加入书架")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: inShelf
                                ? [AppTheme.accentGreen, AppTheme.accentGreen]
                                : [AppTheme.accent, AppTheme.accentPurple],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .frame(width: 480, height: 520)
        .background(AppTheme.bgPrimary)
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? .white : AppTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(isSelected ? AppTheme.accent : AppTheme.bgTertiary)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : AppTheme.border, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}
