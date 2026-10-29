import Foundation

/// One row of `manifest.json` in the bundled `Licenses` resources.
struct NovelLicenseEntry: Decodable, Hashable, Identifiable, Sendable {
    let title: String
    let licenseType: String?
    let file: String

    // Display titles need not be unique. The resource filename is the identity.
    var id: String { file }
}

enum NovelLicenseReaderError: Error, Equatable {
    case unavailableResource
    case invalidUTF8
    case invalidManifest
}

/// Reads the bundled licence manifest and texts. Ported from Amber's
/// `LicenseReader`; reads only bundle resources or an injected local directory.
struct NovelLicenseReader: Sendable {
    static let manifestFile = "manifest.json"

    private let directoryURL: URL?

    init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL
    }

    func loadManifest() async throws -> [NovelLicenseEntry] {
        try await Task.detached(priority: .userInitiated) {
            try self.loadManifestSync()
        }.value
    }

    func loadText(for entry: NovelLicenseEntry) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try self.loadTextSync(for: entry)
        }.value
    }

    func loadManifestSync() throws -> [NovelLicenseEntry] {
        let data = try readResource(Self.manifestFile)
        guard String(data: data, encoding: .utf8) != nil else {
            throw NovelLicenseReaderError.invalidUTF8
        }
        let entries: [NovelLicenseEntry]
        do {
            entries = try JSONDecoder().decode([NovelLicenseEntry].self, from: data)
        } catch {
            throw NovelLicenseReaderError.invalidManifest
        }
        guard !entries.isEmpty,
              Set(entries.map(\.file)).count == entries.count,
              entries.allSatisfy({ entry in
                  !entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && Self.isResourceFilename(entry.file)
              }) else {
            throw NovelLicenseReaderError.invalidManifest
        }
        // Texts are not preflighted: a missing file affects only its own detail page.
        return entries
    }

    func loadTextSync(for entry: NovelLicenseEntry) throws -> String {
        let data = try readResource(entry.file)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NovelLicenseReaderError.invalidUTF8
        }
        // Shown verbatim: no trimming, newline normalization or Markdown parsing.
        return text
    }

    private func readResource(_ file: String) throws -> Data {
        guard Self.isResourceFilename(file),
              let directory = directoryURL ?? Bundle.main.resourceURL,
              directory.isFileURL else {
            throw NovelLicenseReaderError.unavailableResource
        }
        // XcodeGen's explicit file references copy resources to the bundle root.
        let url = directory.appendingPathComponent(file, isDirectory: false)
        do {
            return try Data(contentsOf: url)
        } catch {
            throw NovelLicenseReaderError.unavailableResource
        }
    }

    private static func isResourceFilename(_ file: String) -> Bool {
        !file.isEmpty && file != "." && file != ".."
            && !file.contains("/") && !file.contains("\\") && !file.contains("\0")
    }
}
