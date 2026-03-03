#if canImport(XCTest)
import XCTest
@testable import OrchivisteAnalyseCore
import OrchivisteSharedKit

final class NamingFoundationTests: XCTestCase {
    func testResolutionRuleNormalizesSentenceCaseTitleAndStructuredNumber() {
        let engine = DeclarativeNamingRuleEngine()
        let rule = NamingFoundationSeeds.resolutionRule()
        let text = """
        EXTRAIT DU PROCÈS-VERBAL D'UNE SÉANCE ORDINAIRE DU CONSEIL MUNICIPAL
        Résolution n° 2025-016
        ADJUDICATION DU CONTRAT POUR LA FOURNITURE DES VÉGÉTAUX REQUIS POUR L'AMÉNAGEMENT DES ESPACES VERTS 2024
        lundi 2 mars 2026
        """

        let result = engine.validate(
            NamingRuleValidationRequest(
                rule: rule,
                text: text,
                metadata: NamingSourceMetadata(fileName: "resolution.pdf"),
                thesaurus: NamingFoundationSeeds.defaultThesaurus()
            )
        )

        XCTAssertEqual(result.detected_rule_id, "rule_resolution_conseil_municipal")
        XCTAssertEqual(result.normalized_fields["numero"], "2025-16")
        XCTAssertEqual(result.normalized_fields["date"], "2026-03-02")
        XCTAssertEqual(
            result.normalized_fields["titre"],
            "Adjudication du contrat pour la fourniture des végétaux requis pour l'aménagement des espaces verts 2024"
        )
        XCTAssertEqual(
            result.rendered_filename,
            "Résolution NO 2025-16 – Adjudication du contrat pour la fourniture des végétaux requis pour l'aménagement des espaces verts 2024 – 2026-03-02.pdf"
        )
        XCTAssertFalse(result.issues.contains(where: { $0.level == .error }))
    }

    func testResolutionRuleDoesNotTreatSubjectsAsTitle() {
        let engine = DeclarativeNamingRuleEngine()
        let rule = NamingFoundationSeeds.resolutionRule()
        let text = """
        resolution.pdf
        Resolution
        financement, voirie, Decision, Gouvernance
        Résolution n° 2023-436
        FINANCEMENT PAR LE FONDS DE ROULEMENT – FINALISATION DE LA VOIRIE DE LA RUE
        NADON
        lundi 20 novembre 2023
        """

        let result = engine.validate(
            NamingRuleValidationRequest(
                rule: rule,
                text: text,
                metadata: NamingSourceMetadata(fileName: "resolution.pdf"),
                thesaurus: NamingFoundationSeeds.defaultThesaurus()
            )
        )

        XCTAssertEqual(
            result.normalized_fields["titre"],
            "Financement par le fonds de roulement – finalisation de la voirie de la rue Nadon"
        )
        XCTAssertEqual(
            result.rendered_filename,
            "Résolution NO 2023-436 – Financement par le fonds de roulement – finalisation de la voirie de la rue Nadon – 2023-11-20.pdf"
        )
    }
}

#else
@testable import OrchivisteAnalyseCore
import OrchivisteSharedKit

enum NamingFoundationTestsPlaceholder {
    static let resolutionRenderedFilename: String = {
        let engine = DeclarativeNamingRuleEngine()
        let rule = NamingFoundationSeeds.resolutionRule()
        let text = """
        EXTRAIT DU PROCÈS-VERBAL D'UNE SÉANCE ORDINAIRE DU CONSEIL MUNICIPAL
        Résolution n° 2023-394
        ADJUDICATION DU CONTRAT POUR LA FOURNITURE DES VÉGÉTAUX REQUIS POUR L'AMÉNAGEMENT DES ESPACES VERTS 2024
        lundi 2 mars 2026
        """

        let result = engine.validate(
            NamingRuleValidationRequest(
                rule: rule,
                text: text,
                metadata: NamingSourceMetadata(fileName: "resolution.pdf"),
                thesaurus: NamingFoundationSeeds.defaultThesaurus()
            )
        )
        return result.rendered_filename ?? ""
    }()
}
#endif
