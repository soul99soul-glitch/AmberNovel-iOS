import XCTest
@testable import iosApp

/// 节奏规则与 Markdown 解析。规则用《赵大来了》第 34–57 章回溯标注数据回放校准
///（作者确认 41–43、48–55 水；44–47、56–57 不水）。
final class NovelChapterPacingTests: XCTestCase {
    /// (章, 字数, 两遍强度, 两遍例行公事, 两遍新意分)。34–38 只作前情，新意分记 3。
    private let calibration: [(Int, Int, [Int], [Bool], [Int])] = [
        (34, 5390, [4, 4], [false, false], [3, 3]),
        (35, 3186, [4, 4], [false, false], [3, 3]),
        (36, 3379, [4, 4], [false, false], [3, 3]),
        (37, 4766, [4, 4], [false, false], [3, 3]),
        (38, 3796, [5, 4], [false, false], [3, 3]),
        (39, 4449, [3, 3], [false, false], [2, 2]),
        (40, 3592, [3, 3], [false, false], [2, 2]),
        (41, 3834, [3, 3], [false, false], [1, 2]),
        (42, 1723, [2, 2], [true, true], [1, 1]),
        (43, 2274, [2, 2], [false, false], [1, 1]),
        (44, 3943, [5, 4], [false, false], [3, 3]),
        (45, 2781, [4, 4], [false, false], [2, 2]),
        (46, 3527, [4, 3], [false, false], [2, 2]),
        (47, 4902, [4, 4], [false, false], [2, 3]),
        (48, 2326, [2, 3], [false, false], [2, 2]),
        (49, 2914, [2, 2], [false, true], [1, 1]),
        (50, 2215, [1, 2], [true, true], [2, 1]),
        (51, 2107, [2, 2], [true, true], [1, 1]),
        (52, 2514, [2, 2], [false, false], [2, 2]),
        (53, 2404, [2, 2], [true, false], [1, 1]),
        (54, 2389, [2, 2], [true, true], [1, 1]),
        (55, 1820, [2, 2], [false, false], [2, 2]),
        (56, 2677, [4, 4], [false, false], [3, 3]),
        (57, 1863, [3, 3], [false, false], [2, 2]),
    ]

    private func pass(intensity: Int, routine: Bool, newScore: Int) -> NovelChapterPacingV1 {
        NovelChapterPacingV1(
            axes: [1, 1, 1, 1, 1],
            intensity: intensity,
            beat: "",
            coreChange: "x",
            routine: routine,
            newScore: newScore,
            repeats: [],
            landedSkeletonLine: nil,
            reachedMilestone: ""
        )
    }

    func testPolicyReplaysCalibratedVerdicts() {
        var ledger: [NovelPacingLedgerEntry] = []
        var flagged: [Int: NovelPacingPolicy.Verdict] = [:]
        for (ordinal, characters, intensities, routines, scores) in calibration {
            let passes = (0..<2).map {
                pass(intensity: intensities[$0], routine: routines[$0], newScore: scores[$0])
            }
            if ordinal >= 39 {
                let verdict = NovelPacingPolicy.verdict(
                    passes: passes,
                    characterCount: characters,
                    recent: Array(ledger.suffix(NovelPacingPolicy.recentWindow))
                )
                if verdict != .pass { flagged[ordinal] = verdict }
            }
            ledger.append(NovelPacingLedgerEntry(
                chapterVersionID: NovelChapterVersionID(),
                characterCount: characters,
                passes: passes
            ))
        }
        XCTAssertEqual(flagged.keys.sorted(), [41, 42, 43, 49, 50, 51, 52, 53, 54, 55])
        XCTAssertEqual(flagged[52], .breathOverBudget(totalCharacters: 9_750))
        XCTAssertEqual(flagged[55], .breathOverBudget(totalCharacters: 13_449))
        XCTAssertEqual(flagged[53], .water(repeats: []))
    }

    func testRoutineStreakNeedsBothPassesAndPreviousRoutine() {
        let previous = NovelPacingLedgerEntry(
            chapterVersionID: NovelChapterVersionID(),
            characterCount: 3_000,
            passes: [pass(intensity: 3, routine: true, newScore: 2)]
        )
        let routine = [pass(intensity: 3, routine: true, newScore: 2), pass(intensity: 3, routine: true, newScore: 2)]
        XCTAssertEqual(
            NovelPacingPolicy.verdict(passes: routine, characterCount: 3_000, recent: [previous]),
            .routineStreak
        )
        let mixed = [pass(intensity: 3, routine: true, newScore: 2), pass(intensity: 3, routine: false, newScore: 2)]
        XCTAssertEqual(
            NovelPacingPolicy.verdict(passes: mixed, characterCount: 3_000, recent: [previous]),
            .pass
        )
    }

