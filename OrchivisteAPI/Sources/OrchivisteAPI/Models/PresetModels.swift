import Foundation
import Vapor

struct PresetDetect: Content, Codable {
    let signals_any: [String]?
    let regex_any: [String]?
}

struct PresetExtractStrategy: Content, Codable {
    let kind: String
    let pattern: String?
    let semantic_hint: String?
    let examples: [String]?
    let notes: [String]?
}

struct PresetExtractField: Content, Codable {
    let key: String
    let label: String?
    let required: Bool?
    let strategies: [PresetExtractStrategy]
    let notes: [String]?
}

struct PresetExtract: Content, Codable {
    let fields: [PresetExtractField]
}

struct PresetNaming: Content, Codable {
    let template: String
    let normalization: [String]?
    let postprocess: [String]?
    let notes: [String]?
}

struct PresetClassificationRule: Content, Codable {
    let when_signal: String?
    let when_regex: String?
    let when_type_doc: String?
    let assign_class_code: String?
    let notes: [String]?
}

struct PresetClassification: Content, Codable {
    let suggested_class_code: String?
    let rules: [PresetClassificationRule]?
}

struct PresetPreferredPDF: Content, Codable {
    let format: String?
    let enabled: Bool?
}

struct PresetExport: Content, Codable {
    let preferred_pdf: PresetPreferredPDF?
}

struct PresetReview: Content, Codable {
    let min_confidence: Double?
    let required_fields: [String]?
}

struct Preset: Content, Codable {
    let id: String
    let name: String
    let name_format: String
    let class_code: String?
    let postprocess: [String]?
    let version: String?
    let description: String?
    let detect: PresetDetect?
    let extract: PresetExtract?
    let naming: PresetNaming?
    let classification: PresetClassification?
    let export: PresetExport?
    let review: PresetReview?

    enum CodingKeys: String, CodingKey {
        case id
        case preset_id
        case name
        case name_format
        case class_code
        case postprocess
        case version
        case description
        case detect
        case extract
        case naming
        case classification
        case export
        case review
    }

    init(
        id: String,
        name: String,
        name_format: String,
        class_code: String?,
        postprocess: [String]?,
        version: String? = nil,
        description: String? = nil,
        detect: PresetDetect? = nil,
        extract: PresetExtract? = nil,
        naming: PresetNaming? = nil,
        classification: PresetClassification? = nil,
        export: PresetExport? = nil,
        review: PresetReview? = nil
    ) {
        self.id = id
        self.name = name
        self.name_format = name_format
        self.class_code = class_code ?? classification?.suggested_class_code
        self.postprocess = postprocess ?? naming?.postprocess
        self.version = version
        self.description = description
        self.detect = detect
        self.extract = extract
        self.naming = naming
        self.classification = classification
        self.export = export
        self.review = review
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let naming = try container.decodeIfPresent(PresetNaming.self, forKey: .naming)
        let classification = try container.decodeIfPresent(PresetClassification.self, forKey: .classification)

        let decodedID = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .preset_id)
            ?? ""
        let decodedDescription = try container.decodeIfPresent(String.self, forKey: .description)

        id = decodedID
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? decodedDescription
            ?? decodedID
        name_format = try container.decodeIfPresent(String.self, forKey: .name_format)
            ?? naming?.template
            ?? "{type_doc}-{date}-{numero}"
        class_code = try container.decodeIfPresent(String.self, forKey: .class_code)
            ?? classification?.suggested_class_code
        postprocess = try container.decodeIfPresent([String].self, forKey: .postprocess)
            ?? naming?.postprocess
        version = try container.decodeIfPresent(String.self, forKey: .version)
        description = decodedDescription
        detect = try container.decodeIfPresent(PresetDetect.self, forKey: .detect)
        extract = try container.decodeIfPresent(PresetExtract.self, forKey: .extract)
        self.naming = naming
        self.classification = classification
        export = try container.decodeIfPresent(PresetExport.self, forKey: .export)
        review = try container.decodeIfPresent(PresetReview.self, forKey: .review)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(id, forKey: .preset_id)
        try container.encode(name, forKey: .name)
        try container.encode(name_format, forKey: .name_format)
        try container.encodeIfPresent(class_code, forKey: .class_code)
        try container.encodeIfPresent(postprocess, forKey: .postprocess)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(detect, forKey: .detect)
        try container.encodeIfPresent(extract, forKey: .extract)
        try container.encodeIfPresent(
            naming ?? PresetNaming(
                template: name_format,
                normalization: nil,
                postprocess: postprocess,
                notes: nil
            ),
            forKey: .naming
        )
        try container.encodeIfPresent(
            classification ?? PresetClassification(
                suggested_class_code: class_code,
                rules: nil
            ),
            forKey: .classification
        )
        try container.encodeIfPresent(export, forKey: .export)
        try container.encodeIfPresent(review, forKey: .review)
    }
}

struct PresetLearnRequest: Content {
    let folder_path: String
    let sample_size: Int?
    let extensions: [String]?
}

struct PresetLearnSuggestedField: Content {
    let key: String
    let confidence: Double
    let strategies: [PresetExtractStrategy]
    let notes: [String]
}

struct PresetLearnExampleRename: Content {
    let before: String
    let after: String?
}

struct PresetLearnReport: Content {
    let scanned_files: Int
    let sampled_files: Int
    let extensions: [String]
    let detected_tokens: [String]
    let document_types: [String]
    let structure_hints: [String]
    let suggested_fields: [PresetLearnSuggestedField]
    let proposed_name_template: String?
    let normalization_rules: [String]
    let examples_before_after: [PresetLearnExampleRename]
    let warnings: [String]
}

struct PresetLearnResponse: Content {
    let preset: Preset
    let saved_path: String
    let confidence: Double
    let needs_review: Bool
    let report: PresetLearnReport
}
