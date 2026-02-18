import SwiftUI

public struct ContentView: View {
    @Environment(BookManager.self) private var bookManager
    @State private var selectedTab: SidebarTab = .bookshelf
    @State private var showFileImporter = false

    public init() {}


    enum SidebarTab: String, CaseIterable, Hashable {
        case bookshelf = "书架"
        case search = "搜索"
        case sources = "书源"
        case settings = "设置"

        var icon: String {
            switch self {
            case .bookshelf: return "books.vertical.fill"
            case .search: return "magnifyingglass"
            case .sources: return "text.book.closed.fill"
            case .settings: return "gearshape.fill"
            }
        }

        var shortcut: KeyEquivalent? {
            switch self {
            case .bookshelf: return "1"
            case .search: return "2"
            case .sources: return "3"
            case .settings: return "4"
            }
        }
    }

    public var body: some View {
        Group {
            if bookManager.isReading {
                ReaderView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            } else {
                NavigationSplitView {
                    sidebarContent
                } detail: {
                    detailContent
                }
                .navigationSplitViewStyle(.balanced)
                .transition(.opacity)
            }
        }
        .navigationTitle("开源阅读")
        .animation(.spring(duration: 0.4), value: bookManager.isReading)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.plainText, .epub],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    try? bookManager.addLocalBook(url: url)
                }
            }
        }
        .background {
            Button("") { showFileImporter = true }
                .keyboardShortcut("o", modifiers: .command)
                .hidden()
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // App Header - 仅保留图标
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [AppTheme.accent.opacity(0.2), AppTheme.accentPurple.opacity(0.15)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(
                            LinearGradient(colors: [AppTheme.accent, AppTheme.accentPurple],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }
            }
            .padding(.vertical, 20)

            // Divider with gradient
            Rectangle()
                .fill(
                    LinearGradient(colors: [AppTheme.border.opacity(0), AppTheme.border, AppTheme.border.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .frame(height: 1)

            // Navigation Items
            List(selection: $selectedTab) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Label {
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: .medium))
                    } icon: {
                        Image(systemName: tab.icon)
                            .foregroundColor(selectedTab == tab ? AppTheme.accent : AppTheme.textSecondary)
                    }
                    .tag(tab)
                    .listRowBackground(
                        selectedTab == tab
                            ? RoundedRectangle(cornerRadius: 8)
                                .fill(AppTheme.accent.opacity(0.12))
                                .padding(.horizontal, 4)
                            : nil
                    )
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Spacer()

            // Quick actions
            HStack(spacing: 12) {
                Button(action: { showFileImporter = true }) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("打开文件 (⌘O)")
            }
            .padding(.bottom, 8)

            // Version Footer
            Text("v1.0.0")
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textTertiary)
                .padding(.bottom, 12)
        }
        .background(AppTheme.bgSecondary)
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .bookshelf:
            BookshelfView()
        case .search:
            SearchView()
        case .sources:
            BookSourceListView()
        case .settings:
            SettingsView()
        }
    }
}
