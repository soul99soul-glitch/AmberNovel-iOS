import Foundation

// MARK: - 章节节奏判定（模型输出）

/// 一次「章节节奏判定」的结果：五轴变化、强度、主要变化与相对近期章节的新意。
/// 同一章独立判两遍；判水取严格的一遍（见 `NovelPacingPolicy`）。
struct NovelChapterPacingV1: Codable, Equatable, Sendable {
    /// 事件、关系、认知、内心、蓄势，各 0–3。
    var axes: [Int]
    /// 1–5。
    var intensity: Int
    /// 铺垫 / 升级 / 高潮 / 余波。
    var beat: String
    /// 本章结束时与开头相比最主要的不同（≤40 字）。
    var coreChange: String
    /// 主体是把公事办完且局面照旧。
    var routine: Bool
    /// 0–3：相对最近几章真正新增的变化。
    var newScore: Int
    /// 「第N章：重复了什么」。
    var repeats: [String]
    /// 有骨架行时是否落实；无骨架时为 nil。
    var landedSkeletonLine: Bool?
    /// 本章达成的里程碑原文；没有为空串。
    var reachedMilestone: String
}

// MARK: - 节奏账

/// 节奏账条目：按章节版本作键，正文换版即失效。
struct NovelPacingLedgerEntry: Codable, Equatable, Sendable {
    let chapterVersionID: NovelChapterVersionID
    let characterCount: Int
    /// 1 遍（补标）或 2 遍（代笔判水）。
    let passes: [NovelChapterPacingV1]

    var intensity: Double {
        guard !passes.isEmpty else { return 0 }
        return Double(passes.map(\.intensity).reduce(0, +)) / Double(passes.count)
    }

    var newScore: Int { passes.map(\.newScore).min() ?? 0 }
    var coreChange: String { passes.first?.coreChange ?? "" }
    var routine: Bool { !passes.isEmpty && passes.allSatisfy(\.routine) }
    var isWater: Bool { NovelPacingPolicy.isWater(passes) }
    var isBreath: Bool { intensity <= NovelPacingPolicy.breathIntensityCeiling }
}

/// 按项目落盘的节奏账缓存（派生数据，可重算）。
struct NovelPacingLedgerRecord: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    /// 只为最近章节服务；超出部分丢最旧的。
    static let maxEntries = 400

    var schemaVersion: Int
    var projectID: NovelProjectID
    var entries: [NovelPacingLedgerEntry]

    init(projectID: NovelProjectID, entries: [NovelPacingLedgerEntry] = []) {
        schemaVersion = Self.currentSchemaVersion
        self.projectID = projectID
        self.entries = entries
    }

    func entry(for versionID: NovelChapterVersionID) -> NovelPacingLedgerEntry? {
        entries.last { $0.chapterVersionID == versionID }
    }

    mutating func upsert(_ entry: NovelPacingLedgerEntry) {
        entries.removeAll { $0.chapterVersionID == entry.chapterVersionID }
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }
}

// MARK: - 规则（纯函数）

enum NovelPacingPolicy {
    /// 喘息段（连续低强度章）总字数上限。作者裁决：不按章数，按字数。
    static let breathBudgetCharacters = 8_000
    /// 平均强度不高于此值即视为喘息章。
    static let breathIntensityCeiling = 2.0
    /// 任一遍新意分不高于此值即判水（39–57 章校准）。
    static let waterNewScoreCeiling = 1
    /// 判水时对照的近期章数。
    static let recentWindow = 5

    static func isWater(_ passes: [NovelChapterPacingV1]) -> Bool {
        guard let worst = passes.map(\.newScore).min() else { return false }
        return worst <= waterNewScoreCeiling
    }

    enum Verdict: Equatable, Sendable {
        case pass
        case water(repeats: [String])
        case routineStreak
        case breathOverBudget(totalCharacters: Int)
    }

