# 开源阅读 macOS 版 (LegadoSwift)

<p align="center">
  <img src="Assets.xcassets/AppIcon.appiconset/128x128.png" width="128" height="128" alt="LegadoSwift Logo">
</p>

<p align="center">
  <strong>一款基于 SwiftUI 开发的 macOS 电子书阅读器</strong>
</p>

<p align="center">
  <a href="#功能特性">功能特性</a> •
  <a href="#系统要求">系统要求</a> •
  <a href="#安装说明">安装说明</a> •
  <a href="#使用指南">使用指南</a> •
  <a href="#开发构建">开发构建</a> •
  <a href="#贡献指南">贡献指南</a> •
  <a href="#许可证">许可证</a>
</p>

---

## 📖 简介

LegadoSwift 是知名开源阅读器「开源阅读」的 macOS 移植版本。采用原生 SwiftUI 框架开发，提供流畅的阅读体验和现代化的用户界面。

> **注意**: 本项目为社区移植版本，与原版 Android 应用功能可能存在差异。

## ✨ 功能特性

### 📚 阅读功能
- **多格式支持**: 支持 TXT、EPUB 等常见电子书格式
- **书源导入**: 支持自定义书源，可导入网络书源进行在线阅读
- **阅读设置**: 字体大小、行间距、段落间距、边距等自定义
- **深色模式**: 原生支持 macOS 深色模式，护眼阅读
- **目录导航**: 支持章节跳转和目录浏览
- **阅读进度**: 自动保存阅读进度，支持书签功能
- **阅读笔记**: 右键添加笔记，支持笔记导出为markdown

### 🔍 书源管理
- **书源导入**: 支持 JSON 格式书源导入
- **书源编辑**: 可视化书源规则编辑
- **在线搜索**: 基于书源的在线书籍搜索
- **书源调试**: 支持书源规则测试和调试

### 📖 书架管理
- **本地导入**: 支持拖拽导入本地书籍
- **书籍管理**: 支持书籍删除、重排序
- **封面显示**: 自动解析书籍封面信息
- **阅读记录**: 显示最近阅读书籍

### ⌨️ 快捷键支持
| 快捷键 | 功能 |
|--------|------|
| `⌘ + O` | 打开本地文件 |
| `⌘ + 1` | 切换到书架 |
| `⌘ + 2` | 切换到搜索 |
| `⌘ + 3` | 切换到书源 |
| `⌘ + 4` | 切换到设置 |
| `↑/↓` | 章节导航 |
| `←/→` | 翻页 |
| `Esc` | 退出阅读/全屏 |

## 💻 系统要求

- **macOS**: 14.0 (Sonoma) 或更高版本
- **架构**: Apple Silicon (M1/M2/M3) 或 Intel
- **内存**: 建议 4GB 以上
- **存储**: 100MB 可用空间

## 📥 安装说明

### 方式一：下载预编译版本

1. 前往 [Releases](https://github.com/cqwuhukai/LegadoSwift/releases) 页面
2. 下载最新版本的 `LegadoSwift.app.zip`
3. 解压后将应用拖入「应用程序」文件夹
4. 首次运行可能需要前往「系统设置 > 隐私与安全性」允许运行

### 方式二：自行编译

```bash
# 克隆仓库
git clone https://github.com/cqwuhukai/LegadoSwift.git
cd LegadoSwift

# 运行编译脚本
./build.sh

# 编译完成后，应用位于 release/LegadoSwiftApp.app
# 可将其复制到「应用程序」文件夹
cp -r release/LegadoSwiftApp.app /Applications/开源阅读.app
```

## 📖 使用指南

### 导入本地书籍

1. 点击书架页面的「打开文件」按钮，或按 `⌘ + O`
2. 选择要导入的 TXT 或 EPUB 文件
3. 书籍将自动显示在书架上

### 添加书源

1. 切换到「书源」标签页
2. 点击「导入书源」按钮
3. 选择书源 JSON 文件或粘贴书源链接
4. 导入成功后即可在搜索中使用

### 在线搜索

1. 切换到「搜索」标签页
2. 输入书名或作者名
3. 选择书源进行搜索
4. 点击结果即可开始阅读

### 阅读设置

1. 在阅读界面点击设置按钮
2. 调整字体大小、行间距、段落间距
3. 设置页面边距

## 🛠️ 开发构建

### 环境要求

- Xcode 15.0 或更高版本
- Swift 5.9 或更高版本
- macOS 14.0 SDK

### 构建步骤

```bash
# 1. 克隆仓库
git clone https://github.com/cqwuhukai/LegadoSwift.git
cd LegadoSwift

# 2. 解析依赖
swift package resolve

# 3. 构建 Debug 版本
swift build

# 4. 构建 Release 版本
swift build -c release

# 5. 使用构建脚本（推荐）
./build.sh
```

### 项目结构

```
LegadoSwift/
├── Sources/
│   ├── LegadoSwiftApp/          # 应用入口
│   │   └── LegadoSwiftApp.swift
│   └── LegadoSwiftCore/         # 核心功能模块
│       ├── Managers/            # 业务管理器
│       │   ├── BookManager.swift
│       │   └── BookSourceManager.swift
│       ├── Models/              # 数据模型
│       │   ├── Book.swift
│       │   ├── BookSource.swift
│       │   └── ReadingConfig.swift
│       ├── Network/             # 网络层
│       │   └── NetworkClient.swift
│       ├── Reader/              # 阅读器实现
│       │   ├── EpubReader.swift
│       │   └── TxtReader.swift
│       ├── RuleEngine/          # 书源规则引擎
│       │   ├── AnalyzeRule.swift
│       │   ├── RuleAnalyzer.swift
│       │   └── JSEngine.swift
│       ├── Search/              # 搜索功能
│       │   ├── BookSearchEngine.swift
│       │   └── WebBookEngine.swift
│       └── Views/               # SwiftUI 视图
│           ├── ContentView.swift
│           ├── BookshelfView.swift
│           ├── ReaderView.swift
│           └── ...
├── Assets.xcassets/             # 图标和资源
├── Package.swift                # Swift Package Manager 配置
└── build.sh                     # 构建脚本
```

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request！

### 提交 Issue

- 使用清晰的标题描述问题
- 提供复现步骤
- 说明系统版本和软件版本
- 附上相关截图或日志

### 提交代码

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建 Pull Request

详见 [CONTRIBUTING.md](CONTRIBUTING.md)

## 📋 待办事项

- [ ] 支持更多电子书格式（PDF、MOBI 等）
- [ ] 自定义字体导入
- [ ] 阅读主题切换
- [ ] 全文搜索功能
- [ ] 阅读统计
- [ ] iCloud 同步
- [ ] 导出功能优化
- [ ] 插件系统

## 🙏 致谢

- [开源阅读 (Legado)](https://github.com/gedoor/legado) - 原版 Android 阅读器
- [SwiftSoup](https://github.com/scinfu/SwiftSoup) - HTML 解析库
- [Swift Atomics](https://github.com/apple/swift-atomics) - 原子操作支持
- [LRUCache](https://github.com/nicklockwood/LRUCache) - 缓存实现

## 📄 许可证

本项目采用 GPL-3.0 许可证开源 - 详见 [LICENSE](LICENSE) 文件

## ⚠️ 免责声明

本软件仅供学习交流使用，严禁用于商业用途。用户使用本软件所产生的任何后果由用户自行承担。

---

<p align="center">
  Made with ❤️ by LegadoSwift Team
</p>
