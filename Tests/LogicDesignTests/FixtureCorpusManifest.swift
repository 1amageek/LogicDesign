import Foundation

struct FixtureCorpusManifest: Decodable {
    struct Case: Decodable {
        let expectedStatus: String
        let id: String
        let kind: String
        let path: String
        let sha256: String
        let topDesignName: String
    }

    let cases: [Case]
    let corpusID: String
    let schemaVersion: Int
}
