import Foundation

struct ReviewStore {
    var root: URL

    init(root: URL) {
        self.root = root
    }

    static func applicationSupport() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("EnTrans", isDirectory: true)
    }

    var reviewsURL: URL { root.appendingPathComponent("reviews.json") }
    var digestURL: URL { root.appendingPathComponent("digest.json") }
    var shotsURL: URL { root.appendingPathComponent("shots", isDirectory: true) }

    func prepare() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: shotsURL, withIntermediateDirectories: true)
    }

    func loadSessions() -> [ReviewSession] {
        guard let data = try? Data(contentsOf: reviewsURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([ReviewSession].self, from: data)
        } catch {
            let bad = root.appendingPathComponent("reviews.json.bad")
            try? FileManager.default.removeItem(at: bad)
            try? FileManager.default.moveItem(at: reviewsURL, to: bad)
            return []
        }
    }

    func saveSessions(_ sessions: [ReviewSession]) throws {
        try prepare()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sessions)
        try writeAtomic(data, to: reviewsURL)
    }

    func saveImage(_ data: Data, id: UUID) throws -> String {
        try prepare()
        let filename = "\(id.uuidString).jpg"
        try data.write(to: shotsURL.appendingPathComponent(filename), options: .atomic)
        return filename
    }

    func imageURL(filename: String) -> URL {
        shotsURL.appendingPathComponent(filename)
    }

    func deleteImage(filename: String) {
        guard !filename.isEmpty else { return }
        try? FileManager.default.removeItem(at: imageURL(filename: filename))
    }

    func loadDigest() -> StudyDigest? {
        guard let data = try? Data(contentsOf: digestURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StudyDigest.self, from: data)
    }

    func saveDigest(_ digest: StudyDigest) throws {
        try prepare()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writeAtomic(try encoder.encode(digest), to: digestURL)
    }

    private func writeAtomic(_ data: Data, to url: URL) throws {
        let temporary = url.appendingPathExtension("tmp")
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
    }
}
