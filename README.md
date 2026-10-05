# AmberNovel 小说创作

iPhone / iPad 上的 AI 长篇小说创作应用：项目与分支管理、章节生成与润色、讨论 Agent、代笔模式（长时间自动连写，支持后台续跑）、设定与连续性检查、项目备份与导出。需要自备模型服务的 API Key（OpenAI 兼容含 Responses API、Claude、Gemini）。

本仓库是 [AmberAgent-iOS](https://github.com/soul99soul-glitch/AmberAgent-iOS) 中小说应用的独立裁剪版，只保留构建小说应用所需的代码：

- `iosApp/NovelApp/`：应用入口、设置、外观主题、设计动效与应用自身的测试，详见 [iosApp/NovelApp/README.md](iosApp/NovelApp/README.md)
- `iosApp/iosApp/NovelCreation/`：小说创作核心（模型调用、生成生命周期、项目存储、界面）
- `iosApp/iosApp/` 其余文件：小说依赖的共享 Swift 组件（设计系统、Markdown 渲染、模型服务、搜索、后台保活等）
- `iosApp/iosAppTests/`：小说测试
- `shared/`、`ai-core/`、`ai-provider-*/`、`core/`、`feature/`：Kotlin Multiplatform 模块，编译为 `Shared.framework`
- `native/`：Rust 原生库（Markdown 解析等），已附预编译的 `AmberNative.xcframework`

## 构建

需要 macOS、Xcode 26（iOS 26 SDK）、JDK 17 或 21、[XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```sh
export JAVA_HOME=/path/to/jdk   # 未设置时构建脚本会尝试 Homebrew 的 openjdk@17
xcodegen generate --spec iosApp/NovelApp/project.yml
open iosApp/NovelApp/AmberNovel.xcodeproj
```

用 Google 账号登录 Antigravity（Gemini）需要 OAuth 客户端凭据，本仓库留空，需在 `iosApp/iosApp/IOSAntigravityOAuthClient.swift` 的 `IOSAntigravityOAuthConstants` 中自行填写；使用 API Key 不受影响。

首次构建会通过 Gradle 编译 Kotlin 模块，耗时较长。真机运行需在 Xcode 中设置自己的开发团队，并按需修改 Bundle ID（默认 `app.amber.novel`）。

命令行测试：

```sh
xcodebuild -project iosApp/NovelApp/AmberNovel.xcodeproj -scheme Novel \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO test
```

已知测试状况：约 1047 个测试中，有 13 个在原仓库里同样失败（批量润色、设定建议工具、项目恢复等），尚待修复；另有 4 个测试校验 AmberAgent 主应用的接线（读取 `iosApp/iosApp/AppShell.swift`、`iosApp/iosApp/Info.plist`），本仓库不含这些文件，会报文件不存在。

重新编译原生库（可选）见 [native/README.md](native/README.md)。

## 许可

见 [LICENSE](LICENSE)：非商业、个人 / 教育 / 研究用途或不超过 10 名用户时适用 AGPL v3，其余情形需商业许可。