    /// - Parameters:
    ///   - passes: 候选章的判定结果（通常两遍）。
    ///   - recent: 当前分支最近章节的账目，按章序排列（最后一条紧挨候选）。
    static func verdict(
        passes: [NovelChapterPacingV1],
        characterCount: Int,
        recent: [NovelPacingLedgerEntry]
    ) -> Verdict {
        if isWater(passes) {
            var seen: Set<String> = []
            return .water(repeats: passes.flatMap(\.repeats).filter { seen.insert($0).inserted })
        }
        if !passes.isEmpty, passes.allSatisfy(\.routine), recent.last?.routine == true {
            return .routineStreak
        }
        let intensity = Double(passes.map(\.intensity).reduce(0, +)) / Double(max(passes.count, 1))
        if intensity <= breathIntensityCeiling {
            var total = characterCount
            for entry in recent.reversed() {
                guard entry.isBreath else { break }
                total += entry.characterCount
            }
            if total > breathBudgetCharacters {
                return .breathOverBudget(totalCharacters: total)
            }
        }
        return .pass
    }

    /// 写给改写稿的说明（进失败回执的 summary）。
    static func rewriteSummary(for verdict: Verdict) -> String? {
        switch verdict {
        case .pass:
            return nil
        case .water:
            return "本章没有带来新的变化，或只是把最近几章发生过的同类变化换了道具重演。改写时必须让局面在至少一条轴上（事件、关系、认知、内心、蓄势）产生新的、不可逆的变化，不要再重复下面列出的节拍。"
        case .routineStreak:
            return "连续两章的主体都是把公事办完、局面照旧。改写时公事只作背景，本章要让局面真正改变。"
        case .breathOverBudget(let total):
            return "连续低强度章节已累计约 \(total) 字，超过 8000 字的喘息上限。改写时抬升强度：让冲突升级、危机逼近，或推进主线事件。"
        }
    }
}

// MARK: - 判定上下文

enum NovelPacingContext {
    static let previousTailCharacters = 600

    /// 节奏判定的系统侧上下文。`recent` 为最近章节（章序, 主要变化）。
    static func judgeContext(
        recent: [(ordinal: Int, coreChange: String)],
        previousChapterTail: String?,
        skeletonLine: String?,
        pendingMilestones: [String]
    ) -> String {
        var sections: [String] = []
        let lines = recent
            .filter { !$0.coreChange.isEmpty }
            .map { "第\($0.ordinal)章：\($0.coreChange)" }
        sections.append("RECENT CHANGES\n" + (lines.isEmpty ? "(none)" : lines.joined(separator: "\n")))
        if let tail = previousChapterTail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tail.isEmpty {
            sections.append("PREVIOUS CHAPTER ENDING\n" + String(tail.suffix(previousTailCharacters)))
        }
        if let skeletonLine, !skeletonLine.isEmpty {
            sections.append("SKELETON LINE\n" + skeletonLine)
        }
        if !pendingMilestones.isEmpty {
            sections.append("MILESTONES\n" + pendingMilestones.map { "- \($0)" }.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }
}

// MARK: - Markdown 输出解析

/// 按 `# 标题` 切段的宽松解析，各节点任务共用。
enum NovelPacingMarkdown {
    static func sections(_ raw: String) -> [String: [String]] {
        var buckets: [String: [String]] = [:]
        var current: String?
        for line in raw.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("```") { continue }
            if trimmed.hasPrefix("#"), !trimmed.hasPrefix("###") {
                current = trimmed
                    .replacingOccurrences(of: #"^#{1,2}\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                buckets[current!, default: []] = buckets[current!, default: []]
                continue
            }
            guard let current, !trimmed.isEmpty else { continue }
            buckets[current, default: []].append(trimmed)
        }
        return buckets
    }

    static func prose(_ lines: [String]?) -> String {
        (lines ?? []).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func listItems(_ lines: [String]?) -> [String] {
        (lines ?? []).map { raw in
            var line = raw
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                line = String(line.dropFirst(2))
            } else if let bullet = line.range(of: #"^\d+[.)、]\s*"#, options: .regularExpression) {
                line = String(line[bullet.upperBound...])
            }
            return line.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !["", "无", "没有", "（无）"].contains($0) }
    }

    /// 行内第一个整数。
    static func firstInteger(_ text: String) -> Int? {
        guard let range = text.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(text[range])
    }

    static func yes(_ text: String) -> Bool? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("是") || value.lowercased().hasPrefix("yes") || value.lowercased() == "true" {
            return true
        }
        if value.hasPrefix("否") || value.lowercased().hasPrefix("no") || value.lowercased() == "false" {
            return false
        }
        return nil
    }

    static func failure(_ path: String, _ message: String) -> NovelStructuredOutputFailure {
        NovelStructuredOutputFailure(category: .invalidValue, path: path, message: message)
    }

    static let beats = ["铺垫", "升级", "高潮", "余波"]

    static func parseChapterPacing(_ raw: String) throws -> NovelChapterPacingV1 {
        let s = sections(raw)
        let axisNames = ["事件", "关系", "认知", "内心", "蓄势"]
        let axisLines = s["五轴"] ?? []
        let axes = axisNames.map { name in
            axisLines.first { $0.hasPrefix(name) }.flatMap(firstInteger).map { min(max($0, 0), 3) } ?? 0
        }
        guard let intensity = (s["强度"]?.first).flatMap(firstInteger) else {
            throw failure("$.intensity", "节奏判定缺少「强度」。")
        }
        guard let newScore = (s["新意分"]?.first).flatMap(firstInteger) else {
            throw failure("$.newScore", "节奏判定缺少「新意分」。")
        }
        let core = prose(s["主要变化"])
        guard !core.isEmpty else {
            throw failure("$.coreChange", "节奏判定缺少「主要变化」。")
        }
        let beatText = prose(s["节奏位"])
        let landed = prose(s["落实骨架"])
        return NovelChapterPacingV1(
            axes: axes,
            intensity: min(max(intensity, 1), 5),
            beat: beats.first { beatText.contains($0) } ?? "",
            coreChange: String(core.prefix(80)),
            routine: yes(prose(s["例行公事"])) ?? false,
            newScore: min(max(newScore, 0), 3),
            repeats: Array(listItems(s["重复"]).prefix(4).map { String($0.prefix(120)) }),
            landedSkeletonLine: landed.hasPrefix("无") ? nil : yes(landed),
            reachedMilestone: listItems(s["达成里程碑"]).first ?? ""
        )
    }
}

// MARK: - 批次骨架 / 评审 / 卷规划（模型输出）

struct NovelBatchSkeletonLine: Codable, Equatable, Sendable {
    var stateChange: String
    var cost: String
    var thread: String
    var beat: String
    var intensity: Int
    var estimatedCharacters: Int
    var hook: String

