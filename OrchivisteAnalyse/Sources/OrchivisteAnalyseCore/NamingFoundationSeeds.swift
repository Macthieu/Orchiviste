import Foundation
import OrchivisteSharedKit

public enum NamingFoundationSeeds {
    /// Fallback de secours uniquement. Le runtime normal charge désormais les règles depuis `configs/naming/rules`.
    public static func bootstrapFallbackRules() -> [NamingRuleDefinition] {
        [bootstrapResolutionRule(), bootstrapEntenteRule()]
    }

    /// Fallback de secours uniquement. Le runtime normal charge désormais les thésaurus depuis `configs/naming/thesaurus`.
    public static func bootstrapFallbackThesaurus() -> NamingThesaurus {
        NamingThesaurus(
            thesaurus_id: "municipal-fr",
            version: "1.0.0",
            description: "Thésaurus bootstrap de secours pour l’uniformisation des noms documentaires municipaux.",
            trace: NamingThesaurusTrace(
                source: "bootstrap_fallback",
                imported_at: nil,
                imported_version: "1.0.0"
            ),
            entries: [
                NamingThesaurusEntry(
                    canonical: "Entente",
                    aliases: [
                        "entente", "contrat", "convention", "bail", "protocole", "avenant",
                        "entente d'aide financiere", "entente de soutien financier",
                        "entente relative a", "entente d'utilisation", "entente de bon voisinage"
                    ],
                    kind: "document_family",
                    normalized_output: "Entente",
                    preserve_terms: ["entente"],
                    notes: ["Uniformiser plusieurs natures documentaires vers une même forme de sortie."]
                ),
                NamingThesaurusEntry(
                    canonical: "Résolution",
                    aliases: ["resolution", "résolution", "resolution du conseil municipal"],
                    kind: "document_family",
                    normalized_output: "Résolution"
                ),
                NamingThesaurusEntry(
                    canonical: "Cadastre du Québec",
                    aliases: ["cadastre du québec", "cadastre du quebec"],
                    kind: "significant_term"
                ),
                NamingThesaurusEntry(
                    canonical: "Ville d'Amos",
                    aliases: ["ville d'amos", "ville d amos", "amos"],
                    kind: "organization"
                ),
                NamingThesaurusEntry(
                    canonical: "Bell Mobilité",
                    aliases: ["bell mobilite", "bell mobilité inc.", "bell mobilité"],
                    kind: "organization"
                )
            ],
            stopwords: [
                "le", "la", "les", "de", "du", "des", "a", "au", "aux", "d", "l",
                "ainsi", "que", "pour", "relative", "relatif", "au", "avec"
            ],
            preserve_terms: [
                "lot", "cadastre du québec", "rue", "avenue", "activite", "programme",
                "reglement", "infrastructure", "projet", "site", "construction", "permis"
            ]
        )
    }

    @available(*, deprecated, message: "Utiliser le catalogue runtime chargé depuis les fichiers de config.")
    public static func defaultRules() -> [NamingRuleDefinition] {
        bootstrapFallbackRules()
    }

    @available(*, deprecated, message: "Utiliser le catalogue runtime chargé depuis les fichiers de config.")
    public static func defaultThesaurus() -> NamingThesaurus {
        bootstrapFallbackThesaurus()
    }

    @available(*, deprecated, message: "Utiliser le catalogue runtime chargé depuis les fichiers de config.")
    public static func resolutionRule() -> NamingRuleDefinition {
        bootstrapResolutionRule()
    }

    @available(*, deprecated, message: "Utiliser le catalogue runtime chargé depuis les fichiers de config.")
    public static func ententeRule() -> NamingRuleDefinition {
        bootstrapEntenteRule()
    }

