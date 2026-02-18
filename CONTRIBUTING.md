# 贡献指南

感谢您对 LegadoSwift 项目的关注！我们欢迎各种形式的贡献，包括但不限于：

- 提交 Bug 报告
- 提出新功能建议
- 改进文档
- 提交代码修复
- 分享使用经验

## 如何贡献

### 报告问题

如果您发现了 Bug 或有功能建议，请通过 [GitHub Issues](https://github.com/cqwuhukai/LegadoSwift/issues) 提交。

**提交 Bug 报告时，请包含以下信息：**

- 问题的清晰描述
- 复现步骤
- 期望行为与实际行为
- 截图（如适用）
- 系统信息：
  - macOS 版本
  - 应用版本
  - 设备型号（Apple Silicon/Intel）

### 提交代码

1. **Fork 仓库**
   ```bash
   git clone https://github.com/cqwuhukai/LegadoSwift.git
   cd LegadoSwift
   ```

2. **创建分支**
   ```bash
   git checkout -b feature/your-feature-name
   # 或
   git checkout -b fix/your-bug-fix
   ```

3. **进行更改**
   - 遵循现有的代码风格
   - 添加必要的注释
   - 确保代码可以编译通过

4. **提交更改**
   ```bash
   git add .
   git commit -m "feat: 添加新功能描述"
   ```

   **提交信息规范：**
   - `feat:` 新功能
   - `fix:` 修复 Bug
   - `docs:` 文档更新
   - `style:` 代码格式调整（不影响功能）
   - `refactor:` 代码重构
   - `test:` 测试相关
   - `chore:` 构建过程或辅助工具的变动

5. **推送到 Fork**
   ```bash
   git push origin feature/your-feature-name
   ```

6. **创建 Pull Request**
   - 前往原仓库创建 PR
   - 清晰描述更改内容
   - 关联相关 Issue（如适用）

## 代码规范

### Swift 代码风格

- 使用 4 个空格缩进
- 遵循 [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- 使用有意义的变量名和函数名
- 添加必要的注释说明复杂逻辑

### 示例

```swift
// 好的示例
func loadBook(from url: URL) async throws -> Book {
    // 实现代码
}

// 不好的示例
func load(u: URL) -> Book {
    // 实现代码
}
```

## 开发流程

### 环境设置

1. 安装 Xcode 15.0 或更高版本
2. 安装 Command Line Tools
3. 克隆仓库并打开 Package.swift

### 构建和测试

```bash
# 构建项目
swift build

# 构建 Release 版本
swift build -c release

# 使用构建脚本
./build.sh
```

### 调试技巧

- 使用 Xcode 的调试工具
- 查看 Console 日志输出
- 使用 Instruments 进行性能分析

## 项目结构说明

```
Sources/
├── LegadoSwiftApp/      # 应用入口
└── LegadoSwiftCore/     # 核心功能
    ├── Managers/        # 业务逻辑管理器
    ├── Models/          # 数据模型
    ├── Network/         # 网络请求
    ├── Reader/          # 阅读器实现
    ├── RuleEngine/      # 书源规则引擎
    ├── Search/          # 搜索功能
    └── Views/           # SwiftUI 视图
```

## 行为准则

- 保持友好和尊重
- 接受建设性的批评
- 关注对社区最有利的事情
- 展示对他人的同理心

## 联系方式

- GitHub Issues: [提交问题](https://github.com/cqwuhukai/LegadoSwift/issues)


## 许可证

通过贡献代码，您同意您的贡献将在 GPL-3.0 许可证下发布。

---

再次感谢您的贡献！
