#if canImport(XCTest)
import XCTest
@testable import OrchivisteAnalyse

final class AnalysisMLSupportTests: XCTestCase {
    func testHashedTextFeatureVectorHasRequestedDimension() {
        let vector = analysisHashedTextFeatureVector(
            text: "Résolution du conseil municipal sur le financement de la voirie.",
            dimension: 64
        )

        XCTAssertEqual(vector.count, 64)
        XCTAssertGreaterThan(vector.reduce(0, +), 0.99)
        XCTAssertLessThan(vector.reduce(0, +), 1.01)
    }

    func testLoadCoreMLLabelListSupportsJSONArray() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("orchiviste-coreml-labels-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("labels.json")
        try Data(#"["Resolution","ProcesVerbal","Facture"]"#.utf8).write(to: file)

        let labels = analysisLoadCoreMLLabelList(labelMapPath: file.path, labelsCSV: nil)

        XCTAssertEqual(labels, ["Resolution", "ProcesVerbal", "Facture"])
    }
}
#else
@testable import OrchivisteAnalyse

enum AnalysisMLSupportTestsPlaceholder {
    static let hashedVectorDimension: Int = {
        analysisHashedTextFeatureVector(
            text: "Résolution du conseil municipal sur le financement de la voirie.",
            dimension: 64
        ).count
    }()
}
#endif