    private static func bootstrapResolutionRule() -> NamingRuleDefinition {
        NamingRuleDefinition(
            id: "rule_resolution_conseil_municipal",
            label: "Résolution du conseil municipal",
            version: "1.0.0",
            document_family: "resolution_conseil",
            template: "Résolution NO {numero} – {titre} – {date}.pdf",
            conditions: NamingRuleCondition(
                signals_any: ["résolution n°", "résolution no", "extrait du procès-verbal", "conseil municipal"],
                regex_any: [#"(?i)r[ée]solution\s*n[°o]?\s*[0-9]{4}-[0-9]{1,4}"#],
                source_document_families: ["Resolution", "ProcesVerbal"]
            ),
            fields: [
                NamingFieldDefinition(
                    key: "numero",
                    label: "Numéro",
                    required: true,
                    strategies: [
                        NamingFieldStrategy(kind: "regex", pattern: #"(?i)r[ée]solution\s*n[°o]?\s*([0-9]{4}-[0-9]{1,4})"#),
                        NamingFieldStrategy(kind: "semantic", semantic_hint: "resolution_number")
                    ]
                ),
                NamingFieldDefinition(
                    key: "titre",
                    label: "Titre",
                    required: true,
                    strategies: [
                        NamingFieldStrategy(kind: "semantic", semantic_hint: "resolution_title")
                    ]
                ),
                NamingFieldDefinition(
                    key: "date",
                    label: "Date",
                    required: true,
                    strategies: [
                        NamingFieldStrategy(kind: "semantic", semantic_hint: "adoption_date"),
                        NamingFieldStrategy(kind: "regex", pattern: #"(?i)\b(20[0-9]{2}-[01][0-9]-[0-3][0-9])\b"#)
                    ]
                )
            ],
            normalization: [
                "trim", "collapse_spaces", "separator_en_dash", "normalize_numero",
                "clean_extension_spacing", "unicode_french", "strip_technical_mentions"
            ],
            forbidden_terms: ["signé", "non signé", "OCR", "numérisé", "scanné", "version finale", "PDF/A"],
            validations: [
                NamingValidationRule(kind: "required_prefix", parameter: "Résolution NO"),
                NamingValidationRule(
                    kind: "matches_regex",
                    parameter: #"^Résolution NO\s20\d{2}-\d{1,3}\s–\s.+\s–\s20\d{2}-\d{2}-\d{2}\.pdf$"#,
                    message: "Le nom final doit respecter le format Résolution NO AAAA-N – titre – AAAA-MM-JJ.pdf."
                ),
                NamingValidationRule(kind: "max_length", parameter: "255"),
                NamingValidationRule(kind: "exclude_phrase", parameter: "Ville d'Amos")
            ],
            metadata: NamingRuleMetadata(
                suggested_class_code: "ADM-RES",
                canonical_output_label: "Résolution",
                rendering: NamingRenderingOptions(
                    title_source: "first_underlined_uppercase_line",
                    title_case: "sentence_case",
                    preserve_acronyms: ["CN", "MTQ", "SAAQ", "MRC", "SQ", "CNESST"],
                    title_max_length: 120,
                    sharepoint_safe_filename_length: 140
                ),
                notes: [
                    "Ne jamais inclure la mention Ville d'Amos dans le nom final.",
                    "Le titre doit venir du premier bloc souligné en majuscules du corps de la résolution, puis être rendu en casse phrase."
                ]
            )
        )
    }

    private static func bootstrapEntenteRule() -> NamingRuleDefinition {
        NamingRuleDefinition(
            id: "rule_entente_uniformisee",
            label: "Entente uniformisée",
            version: "1.0.0",
            document_family: "entente_uniformisee",
            template: "{cocontractant} – Entente pour {objet} – {periode}.pdf",
            conditions: NamingRuleCondition(
                signals_any: ["entente", "convention", "contrat", "bail", "protocole", "avenant"],
                regex_any: [
                    #"(?i)\b(entente|convention|contrat|bail|protocole|avenant)\b"#,
                    #"(?i)ville\s+d[' ]amos"#
                ],
                source_document_families: ["Contrat", "Autre"]
            ),
            fields: [
                NamingFieldDefinition(
                    key: "cocontractant",
                    label: "Cocontractant",
                    required: true,
                    strategies: [
                        NamingFieldStrategy(kind: "semantic", semantic_hint: "agreement_counterparty")
                    ]
                ),
                NamingFieldDefinition(
                    key: "objet",
                    label: "Objet",
                    required: true,
                    strategies: [
                        NamingFieldStrategy(
                            kind: "semantic",
                            semantic_hint: "agreement_object",
                            stopwords: ["le", "la", "les", "de", "du", "des", "à", "aux", "ainsi", "que"],
                            preserve_terms: ["lot", "cadastre du québec", "rue", "avenue", "programme", "site", "projet"]
                        )
                    ]
                ),
                NamingFieldDefinition(
                    key: "periode",
                    label: "Période",
                    required: true,
                    strategies: [
                        NamingFieldStrategy(kind: "semantic", semantic_hint: "agreement_period")
                    ]
                )
            ],
            normalization: [
                "trim", "collapse_spaces", "separator_en_dash", "strip_technical_mentions",
                "normalize_document_family", "clean_object_stopwords", "unicode_french"
            ],
            forbidden_terms: ["signé", "non signé", "OCR", "numérisé", "scanné", "version finale", "PDF/A"],
            validations: [
                NamingValidationRule(kind: "max_length", parameter: "256"),
                NamingValidationRule(kind: "required_fields", parameter: "cocontractant,objet,periode")
            ],
            metadata: NamingRuleMetadata(
                suggested_class_code: "ADM-ENT",
                canonical_output_label: "Entente"
            )
        )
    }
}
