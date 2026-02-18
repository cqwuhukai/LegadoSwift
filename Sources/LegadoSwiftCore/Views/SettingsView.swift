import SwiftUI

struct SettingsView: View {
    @Environment(ReadingConfig.self) private var config
    @Environment(BookSourceManager.self) private var sourceManager
    @Environment(BookManager.self) private var bookManager
    @State private var showExportAlert = false
    @State private var exportedJSON = ""
    @State private var showClearAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("设置")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)

                // Reading Settings
                settingsSection("阅读设置", icon: "book.fill") {
                    settingRow("字体大小", value: "\(Int(config.fontSize))") {
                        Slider(value: Bindable(config).fontSize, in: 12...36, step: 1)
                            .frame(width: 200)
                    }
                    settingRow("字体风格", value: config.fontFamily.displayName) {
                        HStack(spacing: 8) {
                            ForEach(FontFamily.allCases) { family in
                                Button(action: {
                                    config.fontFamily = family
                                    config.save()
                                }) {
                                    Text(family.displayName)
                                        .font(.custom(family.fontName, size: 11))
                                        .foregroundColor(config.fontFamily == family ? .white : .primary)
                                        .frame(minWidth: 40)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(config.fontFamily == family ? AppTheme.accent : Color.gray.opacity(0.15))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    settingRow("行距", value: "\(Int(config.lineSpacing))") {
                        Slider(value: Bindable(config).lineSpacing, in: 2...24, step: 1)
                            .frame(width: 200)
                    }
                    settingRow("段间距", value: "\(Int(config.paragraphSpacing))") {
                        Slider(value: Bindable(config).paragraphSpacing, in: 4...32, step: 2)
                            .frame(width: 200)
                    }
                    settingRow("边距", value: "\(Int(config.margins))") {
                        Slider(value: Bindable(config).margins, in: 20...120, step: 5)
                            .frame(width: 200)
                    }
                    settingRow("首行缩进", value: config.firstLineIndent ? "开启" : "关闭") {
                        Toggle("", isOn: Bindable(config).firstLineIndent)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                // Theme
                settingsSection("阅读主题", icon: "paintpalette.fill") {
                    HStack(spacing: 16) {
                        ForEach(ReadingTheme.allCases) { theme in
                            themeCard(theme)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Data
                settingsSection("数据管理", icon: "externaldrive.fill") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("书源数据")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textPrimary)
                            Text("\(sourceManager.sources.count) 个书源 · \(sourceManager.enabledSources.count) 个启用")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        Spacer()
                        Button("复制 JSON") {
                            if let json = sourceManager.exportJSON() {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(json, forType: .string)
                                exportedJSON = "已复制到剪贴板"
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("保存为文件") {
                            exportToFile()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if !exportedJSON.isEmpty {
                        Text(exportedJSON)
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.accentGreen)
                            .transition(.opacity)
                    }

                    Divider().overlay(AppTheme.border.opacity(0.5))

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("书架数据")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textPrimary)
                            Text("\(bookManager.books.count) 本书")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        Spacer()
                    }

                    Divider().overlay(AppTheme.border.opacity(0.5))

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("清除缓存")
                                .font(.system(size: 14))
                                .foregroundColor(AppTheme.textPrimary)
                            Text("清除 EPUB 解压缓存和临时文件")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        Spacer()
                        Button("清除") {
                            clearCache()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                // Keyboard Shortcuts
                settingsSection("快捷键", icon: "keyboard.fill") {
                    shortcutInfoRow("⌘O", description: "打开文件")
                    shortcutInfoRow("⌘1-4", description: "切换标签页")
                    shortcutInfoRow("← →", description: "上/下一章（阅读中）")
                    shortcutInfoRow("⌘F", description: "全屏阅读")
                    shortcutInfoRow("Esc", description: "退出阅读/全屏")
                }

                // About
                settingsSection("关于", icon: "info.circle.fill") {
                    infoRow("应用名称", value: "开源阅读")
                    infoRow("版本", value: "1.0.0")
                    infoRow("平台", value: "macOS (Apple Silicon / Intel)")
                    infoRow("基于", value: "开源阅读")
                    infoRow("框架", value: "SwiftUI + Swift 5.9")

                    Divider().overlay(AppTheme.border.opacity(0.5))

                    HStack {
                        Text("开源阅读是一款优秀的开源阅读器，本应用为其 macOS 版本移植。")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.textTertiary)
                        Spacer()
                    }
                }

                Spacer(minLength: 40)
            }
            .padding(30)
        }
        .background(AppTheme.bgPrimary)
        .onChange(of: config.fontSize) { _, _ in config.save() }
        .onChange(of: config.lineSpacing) { _, _ in config.save() }
        .onChange(of: config.paragraphSpacing) { _, _ in config.save() }
        .onChange(of: config.margins) { _, _ in config.save() }
        .onChange(of: config.firstLineIndent) { _, _ in config.save() }
    }

    // MARK: - Export

    private func exportToFile() {
        guard let json = sourceManager.exportJSON() else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "legado_book_sources.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.title = "导出书源"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try json.write(to: url, atomically: true, encoding: .utf8)
                exportedJSON = "✅ 已保存到 \(url.lastPathComponent)"
            } catch {
                exportedJSON = "❌ 保存失败: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Clear Cache

    private func clearCache() {
        let tempDir = FileManager.default.temporaryDirectory
        let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil)
        var count = 0
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent.hasPrefix("legado_epub_") {
                try? FileManager.default.removeItem(at: url)
                count += 1
            }
        }
        exportedJSON = "✅ 已清除 \(count) 个缓存目录"
    }

    // MARK: - Components

    private func settingsSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(
                        LinearGradient(colors: [AppTheme.accent, AppTheme.accentPurple],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
            }

            VStack(spacing: 1) {
                content()
            }
            .padding(16)
            .background(AppTheme.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppTheme.border, lineWidth: 0.5)
            )
        }
    }

    private func settingRow<Content: View>(_ title: String, value: String, @ViewBuilder control: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textPrimary)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(AppTheme.textTertiary)
                .frame(width: 30)
            Spacer()
            control()
        }
        .padding(.vertical, 4)
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.textPrimary)
        }
        .padding(.vertical, 2)
    }

    private func shortcutInfoRow(_ key: String, description: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(AppTheme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AppTheme.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Text(description)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textSecondary)
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func themeCard(_ theme: ReadingTheme) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                config.theme = theme
            }
            config.save()
        }) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.bgColor)
                    .frame(width: 80, height: 60)
                    .overlay(
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.textColor)
                                .frame(width: 50, height: 3)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.textColor.opacity(0.6))
                                .frame(width: 40, height: 3)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.textColor.opacity(0.3))
                                .frame(width: 45, height: 3)
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                config.theme == theme ? AppTheme.accent : AppTheme.border,
                                lineWidth: config.theme == theme ? 2 : 0.5
                            )
                    )
                    .shadow(color: config.theme == theme ? AppTheme.accent.opacity(0.2) : .clear, radius: 6)

                Text(theme.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(config.theme == theme ? AppTheme.accent : AppTheme.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }
}
