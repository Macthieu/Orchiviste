import Foundation

enum ExamplePresets {
    static func resolution() -> Preset {
        Preset(
            id: "preset_resolution_modele",
            name: "Modele resolution",
            name_format: "{type_doc}-{date}-{numero}-{sujet}",
            class_code: "1223",
            postprocess: ["trim"],
            version: "1.0",
            description: "Exemple de preset modifiable pour des resolutions municipales.",
            detect: PresetDetect(
                signals_any: [
                    "resolution",
                    "attendu que",
                    "il est resolu",
                    "extrait du proces-verbal"
                ],
                regex_any: [
                    "(?i)\\bresolution\\b",
                    "(?i)\\battendu\\s+que\\b",
                    "(?i)\\bil\\s+est\\s+resolu\\b"
                ]
            ),
            extract: PresetExtract(
                fields: [
                    PresetExtractField(
                        key: "numero",
                        label: "Numero",
                        required: true,
                        strategies: [
                            PresetExtractStrategy(
                                kind: "regex",
                                pattern: "(?i)\\b(?:resolution|res\\.?|r)\\s*[:#-]?\\s*([0-9]{2,4}(?:[-/][0-9]{1,6})?)\\b",
                                semantic_hint: nil,
                                examples: ["2026-014", "R-2026-014"],
                                notes: ["Chercher le numero officiel de resolution."]
                            )
                        ],
                        notes: ["Ne pas inventer le numero si absent."]
                    ),
                    PresetExtractField(
                        key: "date",
                        label: "Date",
                        required: true,
                        strategies: [
                            PresetExtractStrategy(
                                kind: "regex",
                                pattern: "(?i)\\b(20\\d{2}[-/]\\d{2}[-/]\\d{2}|\\d{4}-\\d{2}-\\d{2})\\b",
                                semantic_hint: nil,
                                examples: ["2026-02-12"],
                                notes: ["Normaliser en AAAA-MM-JJ."]
                            )
                        ],
                        notes: ["Utiliser la date de la decision si disponible."]
                    ),
                    PresetExtractField(
                        key: "sujet",
                        label: "Sujet",
                        required: true,
                        strategies: [
                            PresetExtractStrategy(
                                kind: "semantic",
                                pattern: nil,
                                semantic_hint: "titre_ou_objet_de_resolution",
                                examples: ["Achat d'equipement", "Nomination d'un comite"],
                                notes: ["Deriver un sujet concis et intelligible."]
                            )
                        ],
                        notes: ["Le sujet doit rester concis et non technique."]
                    ),
                    PresetExtractField(
                        key: "organisme",
                        label: "Organisme",
                        required: false,
                        strategies: [
                            PresetExtractStrategy(
                                kind: "semantic",
                                pattern: nil,
                                semantic_hint: "organisme_emetteur_ou_signataire",
                                examples: ["Ville d'Amos"],
                                notes: ["Heuristique contextuelle."]
                            )
                        ],
                        notes: ["Champ optionnel pour enrichir la detection."]
                    )
                ]
            ),
            naming: PresetNaming(
                template: "{type_doc}-{date}-{numero}-{sujet}",
                normalization: [
                    "trim",
                    "collapse_spaces",
                    "remove_technical_mentions",
                    "max_256_chars"
                ],
                postprocess: ["trim"],
                notes: [
                    "Le nom final doit rester significatif, precis et concis.",
                    "Ne jamais inclure de mentions techniques comme signe, scanne, numerise ou PDF/A."
                ]
            ),
            classification: PresetClassification(
                suggested_class_code: "1223",
                rules: [
                    PresetClassificationRule(
                        when_signal: "resolution",
                        when_regex: "(?i)\\bresolution\\b",
                        when_type_doc: "Resolution",
                        assign_class_code: "1223",
                        notes: ["Code SyGED suggere pour proces-verbaux et resolutions du conseil."]
                    )
                ]
            ),
            export: PresetExport(
                preferred_pdf: PresetPreferredPDF(format: "PDF/A-2b", enabled: true)
            ),
            review: PresetReview(
                min_confidence: 0.78,
                required_fields: ["numero", "date", "sujet"]
            )
        )
    }
}
