import XCTest
@testable import iosApp

final class NovelLicensesTests: XCTestCase {
    private func hostBundleReader() throws -> NovelLicenseReader {
        // Tests run inside the AmberNovel host app; read its bundle, not the xctest bundle.
        let url = try XCTUnwrap(Bundle.main.resourceURL)
        return NovelLicenseReader(directoryURL: url)
    }

    func testManifestLoadsFromAppBundleAndStartsWithAppLicense() throws {
        let entries = try hostBundleReader().loadManifestSync()
        XCTAssertFalse(entries.isEmpty)
        let first = try XCTUnwrap(entries.first)
        XCTAssertEqual(first.file, "AmberNovel-LICENSE.txt")
        let text = try hostBundleReader().loadTextSync(for: first)
        XCTAssertTrue(text.contains("Segmented Dual Licensing"))
        XCTAssertTrue(entries.contains { $0.file == "GNU-AGPL-3.0-standard.txt" })
    }

    func testEveryManifestFileIsBundledNonEmptyUTF8() throws {
        let reader = try hostBundleReader()
        let resourceURL = try XCTUnwrap(Bundle.main.resourceURL)
        for entry in try reader.loadManifestSync() {
            let url = resourceURL.appendingPathComponent(entry.file, isDirectory: false)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "missing \(entry.file)")
            let text = try reader.loadTextSync(for: entry)
            XCTAssertFalse(
                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "empty \(entry.file)"
            )
        }
    }

    func testAboutLinksPointAtPublishedLocations() {
        XCTAssertEqual(
            NovelAboutLinks.sourceCode.absoluteString,
            "https://github.com/soul99soul-glitch/AmberNovel-iOS/tree/v1.0.0-build1"
        )
        XCTAssertEqual(NovelAboutLinks.support.absoluteString, "https://novel.apps.air.build/support/")
        XCTAssertEqual(NovelAboutLinks.privacy.absoluteString, "https://novel.apps.air.build/privacy/")
    }

    func testReaderRejectsPathTraversal() {
        let entry = NovelLicenseEntry(title: "x", licenseType: nil, file: "../Info.plist")
        XCTAssertThrowsError(try NovelLicenseReader().loadTextSync(for: entry)) { error in
            XCTAssertEqual(error as? NovelLicenseReaderError, .unavailableResource)
        }
    }
}
