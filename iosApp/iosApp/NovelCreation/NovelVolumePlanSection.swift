import SwiftUI

/// 代笔设置页：卷规划（生成 / 编辑 / 里程碑进度）与最近节奏。
struct NovelVolumePlanSection: View {
    let workspace: NovelCreationViewModel
    /// 代笔进行中或有写操作时只读。
    let isEditable: Bool

    @State private var direction = ""
    @State private var imeBank = NovelIMEFieldBank()
    @State private var isProposing = false
    @State private var isSaving = false
    @State private var message: String?
    @State private var messageIsError = false
    @State private var recentRows: [PacingRow] = []

    struct PacingRow: Identifiable, Equatable {
        let ordinal: Int
        let intensity: Double
        let newScore: Int
        let isWater: Bool
        let coreChange: String
        var id: Int { ordinal }
    }

    /// 草稿放在 workspace（按项目），切模式或关闭设置页不丢。
    private var draft: String? {
        get { projectID.flatMap { workspace.volumePlanDrafts[$0] } }
        nonmutating set {
            guard let projectID else { return }
            workspace.volumePlanDrafts[projectID] = newValue
        }
    }

    private var projectID: NovelProjectID? { workspace.projectSnapshot?.project.id }

    private struct ReloadKey: Equatable {
        let revision: Int64?
        let branchID: NovelBranchID?
        let ledgerCount: Int
    }

    private var reloadKey: ReloadKey {
        ReloadKey(
            revision: workspace.projectSnapshot?.project.revision,
            branchID: workspace.selectedBranchID,
            ledgerCount: projectID.flatMap { workspace.pacingLedgers[$0]?.entries.count } ?? 0
        )
    }

