import Foundation
@testable import OrchivisteAnalyseCore
import OrchivisteSharedKit

enum NamingFoundationTestsPlaceholder {
    static let resolutionValidation: (String?, String?, String?) = {
        let engine = DeclarativeNamingRuleEngine()
        let rule = NamingFoundationSeeds.resolutionRule()
        let text = """
        EXTRAIT DU PROCÈS-VERBAL D'UNE SÉANCE ORDINAIRE DU CONSEIL MUNICIPAL
        Résolution n° 2025-363
        ADJUDICATION DE CONTRAT POUR LA FOURNITURE DE VÉGÉTAUX
        15 avril 2025
        """
        let result = engine.validate(
            NamingRuleValidationRequest(
                rule: rule,
                text: text,
                metadata: NamingSourceMetadata(fileName: "source.pdf"),
                thesaurus: NamingFoundationSeeds.defaultThesaurus()
            )
        )
        return (
            result.detected_rule_id,
            result.normalized_fields["numero"],
            result.rendered_filename
        )
    }()

    static let yamlImportCanonical: String = {
        let yaml = """
        thesaurus:
          thesaurus_id: external-municipal
          version: "2026.1"
          entries:
            - canonical: Entente
              aliases:
                - contrat
                - convention
          stopwords:
            - le
            - la
          preserve_terms:
            - lot
        """
        let importer = YAMLThesaurusImporter()
        let thesaurus = try? importer.parse(data: Data(yaml.utf8), sourceName: "external.yaml")
        return thesaurus?.entries.first?.canonical ?? ""
    }()

    static let mergeConflictKind: String = {
        let preview = ThesaurusMergeService().previewMerge(
            target: NamingFoundationSeeds.defaultThesaurus(),
            imported: NamingThesaurus(
                thesaurus_id: "imported",
                version: "1",
                entries: [
                    NamingThesaurusEntry(
                        canonical: "Convention spéciale",
                        aliases: ["contrat"],
                        kind: "document_family"
                    )
                ],
                stopwords: [],
                preserve_terms: []
            ),
            strategy: .merge
        )
        return preview.conflicts.first?.kind.rawValue ?? ""
    }()

    static let learnedRuleID: String = {
        let learner = RuleLearner()
        let draft = learner.learn(
            request: RuleLearningRequest(folder_path: "/tmp/ententes", sample_size: 2, extensions: ["pdf"]),
            samples: [
                LearningDocumentSample(
                    file_name: "Bell Mobilité – Entente pour télécommunications – 2024-2026.pdf",
                    file_path: "/tmp/a.pdf",
                    file_extension: "pdf",
                    text: """
                    ENTENTE
                    entre la Ville d'Amos et Bell Mobilité
                    relative aux télécommunications
                    pour les années 2024 2025 2026
                    """
                ),
                LearningDocumentSample(
                    file_name: "Hydro-Québec – Entente pour alimentation du site – 2025.pdf",
                    file_path: "/tmp/b.pdf",
                    file_extension: "pdf",
                    text: """
                    CONTRAT
                    entre la Ville d'Amos et Hydro-Québec
                    pour l'alimentation électrique du site
                    année 2025
                    """
                )
            ],
            baseThesaurus: NamingFoundationSeeds.defaultThesaurus()
        )
        return draft.proposed_rule.id
    }()
}