    func testParseChapterPacingMarkdown() throws {
        let value = try NovelPacingMarkdown.parseChapterPacing("""
        先说结论：
        # 五轴
        事件 2
        关系：1
        认知 0
        内心 3
        蓄势 1
        # 强度
        4
        # 节奏位
        高潮
        # 主要变化
        沈砚改籍入骑军
        # 例行公事
        否
        # 新意分
        3
        # 重复
        - 第53章：无声赠物
        # 落实骨架
        是
        # 达成里程碑
        - 沈砚进入骑军
        """)
        XCTAssertEqual(value.axes, [2, 1, 0, 3, 1])
        XCTAssertEqual(value.intensity, 4)
        XCTAssertEqual(value.beat, "高潮")
        XCTAssertEqual(value.coreChange, "沈砚改籍入骑军")
        XCTAssertFalse(value.routine)
        XCTAssertEqual(value.newScore, 3)
        XCTAssertEqual(value.repeats, ["第53章：无声赠物"])
        XCTAssertEqual(value.landedSkeletonLine, true)
        XCTAssertEqual(value.reachedMilestone, "沈砚进入骑军")

        XCTAssertThrowsError(try NovelPacingMarkdown.parseChapterPacing("""
        # 强度
        3
        # 主要变化
        没有新意分
        """))
    }

    func testParseBatchSkeletonReviewAndVolumePlan() throws {
        let skeleton = try NovelPacingMarkdown.parseBatchSkeleton("""
        # 起点
        沈砚在步营管账
        # 终点
        沈砚在骑军立住
        # 章节
        ### 第1章
        状态变化：沈砚被调入骑军
        代价：失去步营庇护
        线索：无
        节奏位：升级
        强度：3
        预计字数：3200
        钩子：短马十三
        ### 第2章
        状态变化: 查出空草垛
        代价: 得罪队正
        线索: 推进 黄袍
        节奏位: 高潮
        强度: 4
        预计字数: 4000
        钩子: 队正夜访
        """)
        XCTAssertEqual(skeleton.startState, "沈砚在步营管账")
        XCTAssertEqual(skeleton.lines.count, 2)
        XCTAssertEqual(skeleton.lines[1].stateChange, "查出空草垛")
        XCTAssertEqual(skeleton.lines[1].intensity, 4)
        XCTAssertEqual(skeleton.lines[0].estimatedCharacters, 3_200)
        XCTAssertEqual(skeleton.lines[1].beat, "高潮")

        let review = try NovelPacingMarkdown.parseSkeletonReview("""
        # 硬门槛
        1. 通过
        2. 不通过：第1章与第2章都是查账
        3. 通过
        4. 通过
        # 打分
        推进幅度 4
        代价与风险 1
        新信息 3
        冲突升级 3
        旧线处理 3
        # 扣分理由
        - 第2章换成冲突升级
        """)
        XCTAssertFalse(review.passes)
        XCTAssertEqual(review.gates, [true, false, true, true])
        XCTAssertEqual(review.scores, [4, 1, 3, 3, 3])
        XCTAssertEqual(review.feedbackLines.count, 3)

        let plan = try NovelPacingMarkdown.parseVolumePlan("""
        # 卷目标
        赵大掌一营兵权
        # 里程碑
        1. 赵大夜袭立功（约第60章）
        2. 沈砚被诬陷(第65章前后)
        - 翻盘
        """)
        XCTAssertEqual(plan.goal, "赵大掌一营兵权")
        XCTAssertEqual(plan.milestones.map(\.text), ["赵大夜袭立功", "沈砚被诬陷", "翻盘"])
        XCTAssertEqual(plan.milestones.map(\.targetChapter), [60, 65, nil])
    }

    func testVolumePlanMarkdownRoundTripAndMilestoneProgress() throws {
        var plan = NovelVolumePlan(
            goal: "赵大掌一营兵权",
            direction: "让他在军中立住脚",
            milestones: [
                .init(text: "赵大夜袭立功", targetChapter: 60, reachedChapter: nil),
                .init(text: "沈砚被诬陷", targetChapter: 65, reachedChapter: nil),
            ]
        )
        XCTAssertTrue(plan.markReached("赵大夜袭立功", atChapter: 59))
        XCTAssertFalse(plan.markReached("不存在的里程碑", atChapter: 60))
        let parsed = try XCTUnwrap(NovelVolumePlan.parse(plan.markdown()))
        XCTAssertEqual(parsed, plan)
        XCTAssertEqual(parsed.pendingMilestones.map(\.text), ["沈砚被诬陷"])

        // 作者手改的常见写法也能读。
        let edited = try XCTUnwrap(NovelVolumePlan.parse("""
        # 卷目标
        立住脚
        # 里程碑
        - [x] 夜袭
        - [ ] 被诬陷（约第65章）
        3. 翻盘
        """))
        XCTAssertEqual(edited.milestones.map(\.isReached), [true, false, false])
        XCTAssertEqual(edited.milestones.map(\.targetChapter), [nil, 65, nil])
        XCTAssertNil(NovelVolumePlan.parse("# 卷目标\n只有目标"))
    }

