import SwiftUI

/// Public links shown in Settings ▸ 关于 and on the licences page.
enum NovelAboutLinks {
    static let sourceTag = "v1.0.0-build1"
    static let sourceCode = URL(string: "https://github.com/soul99soul-glitch/AmberNovel-iOS/tree/v1.0.0-build1")!
    static let support = URL(string: "https://novel.apps.air.build/support/")!
    static let privacy = URL(string: "https://novel.apps.air.build/privacy/")!
}

private enum NovelLicenseLoadState<Value> {
    case loading
    case loaded(Value)
    case failed
}

struct NovelLicensesView: View {
    let onOpenEntry: (NovelLicenseEntry) -> Void

    @State private var state: NovelLicenseLoadState<[NovelLicenseEntry]> = .loading

    var body: some View {
        Form {
            Section {
                Link(destination: NovelAboutLinks.sourceCode) {
                    NovelAboutLinkLabel(
                        title: "源代码",
                        subtitle: "标签 \(NovelAboutLinks.sourceTag)",
                        systemImage: "chevron.left.forwardslash.chevron.right"
                    )
                }
                Link(destination: NovelAboutLinks.support) {
                    NovelAboutLinkLabel(title: "支持", subtitle: nil, systemImage: "questionmark.circle")
                }
                Link(destination: NovelAboutLinks.privacy) {
                    NovelAboutLinkLabel(title: "隐私政策", subtitle: nil, systemImage: "hand.raised")
                }
            } footer: {
                Text("小说创作以 GNU AGPL v3（及商业许可）发布，可按上方链接获取对应版本的完整源代码。")
            }

            switch state {
            case .loading:
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在读取许可信息…")
                            .foregroundStyle(AmberTheme.muted)
                    }
                }
            case .failed:
                Section {
                    Label("无法读取许可信息", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(AmberTheme.muted)
                }
            case .loaded(let entries):
                Section {
                    ForEach(entries) { entry in
                        Button {
                            onOpenEntry(entry)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: entry.title)
                                        .foregroundStyle(AmberTheme.foreground)
                                    if let type = entry.licenseType {
                                        Text(verbatim: type)
                                            .font(.caption)
                                            .foregroundStyle(AmberTheme.muted)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AmberTheme.muted2)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("许可证")
                } footer: {
                    Text("本应用及其包含的第三方组件的许可证与版权声明原文。")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AmberTheme.background)
        .navigationTitle("开源许可")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard case .loading = state else { return }
            do {
                let entries = try await NovelLicenseReader().loadManifest()
                guard !Task.isCancelled else { return }
                state = .loaded(entries)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed
            }
        }
    }
}

struct NovelLicenseDetailView: View {
    let entry: NovelLicenseEntry

    @State private var state: NovelLicenseLoadState<String> = .loading

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                Label("无法读取许可证文本", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(AmberTheme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let text):
                ScrollView {
                    Text(verbatim: text)
                        .font(.footnote.monospaced())
                        .foregroundStyle(AmberTheme.foreground)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
        }
        .background(AmberTheme.background)
        .navigationTitle(Text(verbatim: entry.title))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: entry.file) {
            state = .loading
            do {
                let text = try await NovelLicenseReader().loadText(for: entry)
                guard !Task.isCancelled else { return }
                state = .loaded(text)
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed
            }
        }
    }
}

struct NovelAboutLinkLabel: View {
    let title: String
    let subtitle: String?
    let systemImage: String

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(AmberTheme.foreground)
                    if let subtitle {
                        Text(verbatim: subtitle)
                            .font(.caption)
                            .foregroundStyle(AmberTheme.muted)
                    }
                }
            } icon: {
                Image(systemName: systemImage)
            }
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AmberTheme.muted2)
        }
        .contentShape(Rectangle())
    }
}
