#if canImport(XCTest)
import XCTest
@testable import OrchivisteAnalyseCore
import OrchivisteSharedKit
#if canImport(CoreML)
import CoreML
#endif

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

    func testEntenteRuleExtractsCounterpartyObjectAndPeriodFromPrefixedFileName() {
        let engine = DeclarativeNamingRuleEngine()
        let rule = NamingFoundationSeeds.bootstrapFallbackRules().first { $0.id == "rule_entente_uniformisee" }!
        let text = "ENTENTE"
        let metadata = NamingSourceMetadata(
            fileName: "20260304-192016-2-CATALAN,_Aurore_&_GENNARETTI,_Fabio_-_Entente_pour_installation_ruches_sur_lot_4_702_312,_cadastre_du_Quebec_-_2021-2026.pdf",
            originalName: "CATALAN, Aurore & GENNARETTI, Fabio - Entente pour installation ruches sur lot 4 702 312, cadastre du Quebec - 2021-2026.pdf"
        )

        let result = engine.validate(
            NamingRuleValidationRequest(
                rule: rule,
                text: text,
                metadata: metadata,
                thesaurus: NamingFoundationSeeds.bootstrapFallbackThesaurus()
            )
        )

        XCTAssertEqual(result.normalized_fields["cocontractant"], "CATALAN, Aurore & GENNARETTI, Fabio")
        XCTAssertEqual(result.normalized_fields["objet"], "installation ruches sur lot 4 702 312, cadastre du Quebec")
        XCTAssertEqual(result.normalized_fields["periode"], "2021-2026")
        XCTAssertEqual(
            result.rendered_filename,
            "CATALAN, Aurore & GENNARETTI, Fabio – Entente pour installation ruches sur lot 4 702 312, cadastre du Quebec – 2021-2026.pdf"
        )
    }

    func testEntenteRuleExtractsCounterpartyAndObjectFromAgreementBody() {
        let engine = DeclarativeNamingRuleEngine()
        let rule = NamingFoundationSeeds.bootstrapFallbackRules().first { $0.id == "rule_entente_uniformisee" }!
        let text = """
        ENTENTE
        ENTRE la Ville d'Amos et Entreprise autobus Plante Inc.
        Objet : Entente pour location d'autobus et service de transport guide pour Anisipi.
        Cette entente est valide pour les années 2023-2025.
        """

        let result = engine.validate(
            NamingRuleValidationRequest(
                rule: rule,
                text: text,
                metadata: NamingSourceMetadata(fileName: "entente.pdf"),
                thesaurus: NamingFoundationSeeds.bootstrapFallbackThesaurus()
            )
        )

        XCTAssertEqual(result.normalized_fields["cocontractant"], "Entreprise autobus Plante Inc")
        XCTAssertEqual(result.normalized_fields["objet"], "location d'autobus et service transport guide Anisipi")
        XCTAssertEqual(result.normalized_fields["periode"], "2023-2025")
    }

    func testEntenteRuleUsesMetadataHintsForCounterpartyObjectAndPeriod() {
        let engine = DeclarativeNamingRuleEngine()
        let rule = NamingFoundationSeeds.bootstrapFallbackRules().first { $0.id == "rule_entente_uniformisee" }!
        let metadata = NamingSourceMetadata(
            fileName: "20260304-215522-4.pdf",
            originalName: "20260304-215522-4.pdf",
            hints: [
                "objet": "Entente sur surveillance de piste cyclable",
                "organisme_emetteur": "Ville d'Amos et Vélo MRC Abitibi",
                "date_document": "15 mai\n2022"
            ]
        )

        let result = engine.validate(
            NamingRuleValidationRequest(
                rule: rule,
                text: "ENTENTE",
                metadata: metadata,
                thesaurus: NamingFoundationSeeds.bootstrapFallbackThesaurus()
            )
        )

        XCTAssertEqual(result.normalized_fields["cocontractant"], "Vélo MRC Abitibi")
        XCTAssertEqual(result.normalized_fields["periode"], "2022")
        XCTAssertTrue((result.normalized_fields["objet"] ?? "").contains("surveillance"))
        XCTAssertTrue((result.normalized_fields["objet"] ?? "").contains("piste cyclable"))
    }

    func testPermisRuleExtractsMatriculeAndPermitNumberFromFilename() {
        let engine = DeclarativeNamingRuleEngine()
        let rule = NamingFoundationSeeds.bootstrapFallbackRules().first { $0.id == "rule_permis_construction" }!
        let metadata = NamingSourceMetadata(
            fileName: "0581-88-3568 - Permis de construction NO 1959-00044.pdf",
            originalName: "0581-88-3568 - Permis de construction NO 1959-00044.pdf"
        )

        let result = engine.validate(
            NamingRuleValidationRequest(
                rule: rule,
                text: "VILLE D'AMOS DEMANDE DE PERMIS",
                metadata: metadata,
                thesaurus: NamingFoundationSeeds.bootstrapFallbackThesaurus()
            )
        )

        XCTAssertEqual(result.normalized_fields["matricule"], "0581-88-3568")
        XCTAssertEqual(result.normalized_fields["numero_permis"], "1959-00044")
        XCTAssertEqual(
            result.rendered_filename,
            "0581-88-3568 – Permis de construction NO 1959-00044.pdf"
        )
        XCTAssertFalse(result.issues.contains(where: { $0.level == .error }))
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

    func testCoreMLDefaultFeatureVectorHasExpectedShape() {
        let request = NamingPredictionRequest(
            text: """
            EXTRAIT DU PROCÈS-VERBAL D'UNE SÉANCE ORDINAIRE DU CONSEIL MUNICIPAL
            Résolution n° 2023-436
            FINANCEMENT PAR LE FONDS DE ROULEMENT
            """,
            metadata: NamingSourceMetadata(fileName: "resolution.pdf", originalName: "resolution.pdf"),
            sample_count: 3,
            sample_file_names: ["resolution-1.pdf", "resolution-2.pdf"]
        )
        let candidates = NamingFoundationSeeds.bootstrapFallbackRules().map {
            LoadedNamingRule(
                rule_id: $0.id,
                version: $0.version,
                status: .active,
                source: .configFile,
                definition: $0
            )
        }

        let vector = CoreMLNamingPredictionProvider.defaultFeatureVector(
            request: request,
            candidates: candidates,
            targetLength: 16
        )

        XCTAssertEqual(vector.count, 16)
        XCTAssertEqual(vector[9], 1.0)
        XCTAssertEqual(vector[12], 1.0)
    }

    #if canImport(CoreML)
    func testCoreMLTinyDocClassifierSmokeLoadsModelAndRanksRules() throws {
        let modelURL = namingRepositoryRoot()
            .appendingPathComponent("ml/models-coreml/tiny_doc_classifier.mlpackage")
        XCTAssertTrue(FileManager.default.fileExists(atPath: modelURL.path))

        let provider = CoreMLNamingPredictionProvider(
            modelURL: modelURL,
            vectorSize: 16
        )
        let ranker = NamingRuleRanker(
            mlScorer: NamingMLScorer(providers: [provider])
        )
        let candidates = NamingFoundationSeeds.bootstrapFallbackRules().map {
            LoadedNamingRule(
                rule_id: $0.id,
                version: $0.version,
                status: .active,
                source: .configFile,
                definition: $0
            )
        }
        let request = NamingPredictionRequest(
            text: """
            EXTRAIT DU PROCÈS-VERBAL D'UNE SÉANCE ORDINAIRE DU CONSEIL MUNICIPAL
            Résolution n° 2023-436
            FINANCEMENT PAR LE FONDS DE ROULEMENT – FINALISATION DE LA VOIRIE DE LA RUE NADON
            """,
            metadata: NamingSourceMetadata(
                fileName: "resolution-2023-436.pdf",
                originalName: "resolution-2023-436.pdf"
            ),
            sample_count: 2,
            sample_file_names: ["resolution-2023-436.pdf", "resolution-2023-437.pdf"]
        )

        let ranked = ranker.rank(request: request, candidates: candidates)

        XCTAssertFalse(ranked.isEmpty)
        XCTAssertTrue(ranked.contains(where: { $0.sources.contains("coreml") }))
    }
    #endif

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

    private func namingRepositoryRoot(filePath: StaticString = #filePath) -> URL {
        var url = URL(fileURLWithPath: "\(filePath)")
        for _ in 0..<4 {
            url.deleteLastPathComponent()
        }
        return url
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