    func testVolumePlanMaterialSurvivesWorkspaceExportImport() throws {
        var document = try NovelTestFixtures.document()
        let plan = NovelVolumePlan(
            goal: "赵大掌一营兵权",
            milestones: [.init(text: "赵大夜袭立功", targetChapter: 60, reachedChapter: nil)]
        )
        document = try NovelReducer.apply(.reviseMaterial(NovelReviseMaterialCommand(
            context: NovelTestFixtures.context(configRevision: document.project.configRevision),
            projectID: document.project.id,
            materialID: NovelMaterialID(),
            revisionID: NovelMaterialRevisionID(),
            kind: .custom(NovelVolumePlan.customKind),
            title: NovelVolumePlan.title,
            content: plan.markdown(),
            tags: [],
            injectionMode: .off,
            aliases: []
        )), to: document).document
        XCTAssertEqual(
            NovelVolumePlan.current(materials: document.materials, revisions: document.materialRevisions)?.plan,
            plan
        )
        let imported = try NovelWorkspaceImporter.makeDocument(from: try NovelWorkspaceBackup.export(document))
        XCTAssertEqual(
            NovelVolumePlan.current(materials: imported.materials, revisions: imported.materialRevisions)?.plan,
            plan
        )
    }

    func testSkeletonHostIssuesCountEndStateAndBreathBudget() {
        func line(_ intensity: Int, _ characters: Int) -> NovelBatchSkeletonLine {
            NovelBatchSkeletonLine(
                stateChange: "变", cost: "", thread: "", beat: "余波",
                intensity: intensity, estimatedCharacters: characters, hook: ""
            )
        }
        let trailingBreath = [NovelPacingLedgerEntry(
            chapterVersionID: NovelChapterVersionID(),
            characterCount: 3_000,
            passes: [pass(intensity: 2, routine: false, newScore: 2)]
        )]
        let skeleton = NovelBatchSkeletonV1(
            startState: "甲",
            endState: "甲",
            lines: [line(2, 3_000), line(2, 3_000), line(4, 4_000)]
        )
        let issues = NovelSkeletonPolicy.hostIssues(skeleton, expectedCount: 4, trailing: trailingBreath)
        XCTAssertEqual(issues.count, 3, issues.joined(separator: "\n"))
        XCTAssertTrue(issues[0].contains("章数不足"))
        XCTAssertTrue(issues[1].contains("终点"))
        XCTAssertTrue(issues[2].contains("第2章"), "接上本批之前的 3000 字喘息，第 2 章累计 9000 字超限")

        var fine = skeleton
        fine.endState = "乙"
        fine.lines = [line(3, 3_000), line(2, 3_000), line(2, 3_000), line(4, 4_000)]
        XCTAssertEqual(NovelSkeletonPolicy.hostIssues(fine, expectedCount: 4, trailing: []), [])
    }

    func testBumpedPlanningPromptsKeepPreviousVersionsReadable() {
        XCTAssertEqual(NovelPromptCatalog.template(for: .chapterPlanProposalV1).version, "novel.chapter-plan-proposal.v5")
        XCTAssertEqual(NovelPromptCatalog.template(for: .chapterAdjudicationV1).version, "novel.chapter-adjudication.v3")
        XCTAssertTrue(NovelPromptCatalog.acceptedVersions(for: .chapterPlanProposalV1).contains("novel.chapter-plan-proposal.v4"))
        XCTAssertTrue(NovelPromptCatalog.acceptedVersions(for: .chapterAdjudicationV1).contains("novel.chapter-adjudication.v2"))
        XCTAssertNotNil(NovelPromptCatalog.systemText(for: .chapterPlanProposalV1, version: "novel.chapter-plan-proposal.v4"))
        XCTAssertNotNil(NovelPromptCatalog.systemText(for: .chapterAdjudicationV1, version: "novel.chapter-adjudication.v2"))
        let proposal = NovelPromptCatalog.template(for: .chapterPlanProposalV1).systemText
        XCTAssertTrue(proposal.contains("chapter-end change of situation and its cost"))
        XCTAssertTrue(proposal.contains("BATCH SKELETON LINE FOR THIS CHAPTER"))
    }

    func testOldBatchProgressSidecarWithoutSkeletonStillDecodes() throws {
        let progress = NovelGhostwriteProgress(
            binding: NovelSessionBinding(projectID: NovelProjectID(), branchID: NovelBranchID()),
            phase: .paused,
            pauseReason: .userPaused,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            targetChapterCount: 3
        )
        let data = try JSONEncoder().encode(NovelGhostwriteBatchProgressRecord.from(progress: progress))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "batchSkeleton")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(NovelGhostwriteBatchProgressRecord.self, from: legacy)
        XCTAssertNil(decoded.batchSkeleton)
        XCTAssertEqual(decoded.targetChapterCount, 3)
    }

    func testMilestoneFuzzyMatchIgnoresShortNoise() {
        var plan = NovelVolumePlan(
            goal: "目标",
            milestones: [.init(text: "无名信的来历揭晓", targetChapter: nil, reachedChapter: nil)]
        )
        XCTAssertFalse(plan.markReached("无。", atChapter: 3))
        XCTAssertTrue(plan.markReached("无名信的来历揭晓了", atChapter: 3))
    }
}
