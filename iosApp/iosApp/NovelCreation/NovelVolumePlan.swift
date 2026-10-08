import Foundation

/// 卷规划：卷目标 + 里程碑。以自定义资料（`.custom("volumePlan")`，注入关闭）存放，
/// 复用资料的版本、导出导入与编辑；作者保存即视为确认。里程碑达成由代笔宿主改写资料。
struct NovelVolumePlan: Equatable, Sendable {
    /// 资料页会把自定义类型名直接展示给作者，所以用中文。
    static let customKind = "卷规划"
    static let title = "卷规划"

    struct Milestone: Equatable, Sendable {
        var text: String
        var targetChapter: Int?
        /// 达成于全书第几章；nil 表示待达成。
        var reachedChapter: Int?

        var isReached: Bool { reachedChapter != nil }
    }

    var goal: String
    var direction: String
    var milestones: [Milestone]

    var pendingMilestones: [Milestone] { milestones.filter { !$0.isReached } }

    init(goal: String, direction: String = "", milestones: [Milestone]) {
        self.goal = goal
        self.direction = direction
        self.milestones = milestones
    }

    init(proposal: NovelVolumePlanProposalV1, direction: String) {
        self.init(
            goal: proposal.goal,
            direction: direction,
            milestones: proposal.milestones.map {
                Milestone(text: $0.text, targetChapter: $0.targetChapter, reachedChapter: nil)
            }
        )
    }

    // MARK: Markdown

    func markdown() -> String {
        var parts = ["# 卷目标\n\(goal)"]
        let direction = direction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !direction.isEmpty {
            parts.append("# 作者方向\n\(direction)")
        }
        let lines = milestones.map { milestone -> String in
            var notes: [String] = []
            if let target = milestone.targetChapter { notes.append("约第\(target)章") }
            if let reached = milestone.reachedChapter, reached > 0 { notes.append("第\(reached)章达成") }
            let suffix = notes.isEmpty ? "" : "（\(notes.joined(separator: "；"))）"
            return "- [\(milestone.isReached ? "x" : " ")] \(milestone.text)\(suffix)"
        }
        parts.append("# 里程碑\n" + lines.joined(separator: "\n"))
        return parts.joined(separator: "\n\n")
    }

    static func parse(_ content: String) -> NovelVolumePlan? {
        let sections = NovelPacingMarkdown.sections(content)
        let goal = NovelPacingMarkdown.prose(sections["卷目标"])
        let milestones = (sections["里程碑"] ?? []).compactMap { raw -> Milestone? in
            var line = raw
            var reachedMark = false
            if let box = line.range(of: #"^[-*]\s*\[([ xX✓])\]\s*"#, options: .regularExpression) {
                reachedMark = line[box].lowercased().contains("x") || line[box].contains("✓")
                line = String(line[box.upperBound...])
            } else if let bullet = line.range(of: #"^([-*•]|\d+[.)、])\s*"#, options: .regularExpression) {
                line = String(line[bullet.upperBound...])
            }
            let target = line.range(of: #"约\s*第\s*\d+\s*章"#, options: .regularExpression)
                .flatMap { NovelPacingMarkdown.firstInteger(String(line[$0])) }
            let reached = line.range(of: #"第\s*\d+\s*章\s*达成"#, options: .regularExpression)
                .flatMap { NovelPacingMarkdown.firstInteger(String(line[$0])) }
            let text = line
                .replacingOccurrences(of: #"[（(][^（()）]*第\s*\d+\s*章[^（()）]*[）)]\s*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return Milestone(
                text: text,
                targetChapter: target,
                reachedChapter: reached ?? (reachedMark ? 0 : nil)
            )
        }
        guard !goal.isEmpty, !milestones.isEmpty else { return nil }
        return NovelVolumePlan(
            goal: goal,
            direction: NovelPacingMarkdown.prose(sections["作者方向"]),
            milestones: milestones
        )
    }

    /// 标记里程碑达成（按原文匹配，容忍首尾空白）；没有匹配返回 false。
    mutating func markReached(_ text: String, atChapter chapter: Int) -> Bool {
        let wanted = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty,
              let index = milestones.firstIndex(where: { !$0.isReached && $0.text == wanted })
                ?? (wanted.count >= 4 ? milestones.firstIndex(where: {
                    // 模糊匹配只给够长的文本：防「无。」「暂无」这类短串误配。
                    !$0.isReached && (wanted.contains($0.text) || $0.text.contains(wanted))
                }) : nil) else { return false }
        milestones[index].reachedChapter = chapter
        return true
    }

    // MARK: 定位

    struct Located: Equatable, Sendable {
        let materialID: NovelMaterialID
        let plan: NovelVolumePlan
    }

    static func current(
        materials: [NovelMaterialRecord],
        revisions: [NovelMaterialRevisionRecord]
    ) -> Located? {
        for material in materials where material.kind == .custom(customKind) && !material.isDeleted {
            guard let revision = revisions.first(where: { $0.id == material.currentRevisionID }),
                  let plan = parse(revision.content) else { continue }
            return Located(materialID: material.id, plan: plan)
        }
        return nil
    }

    /// 卷规划拟定的调用方上下文（故事上下文由创作层补在前面）。
    static func proposalContext(
        direction: String,
        recentChanges: [String],
        reachedMilestones: [String] = []
    ) -> String {
        var sections: [String] = []
        let direction = direction.trimmingCharacters(in: .whitespacesAndNewlines)
        sections.append("AUTHOR DIRECTION\n" + (direction.isEmpty ? "(none; decide from the outline and the written story)" : direction))
        if !recentChanges.isEmpty {
            sections.append("RECENT CHANGES\n" + recentChanges.joined(separator: "\n"))
        }
        if !reachedMilestones.isEmpty {
            sections.append(
                "ALREADY REACHED MILESTONES (already in the book; do not list them again)\n"
                    + reachedMilestones.map { "- \($0)" }.joined(separator: "\n")
            )
        }
        return sections.joined(separator: "\n\n")
    }
}
