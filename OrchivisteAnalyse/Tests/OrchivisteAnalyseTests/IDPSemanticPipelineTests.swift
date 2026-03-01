import Foundation
@testable import OrchivisteAnalyse

enum OrchivisteAnalyseTestsPlaceholder {
    // XCTest / swift-testing ne sont pas disponibles dans cet environnement.
    // La validation fonctionnelle du pipeline est portée par scripts/smoke_analyse_semantic.sh.
    static let multiUnitReviewReasons: [String] = {
        let text = """
        RESOLUTION 2024-001
        2024-03-14
        ATTENDU QUE le conseil souhaite autoriser la depense.
        IL EST RESOLU d'autoriser le contrat.

        RESOLUTION 2024-002
        2024-03-14
        ATTENDU QUE le conseil souhaite autoriser la depense.
        IL EST RESOLU d'autoriser l'avenant.
        """
        let request = AnalysisRequest(
            file_id: "resolution-lot.pdf",
            text: text,
            source: nil,
            lang: "fr",
            hints: nil,
            preset_id: nil,
            policy: nil
        )
        return IDPSemanticPipeline.run(
            request: request,
            typeDoc: "Resolution",
            baseFields: [:]
        ).review.reasons
    }()

    static let nativeCaptureStrategy: String = {
        let request = AnalysisRequest(
            file_id: "facture-2024-009.pdf",
            text: "FACTURE FAC-2024-009\n2024-04-15\nDescription des travaux",
            source: nil,
            lang: "fr",
            hints: nil,
            preset_id: nil,
            policy: nil
        )
        return IDPSemanticPipeline.run(
            request: request,
            typeDoc: "Facture",
            baseFields: ["numero": "FAC-2024-009", "date": "2024-04-15"]
        ).captureStrategy
    }()
}