    var body: some View {
        Section {
            if let draft {
                draftEditor(draft)
            } else if let located = workspace.currentVolumePlan {
                planSummary(located.plan)
            } else {
                emptyState
            }

            if let message, !message.isEmpty {
                Label(
                    message,
                    systemImage: messageIsError ? "exclamationmark.triangle" : "checkmark.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(messageIsError ? AmberTheme.accentRed : AmberTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            // 挂在单个视图上：Section 上的 task 会分发到每一行。
            Text("卷规划")
                .task(id: reloadKey) {
                    await reloadRecentRows()
                }
        } footer: {
            Text("多章代笔开批前，会按卷规划拟定整批骨架并交你确认；里程碑达成后自动打勾。")
                .fixedSize(horizontal: false, vertical: true)
        }

        if !recentRows.isEmpty {
            Section {
                ForEach(recentRows) { row in
                    pacingRow(row)
                }
            } header: {
                Text("最近节奏")
            } footer: {
                Text("强度 1–5；新意 0–3，任一次检查 ≤1 即视为没有推进（水），会自动重写。")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 子视图

    private var emptyState: some View {
        Group {
            if workspace.unreadableVolumePlanMaterialID != nil {
                Label("已有「卷规划」资料但格式无法识别；保存新的卷规划会覆盖它。", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(AmberTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            NovelIMETextEditor(
                text: $direction,
                placeholder: "这一卷想往哪走（可留空，交给 AI 判断）",
                isEnabled: isEditable && !isProposing,
                minHeight: 60,
                bank: imeBank
            )

            primaryButton(title: "生成卷规划", isBusy: isProposing) {
                NovelTextInputCommitter.perform(fieldBank: imeBank) {
                    propose(direction: direction)
                }
            }
            .disabled(!isEditable || isProposing)
        }
    }

    private func planSummary(_ plan: NovelVolumePlan) -> some View {
        Group {
            Text(plan.goal)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(plan.milestones.enumerated()), id: \.offset) { _, milestone in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: milestone.isReached ? "checkmark.circle.fill" : "circle")
                        .font(.footnote)
                        .foregroundStyle(milestone.isReached ? AmberTheme.accent : AmberTheme.muted)
                        .accessibilityHidden(true)
                    Text(milestone.text)
                        .font(.subheadline)
                        .foregroundStyle(milestone.isReached ? AmberTheme.muted : AmberTheme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let label = chapterLabel(milestone) {
                        Text(label)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(AmberTheme.muted)
                            .fixedSize()
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(milestone.isReached ? "已达成" : "待达成")
            }

            HStack(spacing: 12) {
                Button("编辑") {
                    message = nil
                    draft = plan.markdown()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .disabled(!isEditable || isProposing)

                Spacer(minLength: 0)

                Button {
                    propose(direction: plan.direction)
                } label: {
                    busyLabel("重新生成", isBusy: isProposing)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .disabled(!isEditable || isProposing)
            }
        }
    }

    private func draftEditor(_ text: String) -> some View {
        Group {
            NovelIMETextEditor(
                text: Binding(
                    get: { draft ?? text },
                    set: { draft = $0 }
                ),
                isEnabled: isEditable && !isSaving,
                minHeight: 200,
                bank: imeBank
            )

            HStack(spacing: 12) {
                primaryButton(title: "保存为卷规划", isBusy: isSaving) {
                    NovelTextInputCommitter.perform(fieldBank: imeBank) {
                        save()
                    }
                }
                .disabled(!isEditable || isSaving)

                Spacer(minLength: 0)

                Button("放弃") {
                    draft = nil
                    message = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .disabled(isSaving)
            }
        }
    }

    private func pacingRow(_ row: PacingRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("第\(row.ordinal)章")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                Spacer(minLength: 0)
                Text(String(format: "强度 %.1f · 新意 %d", row.intensity, row.newScore))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(AmberTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if row.isWater {
                    Text("水")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AmberTheme.accentRed)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(AmberTheme.accentRed.opacity(0.12), in: Capsule())
                        .accessibilityLabel("判定为水")
                }
            }
            if !row.coreChange.isEmpty {
                Text(row.coreChange)
                    .font(.footnote)
                    .foregroundStyle(AmberTheme.foreground2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func primaryButton(
        title: String,
        isBusy: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            busyLabel(title, isBusy: isBusy)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func busyLabel(_ title: String, isBusy: Bool) -> some View {
        ZStack {
            Text(title)
                .opacity(isBusy ? 0 : 1)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
        }
    }

    private func chapterLabel(_ milestone: NovelVolumePlan.Milestone) -> String? {
        if let reached = milestone.reachedChapter, reached > 0 { return "第\(reached)章" }
        if milestone.isReached { return nil }
        return milestone.targetChapter.map { "约第\($0)章" }
    }

    // MARK: 动作

    private func propose(direction: String) {
        isProposing = true
        message = nil
        Task {
            defer { isProposing = false }
            do {
                let plan = try await workspace.proposeVolumePlan(direction: direction)
                draft = plan.markdown()
            } catch {
                messageIsError = true
                message = "生成失败：\(error.localizedDescription)"
            }
        }
    }

    private func save() {
        guard let draft, let plan = NovelVolumePlan.parse(draft) else {
            messageIsError = true
            message = "格式无法识别：需要「# 卷目标」和「# 里程碑」两节，里程碑每行一条。"
            return
        }
        isSaving = true
        workspace.errorMessage = nil
        Task {
            defer { isSaving = false }
            await workspace.saveVolumePlan(plan)
            if workspace.currentVolumePlan?.plan == plan {
                self.draft = nil
                messageIsError = false
                message = "已保存卷规划。"
            } else {
                messageIsError = true
                message = workspace.errorMessage ?? "保存失败，请重试。"
            }
        }
    }

    private func reloadRecentRows() async {
        guard let branchID = workspace.selectedBranchID else {
            recentRows = []
            return
        }
        recentRows = await workspace.recentPacing(branchID: branchID, limit: 8)
            .reversed()
            .map {
                PacingRow(
                    ordinal: $0.ordinal,
                    intensity: $0.entry.intensity,
                    newScore: $0.entry.newScore,
                    isWater: $0.entry.isWater,
                    coreChange: $0.entry.coreChange
                )
            }
    }
}

/// 代笔设置页：本批骨架（待确认时可重新生成；确认后只读并标出当前章）。
struct NovelBatchSkeletonSection: View {
    let skeleton: NovelGhostwriteBatchSkeleton
    /// 当前推进到全书第几章（标高亮）；nil 不标。
    let currentOrdinal: Int?
    let canRegenerate: Bool
    let onRegenerate: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                labeledLine("起点", skeleton.skeleton.startState)
                labeledLine("终点", skeleton.skeleton.endState)
            }
            .padding(.vertical, 2)

            ForEach(Array(skeleton.skeleton.lines.enumerated()), id: \.offset) { index, line in
                lineRow(index: index, line: line)
            }

            reviewSummary

            if !skeleton.isConfirmed {
                Button(action: onRegenerate) {
                    Text("重新生成骨架")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .contentShape(Rectangle())
                .disabled(!canRegenerate)
            }
        } header: {
            Text(skeleton.isConfirmed ? "本批骨架" : "本批骨架 · 待确认")
        } footer: {
            Text(skeleton.isConfirmed
                ? "每章计划按骨架行拟定；某章没落实时会自动重排剩下的章节，终点不变。"
                : "确认后整批按骨架自动连写，不再逐章确认计划。也可以先到「卷规划」或「往后几章」调整方向再重新生成。")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func labeledLine(_ label: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(AmberTheme.muted)
                .fixedSize()
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func lineRow(index: Int, line: NovelBatchSkeletonLine) -> some View {
        let ordinal = skeleton.startOrdinal + index
        let isCurrent = ordinal == currentOrdinal
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text("第\(ordinal)章")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(isCurrent ? AmberTheme.accent : AmberTheme.foreground)
                Spacer(minLength: 0)
                Text("\(line.beat.isEmpty ? "—" : line.beat) · 强度 \(line.intensity)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(AmberTheme.muted)
                    .fixedSize()
            }
            Text(line.stateChange)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if !line.cost.isEmpty {
                Text("代价：\(line.cost)")
                    .font(.footnote)
                    .foregroundStyle(AmberTheme.foreground2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isCurrent ? "当前章" : "")
    }

    private var reviewSummary: some View {
        let names = NovelBatchSkeletonReviewV1.dimensionNames
        let scores = zip(names, skeleton.review.scores).map { "\($0) \($1)" }.joined(separator: " · ")
        let issues = skeleton.hostIssues + skeleton.review.feedbackLines
        return VStack(alignment: .leading, spacing: 4) {
            // 图标内嵌在文字里：Label 的图标列会把行分隔线顶成缩进，和上面各章对不齐。
            Text("\(Image(systemName: skeleton.passes ? "checkmark.seal" : "exclamationmark.triangle")) \(skeleton.passes ? "评审通过" : "评审未全部通过")")
            .font(.footnote.weight(.medium))
            .foregroundStyle(skeleton.passes ? AmberTheme.foreground2 : AmberTheme.accentRed)
            if !scores.isEmpty {
                Text(scores)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(AmberTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(issues.prefix(4).enumerated()), id: \.offset) { _, issue in
                Text("· \(issue)")
                    .font(.footnote)
                    .foregroundStyle(AmberTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}
