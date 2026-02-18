import SwiftUI

struct BookSourceListView: View {
    @Environment(BookSourceManager.self) private var sourceManager
    @State private var showImportSheet = false
    @State private var importMode: ImportMode = .url
    @State private var importText = ""
    @State private var importResult: String?
    @State private var isImporting = false
    @State private var showFileImporter = false
    @State private var selection = Set<String>()
    @State private var showDeleteAlert = false
    @State private var hoveredSourceId: String?

    enum ImportMode: String, CaseIterable {
        case url = "URL"
        case json = "JSON"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().overlay(AppTheme.border)
            sourceList
        }
        .background(AppTheme.bgPrimary)
        .sheet(isPresented: $showImportSheet) {
            importSheet
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json]) { result in
            handleFileImport(result)
        }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("删除 \(selection.count) 个书源", role: .destructive) {
                sourceManager.removeSources(selection)
                selection.removeAll()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("确定要删除选中的 \(selection.count) 个书源吗？")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("书源管理")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("\(sourceManager.sources.count) 个书源 · \(sourceManager.enabledSources.count) 个启用")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.textSecondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    // Batch operations
                    if !selection.isEmpty {
                        Button(action: { showDeleteAlert = true }) {
                            Label("删除 (\(selection.count))", systemImage: "trash")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(AppTheme.accentRed)
                        }
                        .buttonStyle(.bordered)

                        Button("取消选择") {
                            selection.removeAll()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button(action: { showFileImporter = true }) {
                        Label("文件导入", systemImage: "doc.badge.plus")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)

                    Button(action: { showImportSheet = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("导入书源")
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
            }

            // Search & Filter
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AppTheme.textTertiary)
                    TextField("搜索书源...", text: Bindable(sourceManager).searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(8)
                .background(AppTheme.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if !sourceManager.groups.isEmpty {
                    Picker("分组", selection: Bindable(sourceManager).selectedGroup) {
                        Text("全部").tag(nil as String?)
                        ForEach(sourceManager.groups, id: \.self) { group in
                            Text(group).tag(group as String?)
                        }
                    }
                    .frame(width: 120)
                }

                // Quick actions
                if !sourceManager.sources.isEmpty {
                    Menu {
                        Button("全选") {
                            selection = Set(sourceManager.filteredSources.map { $0.bookSourceUrl })
                        }
                        Button("反选") {
                            let all = Set(sourceManager.filteredSources.map { $0.bookSourceUrl })
                            selection = all.symmetricDifference(selection)
                        }
                        Divider()
                        Button("全部启用") {
                            for source in sourceManager.filteredSources where !source.enabled {
                                sourceManager.toggleSource(source)
                            }
                        }
                        Button("全部禁用") {
                            for source in sourceManager.filteredSources where source.enabled {
                                sourceManager.toggleSource(source)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16))
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 30)
                }
            }
        }
        .padding(20)
    }

    // MARK: - Source List

    private var sourceList: some View {
        Group {
            if sourceManager.filteredSources.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(AppTheme.accent.opacity(0.08))
                            .frame(width: 100, height: 100)
                        Image(systemName: "text.book.closed")
                            .font(.system(size: 40))
                            .foregroundStyle(
                                LinearGradient(colors: [AppTheme.textTertiary, AppTheme.textTertiary.opacity(0.3)],
                                               startPoint: .top, endPoint: .bottom)
                            )
                    }
                    Text(sourceManager.sources.isEmpty ? "还没有书源" : "未找到匹配的书源")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                    if sourceManager.sources.isEmpty {
                        Text("点击「导入书源」从 URL 或 JSON 添加书源")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textTertiary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(sourceManager.filteredSources) { source in
                        sourceRow(source)
                            .tag(source.bookSourceUrl)
                    }
                    .onDelete { indexSet in
                        let filtered = sourceManager.filteredSources
                        for idx in indexSet {
                            sourceManager.removeSource(filtered[idx])
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func sourceRow(_ source: BookSource) -> some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(source.enabled ? AppTheme.accentGreen : AppTheme.textTertiary.opacity(0.5))
                .frame(width: 8, height: 8)
                .shadow(color: source.enabled ? AppTheme.accentGreen.opacity(0.4) : .clear, radius: 4)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(source.bookSourceName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(source.enabled ? AppTheme.textPrimary : AppTheme.textTertiary)

                    Text(source.sourceTypeDescription)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(AppTheme.accent.opacity(0.12))
                        .clipShape(Capsule())

                    if source.searchUrl != nil {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.accentGreen.opacity(0.7))
                    }
                    if source.exploreUrl != nil {
                        Image(systemName: "safari")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.accentOrange.opacity(0.7))
                    }
                }

                Text(source.bookSourceUrl)
                    .font(.system(size: 11))
                    .foregroundColor(AppTheme.textTertiary)
                    .lineLimit(1)

                if let groups = source.bookSourceGroup, !groups.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(groups.components(separatedBy: CharacterSet(charactersIn: ",;，；")).prefix(3), id: \.self) { group in
                            let g = group.trimmingCharacters(in: .whitespaces)
                            if !g.isEmpty {
                                Text(g)
                                    .font(.system(size: 9))
                                    .foregroundColor(AppTheme.textTertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(AppTheme.bgElevated)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { source.enabled },
                set: { _ in sourceManager.toggleSource(source) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Import Sheet

    private var importSheet: some View {
        VStack(spacing: 20) {
            HStack {
                Text("导入书源")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Button(action: { showImportSheet = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Picker("导入方式", selection: $importMode) {
                ForEach(ImportMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if importMode == .url {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("输入书源 URL...", text: $importText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                    Text("支持导入单个书源或书源列表的 JSON URL")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    TextEditor(text: $importText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                    Text("粘贴书源 JSON（支持单个或数组）")
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.textTertiary)
                }
            }

            if let result = importResult {
                HStack(spacing: 6) {
                    Image(systemName: result.contains("成功") ? "checkmark.circle.fill" : "xmark.circle.fill")
                    Text(result)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(result.contains("成功") ? AppTheme.accentGreen : AppTheme.accentRed)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    (result.contains("成功") ? AppTheme.accentGreen : AppTheme.accentRed)
                        .opacity(0.08)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button("取消") {
                    showImportSheet = false
                    importResult = nil
                    importText = ""
                }
                .keyboardShortcut(.cancelAction)

                Button(action: performImport) {
                    HStack(spacing: 4) {
                        if isImporting {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.8)
                        }
                        Text("导入")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(importText.isEmpty || isImporting)
            }
        }
        .padding(24)
        .frame(width: 520, height: importMode == .json ? 440 : 240)
    }

    // MARK: - Import Actions

    private func performImport() {
        isImporting = true
        importResult = nil

        if importMode == .url {
            Task {
                do {
                    let count = try await sourceManager.importFromURL(importText)
                    importResult = "成功导入 \(count) 个书源"
                    importText = ""
                } catch {
                    importResult = "导入失败: \(error.localizedDescription)"
                }
                isImporting = false
            }
        } else {
            do {
                let count = try sourceManager.importFromJSON(importText)
                importResult = "成功导入 \(count) 个书源"
                importText = ""
            } catch {
                importResult = "导入失败: \(error.localizedDescription)"
            }
            isImporting = false
        }
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let count = try sourceManager.importFromFile(url)
            importResult = "✅ 成功从文件导入 \(count) 个书源"
        } catch {
            importResult = "❌ 文件导入失败: \(error.localizedDescription)"
        }
    }
}