    /// 注入本章计划拟定与节奏判定的单行描述。
    var promptText: String {
        var parts = ["状态变化：\(stateChange)", "代价：\(cost)"]
        if !thread.isEmpty, thread != "无" { parts.append("线索：\(thread)") }
        parts.append("节奏位：\(beat)，强度 \(intensity)")
        if !hook.isEmpty { parts.append("钩子：\(hook)") }
        return parts.joined(separator: "；")
    }
}

struct NovelBatchSkeletonV1: Codable, Equatable, Sendable {
    var startState: String
    var endState: String
    var lines: [NovelBatchSkeletonLine]
}

struct NovelBatchSkeletonReviewV1: Codable, Equatable, Sendable {
    static let dimensionNames = ["推进幅度", "代价与风险", "新信息", "冲突升级", "旧线处理"]
    static let minimumScore = 2

    var gates: [Bool]
    var gateNotes: [String]
    var scores: [Int]
    var deductions: [String]

    var passes: Bool {
        gates.allSatisfy { $0 } && scores.allSatisfy { $0 >= Self.minimumScore }
    }

    /// 不过关时写回拟定的扣分理由（含未过的门槛与低分维度）。
    var feedbackLines: [String] {
        var lines = gateNotes.filter { !$0.isEmpty }
        for (index, score) in scores.enumerated() where score < Self.minimumScore {
            lines.append("「\(Self.dimensionNames[index])」只有 \(score) 分")
        }
        return lines + deductions
    }
}

struct NovelVolumeMilestoneDraft: Codable, Equatable, Sendable {
    var text: String
    var targetChapter: Int?
}

struct NovelVolumePlanProposalV1: Codable, Equatable, Sendable {
    var goal: String
    var milestones: [NovelVolumeMilestoneDraft]
}

extension NovelPacingMarkdown {
    /// 「键：值」行（全角或半角冒号）。
    static func keyed(_ lines: [String], _ key: String) -> String {
        for line in lines {
            for separator in ["：", ":"] where line.hasPrefix(key + separator) {
                return String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    static func parseBatchSkeleton(_ raw: String) throws -> NovelBatchSkeletonV1 {
        let s = sections(raw)
        var blocks: [[String]] = []
        for line in s["章节"] ?? [] {
            let heading = line.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
            if line.hasPrefix("#") || heading.range(of: #"^第\s*\d+\s*章\s*$"#, options: .regularExpression) != nil {
                blocks.append([])
            } else if !blocks.isEmpty {
                blocks[blocks.count - 1].append(line)
            }
        }
        let lines = blocks.compactMap { block -> NovelBatchSkeletonLine? in
            let change = keyed(block, "状态变化")
            guard !change.isEmpty else { return nil }
            let beatText = keyed(block, "节奏位")
            return NovelBatchSkeletonLine(
                stateChange: change,
                cost: keyed(block, "代价"),
                thread: keyed(block, "线索"),
                beat: beats.first { beatText.contains($0) } ?? "",
                intensity: min(max(firstInteger(keyed(block, "强度")) ?? 3, 1), 5),
                estimatedCharacters: firstInteger(keyed(block, "预计字数")) ?? 3_000,
                hook: keyed(block, "钩子")
            )
        }
        guard !lines.isEmpty else {
            throw failure("$.lines", "批次骨架缺少「章节」。")
        }
        return NovelBatchSkeletonV1(
            startState: prose(s["起点"]),
            endState: prose(s["终点"]),
            lines: lines
        )
    }

    static func parseSkeletonReview(_ raw: String) throws -> NovelBatchSkeletonReviewV1 {
        let s = sections(raw)
        let gateLines = listItems(s["硬门槛"])
        guard !gateLines.isEmpty else {
            throw failure("$.gates", "骨架评审缺少「硬门槛」。")
        }
        let gates = gateLines.map { !$0.hasPrefix("不通过") && !$0.contains("不通过") }
        let notes = gateLines.filter { $0.contains("不通过") }
        let scoreLines = s["打分"] ?? []
        let scores = NovelBatchSkeletonReviewV1.dimensionNames.map { name in
            scoreLines.first { $0.hasPrefix(name) }.flatMap(firstInteger) ?? 0
        }
        return NovelBatchSkeletonReviewV1(
            gates: gates,
            gateNotes: notes,
            scores: scores,
            deductions: listItems(s["扣分理由"])
        )
    }

    static func parseVolumePlan(_ raw: String) throws -> NovelVolumePlanProposalV1 {
        let s = sections(raw)
        let goal = prose(s["卷目标"])
        let milestones = listItems(s["里程碑"]).map { line -> NovelVolumeMilestoneDraft in
            // 目标章只从行尾括号取，描述里提到的「第3章」不算。
            let target = line.range(of: #"[（(][^（()）]*第\s*\d+\s*章[^（()）]*[）)]\s*$"#, options: .regularExpression)
                .flatMap { firstInteger(String(line[$0])) }
            let text = line
                .replacingOccurrences(of: #"[（(]\s*约?\s*第\s*\d+\s*章[^）)]*[）)]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return NovelVolumeMilestoneDraft(text: text, targetChapter: target)
        }
        .filter { !$0.text.isEmpty }
        guard !goal.isEmpty, !milestones.isEmpty else {
            throw failure("$.milestones", "卷规划缺少「卷目标」或「里程碑」。")
        }
        return NovelVolumePlanProposalV1(goal: goal, milestones: Array(milestones.prefix(8)))
    }
}

// MARK: - 批次骨架（运行状态与规则）

/// 本批骨架：存进代笔进度 sidecar（单批运行状态）。
struct NovelGhostwriteBatchSkeleton: Codable, Equatable, Sendable {
    var skeleton: NovelBatchSkeletonV1
    var review: NovelBatchSkeletonReviewV1
    /// 宿主可算的硬门槛（章数、喘息字数、起终点）未过的理由。
    var hostIssues: [String]
    /// 本批第 1 章在全书中的章序。
    var startOrdinal: Int
    var isConfirmed: Bool
    /// 已收录的章没有落实骨架行：下一章前重排剩余行。
    var needsReplan: Bool

    var passes: Bool { hostIssues.isEmpty && review.passes }

    func line(forChapterOrdinal ordinal: Int) -> NovelBatchSkeletonLine? {
        let index = ordinal - startOrdinal
        return skeleton.lines.indices.contains(index) ? skeleton.lines[index] : nil
    }
}

enum NovelSkeletonPolicy {
    static let maxRounds = 3

    /// - Parameter trailing: 本批之前紧挨着的节奏账（章序），用于接续喘息字数。
    static func hostIssues(
        _ skeleton: NovelBatchSkeletonV1,
        expectedCount: Int,
        trailing: [NovelPacingLedgerEntry]
    ) -> [String] {
        var issues: [String] = []
        if skeleton.lines.count < expectedCount {
            issues.append("章数不足：应为 \(expectedCount) 章，只拟了 \(skeleton.lines.count) 章")
        }
        let start = skeleton.startState.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = skeleton.endState.trimmingCharacters(in: .whitespacesAndNewlines)
        if end.isEmpty || end == start {
            issues.append("终点必须写明，且与起点不同")
        }
        var breath = 0
        for entry in trailing.reversed() {
            guard entry.isBreath else { break }
            breath += entry.characterCount
        }
        for (index, line) in skeleton.lines.enumerated() {
            guard Double(line.intensity) <= NovelPacingPolicy.breathIntensityCeiling else {
                breath = 0
                continue
            }
            breath += line.estimatedCharacters
            if breath > NovelPacingPolicy.breathBudgetCharacters {
                issues.append("第\(index + 1)章处连续低强度章节累计约 \(breath) 字，超过 8000 字的喘息上限")
                breath = 0
            }
        }
        return issues
    }

    /// 骨架拟定的调用方上下文（故事上下文由创作层补在前面）。
    static func proposalContext(
        chapterCount: Int,
        plan: NovelVolumePlan,
        recentChanges: [String],
        fixedFirstChapterPlan: String?,
        writtenInBatch: [String],
        fixedEndState: String?,
        feedback: [String]
    ) -> String {
        var sections = ["TARGET CHAPTER COUNT\n\(chapterCount)"]
        var volume = ["卷目标：\(plan.goal)"]
        let pending = plan.pendingMilestones.map { milestone -> String in
            milestone.targetChapter.map { "- \(milestone.text)（约第\($0)章）" } ?? "- \(milestone.text)"
        }
        if !pending.isEmpty { volume.append("待达成里程碑：\n" + pending.joined(separator: "\n")) }
        sections.append("VOLUME PLAN\n" + volume.joined(separator: "\n"))
        if !recentChanges.isEmpty {
            sections.append("RECENT CHANGES\n" + recentChanges.joined(separator: "\n"))
        }
        if let fixedFirstChapterPlan, !fixedFirstChapterPlan.isEmpty {
            sections.append("FIXED CHAPTER 1 (the author already confirmed this plan; copy it as 第1章)\n" + fixedFirstChapterPlan)
        }
        if !writtenInBatch.isEmpty {
            sections.append(
                "ALREADY WRITTEN IN THIS BATCH (do not include them; plan only the remaining chapters, continuing from their actual outcome)\n"
                    + writtenInBatch.joined(separator: "\n")
            )
        }
        if let fixedEndState, !fixedEndState.isEmpty {
            sections.append("FIXED END STATE (keep this 终点)\n" + fixedEndState)
        }
        if !feedback.isEmpty {
            sections.append(
                "REVIEW FEEDBACK FROM THE LAST ROUND (fix every item)\n"
                    + feedback.map { "- \($0)" }.joined(separator: "\n")
            )
        }
        return sections.joined(separator: "\n\n")
    }

    static func reviewContext(recentChanges: [String]) -> String {
        "RECENT CHANGES\n" + (recentChanges.isEmpty ? "(none)" : recentChanges.joined(separator: "\n"))
    }

    static func render(_ skeleton: NovelBatchSkeletonV1) -> String {
        var parts = ["# 起点\n\(skeleton.startState)", "# 终点\n\(skeleton.endState)", "# 章节"]
        for (index, line) in skeleton.lines.enumerated() {
            parts.append("""
            ### 第\(index + 1)章
            状态变化：\(line.stateChange)
            代价：\(line.cost)
            线索：\(line.thread.isEmpty ? "无" : line.thread)
            节奏位：\(line.beat)
            强度：\(line.intensity)
            预计字数：\(line.estimatedCharacters)
            钩子：\(line.hook)
            """)
        }
        return parts.joined(separator: "\n\n")
    }
}
