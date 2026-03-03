#if canImport(XCTest)
import XCTest
@testable import OrchivisteAnalyseCore
import OrchivisteSharedKit

final class NamingFoundationTests: XCTestCase {
    func testResolutionRuleNormalizesSentenceCaseTitleAndStructuredNumber() {
        let engine = DeclarativeNamingRuleEngine()
        let rule = NamingFoundationSeeds.bootstrapFallbackRules().first { $0.id == "rule_resolution_conseil_municipal" }!
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
                thesaurus: NamingFoundationSeeds.bootstrapFallbackThesaurus()
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
        let rule = NamingFoundationSeeds.bootstrapFallbackRules().first { $0.id == "rule_resolution_conseil_municipal" }!
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
                thesaurus: NamingFoundationSeeds.bootstrapFallbackThesaurus()
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

    func testResolutionRuleReusesMemorizedCorrectionForSameDocumentNumber() {
        let engine = DeclarativeNamingRuleEngine()
        let baseRule = NamingFoundationSeeds.bootstrapFallbackRules().first { $0.id == "rule_resolution_conseil_municipal" }!
        let correctedRule = NamingRuleDefinition(
            id: baseRule.id,
            label: baseRule.label,
            version: baseRule.version,
            document_family: baseRule.document_family,
            template: baseRule.template,
            conditions: baseRule.conditions,
            fields: baseRule.fields,
            normalization: baseRule.normalization,
            forbidden_terms: baseRule.forbidden_terms,
            validations: baseRule.validations,
            metadata: NamingRuleMetadata(
                suggested_class_code: baseRule.metadata?.suggested_class_code,
                canonical_output_label: baseRule.metadata?.canonical_output_label,
                rendering: baseRule.metadata?.rendering,
                feedback_examples: [
                    NamingFeedbackExample(
                        created_at: Date(timeIntervalSince1970: 0),
                        source_filename: "20260303-101231-31-2023_398.pdf",
                        corrected_filename: "Résolution NO 2023-398 – Adjudication de l'entente pour l'entretien d'hiver du réseau routier rural – 2023-10-16.pdf"
                    )
                ],
                notes: baseRule.metadata?.notes
            )
        )

        let rawFields = [
            "numero": "2023-398",
            "titre": "Adjudication du entente pour l'entretien d'hiver du réseau routier rural",
            "date": "2026-03-03"
        ]

        let normalized = engine.normalizeFields(
            rawFields,
            rule: correctedRule,
            thesaurus: NamingFoundationSeeds.bootstrapFallbackThesaurus()
        )
        let rendered = engine.renderFilename(rule: correctedRule, fields: normalized)

        XCTAssertEqual(
            rendered,
            "Résolution NO 2023-398 – Adjudication de l'entente pour l'entretien d'hiver du réseau routier rural – 2023-10-16.pdf"
        )
    }

    func testNamingRuleRankerScoresResolutionRuleFromLoadedCatalog() {
        let ranker = NamingRuleRanker()
        let resolution = LoadedNamingRule(
            rule_id: NamingFoundationSeeds.bootstrapFallbackRules().first { $0.id == "rule_resolution_conseil_municipal" }!.id,
            version: "1.0.0",
            status: .active,
            source: .configFile,
            definition: NamingFoundationSeeds.bootstrapFallbackRules().first { $0.id == "rule_resolution_conseil_municipal" }!
        )
        let entente = LoadedNamingRule(
            rule_id: NamingFoundationSeeds.bootstrapFallbackRules().first { $0.id == "rule_entente_uniformisee" }!.id,
            version: "1.0.0",
            status: .active,
            source: .configFile,
            definition: NamingFoundationSeeds.bootstrapFallbackRules().first { $0.id == "rule_entente_uniformisee" }!
        )
        let request = NamingPredictionRequest(
            text: """
            EXTRAIT DU PROCÈS-VERBAL D'UNE SÉANCE ORDINAIRE DU CONSEIL MUNICIPAL
            Résolution n° 2025-016
            ADJUDICATION DU CONTRAT
            """,
            metadata: NamingSourceMetadata(fileName: "resolution.pdf"),
            sample_count: 1,
            sample_file_names: ["resolution.pdf"]
        )

        let ranked = ranker.rank(request: request, candidates: [resolution, entente])

        XCTAssertEqual(ranked.first?.rule.rule_id, "rule_resolution_conseil_municipal")
        XCTAssertGreaterThan(ranked.first?.score ?? 0, 0.1)
    }

    func testRuntimeCatalogFallsBackWhenNothingIsLoaded() {
        let catalog = NamingRuntimeCatalogBuilder().build(
            activeRules: [],
            archivedRules: [],
            activeThesauri: [],
            archivedThesauri: [],
            ruleDrafts: [],
            thesaurusDrafts: [],
            feedbackRecords: []
        )

        XCTAssertTrue(catalog.fallback_active)
        XCTAssertFalse(catalog.active_rules.isEmpty)
        XCTAssertFalse(catalog.active_thesauri.isEmpty)
    }
}

#else
@testable import OrchivisteAnalyseCore
import OrchivisteSharedKit

enum NamingFoundationTestsPlaceholder {
    static let resolutionRenderedFilename: String = {
        let engine = DeclarativeNamingRuleEngine()
        let rule = NamingFoundationSeeds.bootstrapFallbackRules().first { $0.id == "rule_resolution_conseil_municipal" }!
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
                thesaurus: NamingFoundationSeeds.bootstrapFallbackThesaurus()
            )
        )
        return result.rendered_filename ?? ""
    }()
}
#endif
