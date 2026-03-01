import Foundation
import Vapor

private struct UIDashboardContext: Encodable {
    let total_jobs: Int
    let pending_jobs: Int
    let running_jobs: Int
    let needs_review_jobs: Int
    let completed_jobs: Int
    let failed_jobs: Int
    let cancelled_jobs: Int
    let worker_count: Int
    let queue_ingest_depth: Int
    let queue_dead_letter_depth: Int
    let recent_jobs: [UIJobSummary]
    let recent_jobs_empty: Bool
    let recent_jobs_present: Bool
    let recent_jobs_cleared: Bool
    let recent_total_jobs: Int
    let recent_pending_jobs: Int
    let recent_running_jobs: Int
    let recent_needs_review_jobs: Int
    let recent_completed_jobs: Int
    let recent_failed_jobs: Int
    let recent_cancelled_jobs: Int
    let dashboard_has_active_processing: Bool
    let dashboard_auto_refresh_seconds: Int
    let dashboard_notice: String?
    let dashboard_error: String?
    let upload_notice: String?
    let upload_error: String?
    let ingest_default_input_folder: String
    let ingest_default_output_folder: String
}

private struct UIJobsContext: Encodable {
    let jobs: [UIJobSummary]
}

private struct UISetupContext: Encodable {
    let ingest_default_input_folder: String
    let routing_local_route_root: String
    let routing_default_destination_template: String
    let routing_default_name_format: String
    let renaming_guide: String
    let taxonomy_ids: [String]
    let notice: String?
    let error: String?
}

private struct UIWorkersContext: Encodable {
    let workers: [UIWorkerSummary]
    let queue_ingest_depth: Int
    let queue_dead_letter_depth: Int
    let notice: String?
    let error: String?
}

private struct UIPresetsContext: Encodable {
    let presets: [UIPresetSummary]
    let routing_local_route_root: String
    let routing_default_destination_template: String
    let routing_default_name_format: String
    let routing_rules: [UIRoutingRuleSummary]
    let routing_rules_json: String
    let taxonomy_ids: [String]
    let selected_taxonomy_id: String?
    let selected_taxonomy_json: String
    let notice: String?
    let error: String?
}

private struct UIEventsContext: Encodable {
    let events: [UIEventSummary]
    let initial_cursor: Int
}

private struct UIEventSummary: Encodable {
    let id: Int
    let type: String
    let created_at: String
    let payload: String
}

private struct UIJobSummary: Encodable {
    let id: String
    let status: String
    let status_label: String
    let file_url: String
    let source_kind: String
    let confidence: String
    let suggested_class_code: String
    let ocr_ok: String
    let resolved_file_name: String
    let metadata_ok: String
    let saved_folder_path: String
    let updated_at: String
}

private struct UIWorkerSummary: Encodable {
    let id: String
    let name: String
    let status_raw: String
    let status: String
    let capabilities: String
    let has_coreml: Bool
    let last_seen: String
    let version: String
    let load: String
    let ram_mb: String
    let can_approve: Bool
    let can_heartbeat: Bool
    let can_pause: Bool
    let can_resume: Bool
}

private struct UIPresetSummary: Encodable {
    let id: String
    let name: String
    let name_format: String
    let class_code: String
    let postprocess: String
}

private struct UIRoutingRuleSummary: Encodable {
    let id: String
    let when_type_doc: String
    let when_sujet: String
    let when_class_code: String
    let class_code: String
    let preset_id: String
    let destination_template: String
    let name_format: String
}

private struct UIJobViewerContext: Encodable {
    let id: String
    let status: String
    let file_url: String
    let source_kind: String
    let suggested_preset: String
    let suggested_class_code: String
    let confidence: String
    let needs_review: Bool
    let can_review: Bool
    let can_route: Bool
    let route_disabled_reason: String?
    let routed_at: String?
    let preview_pages: Int
    let download_url: String
    let download_searchable_url: String
    let analysis_type_doc: String
    let analysis_sujets: String
    let analysis_capture_strategy: String
    let analysis_review_reasons: String
    let analysis_champs_json: String
    let analysis_validation_flags: String
    let class_code_options: [String]
    let preset_options: [String]
    let suggested_class_code_raw: String?
    let suggested_preset_raw: String?
}

private struct UILocalIngestForm: Content {
    let pdf: File?
    let server_file: String?
    let tags: String?
}

private struct UIFolderIngestForm: Content {
    let input_folder: String?
    let tags: String?
    let recursive: String?
    let max_files: String?
    let output_root: String?
    let folder_files: [File]

    private enum CodingKeys: String, CodingKey {
        case input_folder
        case tags
        case recursive
        case max_files
        case output_root
        case folder_files
    }

    init(
        input_folder: String? = nil,
        tags: String? = nil,
        recursive: String? = nil,
        max_files: String? = nil,
        output_root: String? = nil,
        folder_files: [File] = []
    ) {
        self.input_folder = input_folder
        self.tags = tags
        self.recursive = recursive
        self.max_files = max_files
        self.output_root = output_root
        self.folder_files = folder_files
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input_folder = try container.decodeIfPresent(String.self, forKey: .input_folder)
        tags = try container.decodeIfPresent(String.self, forKey: .tags)
        recursive = try container.decodeIfPresent(String.self, forKey: .recursive)
        max_files = try container.decodeIfPresent(String.self, forKey: .max_files)
        output_root = try container.decodeIfPresent(String.self, forKey: .output_root)

        if let multiple = try? container.decode([File].self, forKey: .folder_files) {
            folder_files = multiple
        } else if let single = try? container.decode(File.self, forKey: .folder_files) {
            folder_files = [single]
        } else {
            folder_files = []
        }
    }
}

private struct UIPresetCreateForm: Content {
    let id: String
    let name: String
    let name_format: String
    let class_code: String?
    let postprocess: String?
}

private struct UIPresetLearnForm: Content {
    let folder_path: String?
    let sample_size: String?
    let extensions: String?
}

private struct UIRoutingSettingsForm: Content {
    let local_route_root: String?
    let default_destination_template: String?
    let default_name_format: String?
}

private struct UIRoutingRulesForm: Content {
    let rules_json: String
}

private struct UIRoutingGuideForm: Content {
    let guide_text: String
}

private struct UIRoutingRuleCreateForm: Content {
    let id: String?
    let when_type_doc: String?
    let when_sujet: String?
    let when_class_code: String?
    let class_code: String?
    let preset_id: String?
    let destination_template: String?
    let name_format: String?
}

private struct UIRoutingRuleSuggestForm: Content {
    let input_folder: String?
    let input_file_names: String?
    let when_type_doc: String?
    let when_sujet: String?
    let preset_id: String?
    let max_files: String?
}

private struct UITaxonomyImportForm: Content {
    let taxonomy_id: String?
    let taxonomy_json: String
}

private struct UITaxonomyImportPDFForm: Content {
    let taxonomy_id: String?
    let pdf: File
}

private struct UIFolderListEntry: Content {
    let name: String
    let path: String
}

private struct UIFolderListResponse: Content {
    let current: String
    let parent: String?
    let roots: [String]
    let directories: [UIFolderListEntry]
    let files: [UIFolderListEntry]
}

private struct UIWorkerEnrollForm: Content {
    let name: String
    let capabilities: String?
}

private struct UIWorkerHeartbeatForm: Content {
    let version: String?
    let load: String?
    let ram_mb: String?
    let capabilities: String?
}

private struct UIWorkerConfigForm: Content {
    let version: String?
    let capabilities: String?
}

func registerUIRoutes(_ app: Application) {
    app.get { req async throws -> Response in
        req.redirect(to: "/ui")
    }

    app.get("u") { req async throws -> Response in
        req.redirect(to: "/ui")
    }
    app.get("u", "jobs") { req async throws -> Response in
        req.redirect(to: "/ui/jobs")
    }
    app.get("u", "workers") { req async throws -> Response in
        req.redirect(to: "/ui/workers")
    }
    app.get("u", "setup") { req async throws -> Response in
        req.redirect(to: "/ui/setup")
    }
    app.get("u", "presets") { req async throws -> Response in
        req.redirect(to: "/ui/presets")
    }
    app.get("u", "events") { req async throws -> Response in
        req.redirect(to: "/ui/events")
    }
    app.get("u", "jobs", ":id") { req async throws -> Response in
        guard let id = req.parameters.get("id") else {
            return req.redirect(to: "/ui/jobs")
        }
        return req.redirect(to: "/ui/jobs/\(id)")
    }

    app.get("ui", "fs", "list") { req async throws -> UIFolderListResponse in
        let roots = uiFolderPickerRoots()
        let requestedPath = req.query[String.self, at: "path"]
        let current = try resolveFolderPickerPath(requestedPath, roots: roots)
        let manager = FileManager.default

        let directories: [UIFolderListEntry]
        let files: [UIFolderListEntry]
        do {
            let items = try manager.contentsOfDirectory(
                at: current,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            directories = items
                .compactMap { url -> UIFolderListEntry? in
                    let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    guard isDirectory else { return nil }
                    return UIFolderListEntry(name: url.lastPathComponent, path: url.path)
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .prefix(250)
                .map { $0 }
            files = items
                .compactMap { url -> UIFolderListEntry? in
                    let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    guard !isDirectory, isSupportedIngestFileName(url.lastPathComponent) else { return nil }
                    return UIFolderListEntry(name: url.lastPathComponent, path: url.path)
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .prefix(250)
                .map { $0 }
        } catch {
            throw Abort(.badRequest, reason: "Impossible de lire ce dossier: \(error.localizedDescription)")
        }

        let parentURL = current.deletingLastPathComponent()
        let parentPath = roots.contains(where: { current.path == $0.path }) ? nil : parentURL.path
        return UIFolderListResponse(
            current: current.path,
            parent: parentPath,
            roots: roots.map(\.path),
            directories: directories,
            files: files
        )
    }

    app.on(.POST, "ui", "ingest", "local", body: .collect(maxSize: "48mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UILocalIngestForm.self)
            let parsedTags = parseUploadTags(raw: form.tags)
            let destinationPath: String
            if let uploadedFile = form.pdf, uploadedFile.data.readableBytes > 0 {
                let filename = uploadedFile.filename.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !filename.isEmpty else {
                    throw Abort(.badRequest, reason: "Aucun fichier fourni.")
                }
                guard isSupportedIngestFileName(filename) else {
                    throw Abort(.badRequest, reason: "Format non supporte. Utilise PDF, DOCX, XLSX, PPTX, PNG, JPG ou TIFF.")
                }

                let inboxDirectory = resolveUILocalIngestInboxDirectory()
                try FileManager.default.createDirectory(
                    at: inboxDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )

                let safeName = sanitizeUploadFileName(filename)
                let timestamp = formatUploadTimestamp(Date())
                let destination = inboxDirectory.appendingPathComponent("\(timestamp)-\(safeName)")
                try Data(buffer: uploadedFile.data).write(to: destination, options: .atomic)
                destinationPath = destination.path
            } else if let serverFilePath = nonEmptyString(form.server_file) {
                let serverURL = URL(fileURLWithPath: serverFilePath)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: serverURL.path, isDirectory: &isDirectory),
                      !isDirectory.boolValue else {
                    throw Abort(.badRequest, reason: "Le fichier serveur sélectionné est introuvable.")
                }
                guard isSupportedIngestFileName(serverURL.lastPathComponent) else {
                    throw Abort(.badRequest, reason: "Format non supporte. Utilise PDF, DOCX, XLSX, PPTX, PNG, JPG ou TIFF.")
                }
                destinationPath = serverURL.path
            } else {
                throw Abort(.badRequest, reason: "Choisis un fichier local ou un fichier serveur.")
            }

            let requestBody = IngestRequest(
                fileURL: destinationPath,
                source: JobSource(kind: "local", url: nil, site: nil, library: nil, itemId: nil),
                tags: parsedTags.isEmpty ? nil : parsedTags,
                hints: nil
            )
            let taskId = try await enqueueIngest(
                body: requestBody,
                idempotencyKey: "ui-upload-\(UUID().uuidString)",
                req: req
            )
            return req.redirect(to: "/ui/jobs/\(taskId.uuidString)")
        } catch let abort as AbortError {
            let reason = abort.reason.isEmpty ? "Echec de l'import du document." : abort.reason
            req.logger.warning("Échec ingestion UI.", metadata: [
                "reason": .string(reason)
            ])
            return req.redirect(to: "/ui?upload_error=\(urlQueryEncoded(reason))")
        } catch {
            req.logger.error("Échec ingestion UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui?upload_error=\(urlQueryEncoded("Erreur interne pendant l'import du document."))")
        }
    }

    app.on(.POST, "ui", "ingest", "folder", body: .collect(maxSize: "512mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UIFolderIngestForm.self)
            let inputFolderRaw = nonEmptyString(form.input_folder)
            let recursive = parseBooleanFlag(form.recursive, defaultValue: true)
            let maxFiles = parseMaxFiles(form.max_files)
            let tags = parseUploadTags(raw: form.tags)
            let uploadedFolderFiles = form.folder_files

            var files: [URL] = []
            var sourceLabel = "dossier serveur"

            if let inputFolderRaw {
                let inputURL = URL(fileURLWithPath: inputFolderRaw, isDirectory: true)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    throw Abort(.badRequest, reason: "Le dossier d'entrée est introuvable sur le serveur API.")
                }
                files = try collectSupportedDocumentFiles(in: inputURL, recursive: recursive, maxFiles: maxFiles)
                guard !files.isEmpty else {
                    throw Abort(.badRequest, reason: "Aucun document supporte trouve dans le dossier d'entree.")
                }
            } else if !uploadedFolderFiles.isEmpty {
                let supportedFiles = uploadedFolderFiles.filter {
                    isSupportedIngestFileName($0.filename) && $0.data.readableBytes > 0
                }
                guard !supportedFiles.isEmpty else {
                    throw Abort(.badRequest, reason: "Aucun document valide trouve dans le dossier local.")
                }
                guard supportedFiles.count <= maxFiles else {
                    throw Abort(
                        .badRequest,
                        reason: "Le dossier local contient \(supportedFiles.count) documents. Reduis la selection ou augmente la limite."
                    )
                }

                let inboxDirectory = resolveUILocalIngestInboxDirectory()
                try FileManager.default.createDirectory(
                    at: inboxDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )

                let timestamp = formatUploadTimestamp(Date())
                for (index, file) in supportedFiles.enumerated() {
                    let safeName = sanitizeUploadFileName(file.filename)
                    let destination = inboxDirectory.appendingPathComponent("\(timestamp)-\(index + 1)-\(safeName)")
                    try Data(buffer: file.data).write(to: destination, options: .atomic)
                    files.append(destination)
                }
                sourceLabel = "ton ordinateur"
            } else {
                throw Abort(.badRequest, reason: "Sélectionne un dossier serveur ou choisis un dossier local.")
            }

            if let outputRoot = nonEmptyString(form.output_root) {
                let existing = ConfigLoader.loadRoutingLocalSettings()
                let merged = RoutingLocalSettings(
                    local_route_root: outputRoot,
                    default_destination_template: existing?.default_destination_template,
                    default_name_format: existing?.default_name_format
                )
                try ConfigLoader.saveRoutingLocalSettings(merged)
            }

            var ingested = 0
            for file in files {
                let requestBody = IngestRequest(
                    fileURL: file.path,
                    source: JobSource(kind: "local", url: nil, site: nil, library: nil, itemId: nil),
                    tags: tags.isEmpty ? nil : tags,
                    hints: nil
                )
                let idempotency = buildFolderIngestIdempotencyKey(fileURL: file)
                _ = try await enqueueIngest(
                    body: requestBody,
                    idempotencyKey: idempotency,
                    req: req
                )
                ingested += 1
            }

            let notice = "\(ingested) document(s) ajoute(s) depuis \(sourceLabel)."
            return req.redirect(to: "/ui?upload_notice=\(urlQueryEncoded(notice))#recent-jobs")
        } catch let abort as AbortError {
            return req.redirect(to: "/ui?upload_error=\(urlQueryEncoded(abort.reason))")
        } catch {
            req.logger.error("Échec ingestion dossier UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui?upload_error=\(urlQueryEncoded("Erreur interne pendant l'import du dossier."))")
        }
    }

    app.post("ui", "dashboard", "recent-jobs", "clear") { req async throws -> Response in
        do {
            let current = ConfigLoader.loadDashboardState() ?? UIDashboardState(recent_jobs_cleared_at: nil)
            let updated = UIDashboardState(recent_jobs_cleared_at: Date())
            if current.recent_jobs_cleared_at != updated.recent_jobs_cleared_at {
                try ConfigLoader.saveDashboardState(updated)
            }
            return req.redirect(to: "/ui?dashboard_notice=\(urlQueryEncoded("La liste des tâches récentes a été vidée."))")
        } catch {
            req.logger.error("Échec vidage liste tâches récentes UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui?dashboard_error=\(urlQueryEncoded("Erreur interne pendant le vidage de la liste."))")
        }
    }

    app.post("ui", "dashboard", "recent-jobs", "reset") { req async throws -> Response in
        do {
            try ConfigLoader.saveDashboardState(UIDashboardState(recent_jobs_cleared_at: nil))
            return req.redirect(to: "/ui?dashboard_notice=\(urlQueryEncoded("La liste complète des tâches récentes est réaffichée."))")
        } catch {
            req.logger.error("Échec réinitialisation liste tâches récentes UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui?dashboard_error=\(urlQueryEncoded("Erreur interne pendant la réinitialisation de la liste."))")
        }
    }

    app.on(.POST, "ui", "presets", body: .collect(maxSize: "1mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UIPresetCreateForm.self)
            let preset = Preset(
                id: form.id.trimmingCharacters(in: .whitespacesAndNewlines),
                name: form.name.trimmingCharacters(in: .whitespacesAndNewlines),
                name_format: form.name_format.trimmingCharacters(in: .whitespacesAndNewlines),
                class_code: nonEmptyString(form.class_code),
                postprocess: parseUploadTags(raw: form.postprocess)
            )
            try validatePreset(preset)
            await req.application.appState.upsertPreset(preset)
            try ConfigLoader.savePreset(preset)
            return req.redirect(to: "/ui/presets?notice=\(urlQueryEncoded("Préréglage enregistré."))")
        } catch let abort as AbortError {
            let reason = abort.reason.isEmpty ? "Échec de création du préréglage." : abort.reason
            return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded(reason))")
        } catch {
            req.logger.error("Échec création préréglage UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded("Erreur interne pendant la création du préréglage."))")
        }
    }

    app.on(.POST, "ui", "presets", "learn", body: .collect(maxSize: "1mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UIPresetLearnForm.self)
            guard let folderPath = nonEmptyString(form.folder_path) else {
                throw Abort(.badRequest, reason: "Le chemin du dossier source est requis.")
            }
            let extensions = parseUploadTags(raw: form.extensions)
            let response = try PresetLearningService.learn(
                request: PresetLearnRequest(
                    folder_path: folderPath,
                    sample_size: parseOptionalInt(form.sample_size),
                    extensions: extensions.isEmpty ? nil : extensions
                ),
                logger: req.logger
            )
            await req.application.appState.upsertPreset(response.preset)
            let statusLabel = response.needs_review ? "needs_review" : "ok"
            let notice = "Preset draft sauvegarde: \(response.saved_path) (confidence \(String(format: "%.2f", response.confidence)), \(statusLabel))."
            return req.redirect(to: "/ui/presets?notice=\(urlQueryEncoded(notice))")
        } catch let abort as AbortError {
            let reason = abort.reason.isEmpty ? "Echec de l'apprentissage du preset." : abort.reason
            return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded(reason))")
        } catch {
            req.logger.error("Échec apprentissage preset UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded("Erreur interne pendant l'apprentissage du preset."))")
        }
    }

    app.on(.POST, "ui", "routing", "settings", body: .collect(maxSize: "1mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UIRoutingSettingsForm.self)
            let settings = RoutingLocalSettings(
                local_route_root: nonEmptyString(form.local_route_root),
                default_destination_template: nonEmptyString(form.default_destination_template),
                default_name_format: nonEmptyString(form.default_name_format)
            )
            try ConfigLoader.saveRoutingLocalSettings(settings)
            return req.redirect(to: "/ui/presets?notice=\(urlQueryEncoded("Paramètres de routage enregistrés."))")
        } catch let abort as AbortError {
            let reason = abort.reason.isEmpty ? "Échec de sauvegarde des paramètres de routage." : abort.reason
            return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded(reason))")
        } catch {
            req.logger.error("Échec sauvegarde paramètres de routage UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded("Erreur interne pendant l'enregistrement des paramètres de routage."))")
        }
    }

    app.on(.POST, "ui", "routing", "rules", body: .collect(maxSize: "2mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UIRoutingRulesForm.self)
            let raw = form.rules_json.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else {
                throw Abort(.badRequest, reason: "Le JSON des règles ne peut pas être vide.")
            }
            try ConfigLoader.saveRoutingRulesRawJSON(raw)
            return req.redirect(to: "/ui/presets?notice=\(urlQueryEncoded("Règles type/sujet enregistrées."))")
        } catch let abort as AbortError {
            let reason = abort.reason.isEmpty ? "Échec de sauvegarde des règles type/sujet." : abort.reason
            return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded(reason))")
        } catch {
            req.logger.error("Échec sauvegarde règles type/sujet UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded("JSON invalide ou erreur interne pendant l'enregistrement des règles."))")
        }
    }

    app.on(.POST, "ui", "routing", "guide", body: .collect(maxSize: "2mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UIRoutingGuideForm.self)
            let guide = form.guide_text.trimmingCharacters(in: .newlines)
            guard !guide.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw Abort(.badRequest, reason: "Le guide de renommage ne peut pas être vide.")
            }
            try ConfigLoader.saveRenamingGuide(guide + "\n")
            return req.redirect(to: "/ui/setup?notice=\(urlQueryEncoded("Guide de renommage enregistré."))")
        } catch let abort as AbortError {
            return req.redirect(to: "/ui/setup?error=\(urlQueryEncoded(abort.reason))")
        } catch {
            req.logger.error("Échec enregistrement guide renommage UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui/setup?error=\(urlQueryEncoded("Erreur interne pendant l'enregistrement du guide."))")
        }
    }

    app.on(.POST, "ui", "routing", "rules", "create", body: .collect(maxSize: "1mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UIRoutingRuleCreateForm.self)
            let whenTypeDoc = nonEmptyString(form.when_type_doc)
            let whenSujet = nonEmptyString(form.when_sujet)
            let whenClassCode = nonEmptyString(form.when_class_code)
            let classCode = nonEmptyString(form.class_code)
            let presetID = nonEmptyString(form.preset_id)
            let destinationTemplate = nonEmptyString(form.destination_template)
            let nameFormat = nonEmptyString(form.name_format)

            guard whenTypeDoc != nil || whenSujet != nil || whenClassCode != nil else {
                throw Abort(.badRequest, reason: "Ajouter au moins un critère (type, sujet ou code).")
            }
            guard classCode != nil || presetID != nil || destinationTemplate != nil || nameFormat != nil else {
                throw Abort(.badRequest, reason: "Ajouter au moins une action (code, preset, dossier ou format).")
            }

            let providedID = nonEmptyString(form.id)
            let computedID = buildRoutingRuleID(
                explicit: providedID,
                whenTypeDoc: whenTypeDoc,
                whenSujet: whenSujet,
                whenClassCode: whenClassCode
            )

            let rule = RoutingRule(
                id: computedID,
                when_type_doc: whenTypeDoc,
                when_sujet: whenSujet,
                when_class_code: whenClassCode,
                class_code: classCode,
                preset_id: presetID,
                destination_template: destinationTemplate,
                name_format: nameFormat
            )

            var existing = ConfigLoader.loadRoutingRules()?.rules ?? []
            if let index = existing.firstIndex(where: { nonEmptyString($0.id) == computedID }) {
                existing[index] = rule
            } else {
                existing.append(rule)
            }

            try ConfigLoader.saveRoutingRules(RoutingRuleSet(rules: existing))
            return req.redirect(to: "/ui/presets?notice=\(urlQueryEncoded("Règle type/sujet enregistrée."))")
        } catch let abort as AbortError {
            let reason = abort.reason.isEmpty ? "Échec de sauvegarde de la règle." : abort.reason
            return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded(reason))")
        } catch {
            req.logger.error("Échec création règle type/sujet UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded("Erreur interne pendant l'enregistrement de la règle."))")
        }
    }

    app.on(.POST, "ui", "routing", "rules", "suggest", body: .collect(maxSize: "1mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UIRoutingRuleSuggestForm.self)
            let maxFiles = parseMaxFiles(form.max_files)
            let folderRaw = nonEmptyString(form.input_folder)
            let localSubmittedNames = parseSubmittedPDFNames(form.input_file_names)

            let sampleNames: [String]
            let folderLabel: String
            if let folderRaw {
                let folderURL = URL(fileURLWithPath: folderRaw, isDirectory: true)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    throw Abort(.badRequest, reason: "Le dossier source est introuvable.")
                }
                sampleNames = try collectPDFFiles(in: folderURL, recursive: false, maxFiles: maxFiles)
                    .map(\.lastPathComponent)
                guard !sampleNames.isEmpty else {
                    throw Abort(.badRequest, reason: "Aucun PDF trouvé dans le dossier source.")
                }
                folderLabel = folderURL.lastPathComponent
            } else if !localSubmittedNames.isEmpty {
                sampleNames = Array(localSubmittedNames.prefix(maxFiles)).map {
                    URL(fileURLWithPath: $0).lastPathComponent
                }
                guard !sampleNames.isEmpty else {
                    throw Abort(.badRequest, reason: "Aucun PDF local valide n'a été transmis.")
                }
                folderLabel = inferSubmittedFolderLabel(from: localSubmittedNames) ?? "dossier-local"
            } else {
                throw Abort(.badRequest, reason: "Le dossier source est requis (serveur ou local).")
            }

            let inferredClassCode = inferClassCodeFromFileNames(sampleNames)
            let ruleID = sanitizeRoutingRuleID("auto-\(folderLabel)")
            let whenTypeDoc = nonEmptyString(form.when_type_doc)
            let whenSujet = nonEmptyString(form.when_sujet)
            let presetID = nonEmptyString(form.preset_id)
            let destinationTemplate = "Archives/{year}/{class_code}/\(sanitizeTemplateSegment(folderLabel))"
            let nameFormat = "{class_code}-{type_doc}-{sujet}-{date}-{numero}"

            let rule = RoutingRule(
                id: ruleID,
                when_type_doc: whenTypeDoc,
                when_sujet: whenSujet,
                when_class_code: nil,
                class_code: inferredClassCode,
                preset_id: presetID,
                destination_template: destinationTemplate,
                name_format: nameFormat
            )

            var existing = ConfigLoader.loadRoutingRules()?.rules ?? []
            if let index = existing.firstIndex(where: { nonEmptyString($0.id) == ruleID }) {
                existing[index] = rule
            } else {
                existing.append(rule)
            }
            try ConfigLoader.saveRoutingRules(RoutingRuleSet(rules: existing))

            return req.redirect(
                to: "/ui/presets?notice=\(urlQueryEncoded("Règle suggérée créée (\(ruleID)). Vérifie puis ajuste si nécessaire."))"
            )
        } catch let abort as AbortError {
            return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded(abort.reason))")
        } catch {
            req.logger.error("Échec génération règle suggérée UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded("Erreur interne pendant la génération de règle suggérée."))")
        }
    }

    app.post("ui", "routing", "rules", ":id", "delete") { req async throws -> Response in
        guard let id = req.parameters.get("id"),
              let trimmedID = nonEmptyString(id) else {
            return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded("Identifiant de règle invalide."))")
        }

        do {
            let current = ConfigLoader.loadRoutingRules()?.rules ?? []
            let updated = current.filter { nonEmptyString($0.id) != trimmedID }
            guard updated.count != current.count else {
                return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded("Règle introuvable."))")
            }
            try ConfigLoader.saveRoutingRules(RoutingRuleSet(rules: updated))
            return req.redirect(to: "/ui/presets?notice=\(urlQueryEncoded("Règle supprimée."))")
        } catch {
            req.logger.error("Échec suppression règle type/sujet UI.", metadata: [
                "error": .string(error.localizedDescription),
                "rule_id": .string(trimmedID)
            ])
            return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded("Erreur interne pendant la suppression de la règle."))")
        }
    }

    app.on(.POST, "ui", "taxonomy", "import", body: .collect(maxSize: "2mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UITaxonomyImportForm.self)
            let rawJSON = form.taxonomy_json.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawJSON.isEmpty else {
                throw Abort(.badRequest, reason: "Le JSON du plan de classification est requis.")
            }

            let data = Data(rawJSON.utf8)
            var taxonomy = try JSONDecoder().decode(TaxonomyRecord.self, from: data)
            if let explicitID = nonEmptyString(form.taxonomy_id),
               explicitID != taxonomy.taxonomy_id {
                taxonomy = TaxonomyRecord(taxonomy_id: explicitID, root: taxonomy.root)
            }

            await req.application.appState.saveTaxonomy(taxonomy)
            try ConfigLoader.saveTaxonomy(taxonomy)
            return req.redirect(
                to: "/ui/presets?notice=\(urlQueryEncoded("Plan de classification importé."))&taxonomy_id=\(urlQueryEncoded(taxonomy.taxonomy_id))"
            )
        } catch let abort as AbortError {
            return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded(abort.reason))")
        } catch {
            req.logger.error("Échec import taxonomie UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded("JSON de taxonomie invalide ou erreur interne."))")
        }
    }

    app.on(.POST, "ui", "taxonomy", "import-pdf", body: .collect(maxSize: "32mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UITaxonomyImportPDFForm.self)
            let taxonomyID = nonEmptyString(form.taxonomy_id) ?? "taxonomy-from-pdf"
            let fileName = form.pdf.filename.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fileName.isEmpty, fileName.lowercased().hasSuffix(".pdf") else {
                throw Abort(.badRequest, reason: "Le fichier fourni doit être un PDF.")
            }
            guard form.pdf.data.readableBytes > 0 else {
                throw Abort(.badRequest, reason: "Le PDF est vide.")
            }

            let tempPDF = FileManager.default.temporaryDirectory
                .appendingPathComponent("orchiviste-taxonomy-\(UUID().uuidString).pdf")
            let textOutput = FileManager.default.temporaryDirectory
                .appendingPathComponent("orchiviste-taxonomy-\(UUID().uuidString).txt")
            defer {
                try? FileManager.default.removeItem(at: tempPDF)
                try? FileManager.default.removeItem(at: textOutput)
            }

            try Data(buffer: form.pdf.data).write(to: tempPDF, options: .atomic)
            let convert = runEnvCommand(
                executable: "pdftotext",
                arguments: ["-enc", "UTF-8", "-layout", tempPDF.path, textOutput.path]
            )
            guard convert.exitCode == 0 else {
                throw Abort(.badRequest, reason: "Impossible d'extraire le texte du PDF (pdftotext).")
            }
            guard let rawText = try? String(contentsOf: textOutput, encoding: .utf8),
                  !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw Abort(.badRequest, reason: "Le PDF ne contient pas de texte exploitable.")
            }

            let taxonomy = buildTaxonomyFromPlanPDFText(rawText, taxonomyID: taxonomyID)
            guard !taxonomy.root.isEmpty else {
                throw Abort(.badRequest, reason: "Aucun code de classification détecté dans le PDF.")
            }

            await req.application.appState.saveTaxonomy(taxonomy)
            try ConfigLoader.saveTaxonomy(taxonomy)
            return req.redirect(
                to: "/ui/presets?notice=\(urlQueryEncoded("Plan de classification importé depuis PDF."))&taxonomy_id=\(urlQueryEncoded(taxonomy.taxonomy_id))"
            )
        } catch let abort as AbortError {
            return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded(abort.reason))")
        } catch {
            req.logger.error("Échec import taxonomie PDF UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui/presets?error=\(urlQueryEncoded("Erreur interne pendant l'import du plan PDF."))")
        }
    }

    app.on(.POST, "ui", "workers", "enroll", body: .collect(maxSize: "1mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UIWorkerEnrollForm.self)
            let name = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw Abort(.badRequest, reason: "Le nom de l'agent est requis.")
            }
            let capabilities = parseUploadTags(raw: form.capabilities)
            let worker = await uiEnrollWorkerWithPersistence(
                name: name,
                capabilities: capabilities,
                req: req
            )
            await EventPublisher.publish(
                type: "worker.enrolled",
                payload: ["worker_id": worker.id.uuidString],
                application: req.application,
                database: req.db,
                logger: req.logger
            )
            return req.redirect(to: "/ui/workers?notice=\(urlQueryEncoded("Agent enrôlé."))")
        } catch let abort as AbortError {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded(abort.reason))")
        } catch {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("Erreur interne pendant l'enrôlement."))")
        }
    }

    app.post("ui", "workers", ":id", "approve") { req async throws -> Response in
        guard let id = req.parameters.get("id"),
              let workerID = UUID(uuidString: id) else {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("Identifiant d'agent invalide."))")
        }
        guard let existing = await uiResolveWorker(workerID, req: req) else {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("Agent introuvable."))")
        }
        let worker = await uiApproveWorkerWithPersistence(id: workerID, fallback: existing, req: req)
        await EventPublisher.publish(
            type: "worker.approved",
            payload: ["worker_id": worker.id.uuidString],
            application: req.application,
            database: req.db,
            logger: req.logger
        )
        return req.redirect(to: "/ui/workers?notice=\(urlQueryEncoded("Agent approuvé."))")
    }

    app.post("ui", "workers", ":id", "pause") { req async throws -> Response in
        guard let id = req.parameters.get("id"),
              let workerID = UUID(uuidString: id) else {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("Identifiant d'agent invalide."))")
        }
        guard let existing = await uiResolveWorker(workerID, req: req) else {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("Agent introuvable."))")
        }
        guard existing.status == .approved else {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("Seul un agent approuvé peut être mis en pause."))")
        }

        let worker = await uiPauseWorkerWithPersistence(id: workerID, fallback: existing, req: req)
        await EventPublisher.publish(
            type: "worker.paused",
            payload: ["worker_id": worker.id.uuidString],
            application: req.application,
            database: req.db,
            logger: req.logger
        )
        return req.redirect(to: "/ui/workers?notice=\(urlQueryEncoded("Agent mis en pause."))")
    }

    app.post("ui", "workers", ":id", "resume") { req async throws -> Response in
        guard let id = req.parameters.get("id"),
              let workerID = UUID(uuidString: id) else {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("Identifiant d'agent invalide."))")
        }
        guard let existing = await uiResolveWorker(workerID, req: req) else {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("Agent introuvable."))")
        }
        guard existing.status == .paused else {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("Seul un agent en pause peut être réactivé."))")
        }

        let worker = await uiResumeWorkerWithPersistence(id: workerID, fallback: existing, req: req)
        await EventPublisher.publish(
            type: "worker.resumed",
            payload: ["worker_id": worker.id.uuidString],
            application: req.application,
            database: req.db,
            logger: req.logger
        )
        return req.redirect(to: "/ui/workers?notice=\(urlQueryEncoded("Agent réactivé."))")
    }

    app.on(.POST, "ui", "workers", ":id", "config", body: .collect(maxSize: "1mb")) { req async throws -> Response in
        guard let id = req.parameters.get("id"),
              let workerID = UUID(uuidString: id) else {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("Identifiant d'agent invalide."))")
        }
        guard let existing = await uiResolveWorker(workerID, req: req) else {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("Agent introuvable."))")
        }

        let form = try req.content.decode(UIWorkerConfigForm.self)
        let payload = WorkerConfigUpdateRequest(
            capabilities: {
                let parsed = parseUploadTags(raw: form.capabilities)
                return parsed.isEmpty ? nil : parsed
            }(),
            version: nonEmptyString(form.version)
        )

        let worker = await uiConfigureWorkerWithPersistence(
            id: workerID,
            payload: payload,
            fallback: existing,
            req: req
        )
        await EventPublisher.publish(
            type: "worker.configured",
            payload: ["worker_id": worker.id.uuidString],
            application: req.application,
            database: req.db,
            logger: req.logger
        )
        return req.redirect(to: "/ui/workers?notice=\(urlQueryEncoded("Configuration agent mise à jour."))")
    }

    app.on(.POST, "ui", "workers", ":id", "heartbeat", body: .collect(maxSize: "1mb")) { req async throws -> Response in
        guard let id = req.parameters.get("id"),
              let workerID = UUID(uuidString: id) else {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("Identifiant d'agent invalide."))")
        }
        guard let existing = await uiResolveWorker(workerID, req: req) else {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("Agent introuvable."))")
        }
        guard existing.status == .approved else {
            return req.redirect(to: "/ui/workers?error=\(urlQueryEncoded("L'agent doit être approuvé avant heartbeat."))")
        }

        let form = try req.content.decode(UIWorkerHeartbeatForm.self)
        let heartbeat = WorkerHeartbeatRequest(
            version: nonEmptyString(form.version) ?? "ui-test",
            load: parseOptionalDouble(form.load),
            ram_mb: parseOptionalInt(form.ram_mb),
            capabilities: {
                let parsed = parseUploadTags(raw: form.capabilities)
                return parsed.isEmpty ? nil : parsed
            }()
        )

        let worker = await uiHeartbeatWorkerWithPersistence(
            id: workerID,
            payload: heartbeat,
            fallback: existing,
            req: req
        )
        await EventPublisher.publish(
            type: "worker.heartbeat",
            payload: ["worker_id": worker.id.uuidString],
            application: req.application,
            database: req.db,
            logger: req.logger
        )
        return req.redirect(to: "/ui/workers?notice=\(urlQueryEncoded("Heartbeat de test envoyé."))")
    }

    app.get("ui") { req async throws -> View in
        let jobs = try await loadJobRecords(req: req, limit: 100)
        let workerCount = try await loadWorkerRecords(req: req).count
        let queueStats = await RedisQueueService.queueStats(application: req.application, logger: req.logger)
        let routingSettings = ConfigLoader.loadRoutingLocalSettings()
        let dashboardState = ConfigLoader.loadDashboardState()
        let recentCutoff = dashboardState?.recent_jobs_cleared_at
        let uploadNotice = req.query[String.self, at: "upload_notice"]
        let uploadError = req.query[String.self, at: "upload_error"]
        let dashboardNotice = req.query[String.self, at: "dashboard_notice"]
        let dashboardError = req.query[String.self, at: "dashboard_error"]

        let counts = Dictionary(grouping: jobs, by: \.status)
        let recentJobRecords = jobs
            .filter { job in
                guard let recentCutoff else { return true }
                return job.createdAt > recentCutoff
            }
            .prefix(15)
        let recentCounts = Dictionary(grouping: recentJobRecords, by: \.status)
        let recentJobs = recentJobRecords.map(makeUIJobSummary)
        let dashboardHasActiveProcessing =
            (recentCounts[.pending]?.isEmpty == false) ||
            (recentCounts[.running]?.isEmpty == false) ||
            queueStats.ingest_depth > 0
        let context = UIDashboardContext(
            total_jobs: jobs.count,
            pending_jobs: counts[.pending]?.count ?? 0,
            running_jobs: counts[.running]?.count ?? 0,
            needs_review_jobs: counts[.needs_review]?.count ?? 0,
            completed_jobs: counts[.completed]?.count ?? 0,
            failed_jobs: counts[.failed]?.count ?? 0,
            cancelled_jobs: counts[.cancelled]?.count ?? 0,
            worker_count: workerCount,
            queue_ingest_depth: queueStats.ingest_depth,
            queue_dead_letter_depth: queueStats.dead_letter_depth,
            recent_jobs: recentJobs,
            recent_jobs_empty: recentJobs.isEmpty,
            recent_jobs_present: !recentJobs.isEmpty,
            recent_jobs_cleared: recentCutoff != nil,
            recent_total_jobs: recentJobs.count,
            recent_pending_jobs: recentCounts[.pending]?.count ?? 0,
            recent_running_jobs: recentCounts[.running]?.count ?? 0,
            recent_needs_review_jobs: recentCounts[.needs_review]?.count ?? 0,
            recent_completed_jobs: recentCounts[.completed]?.count ?? 0,
            recent_failed_jobs: recentCounts[.failed]?.count ?? 0,
            recent_cancelled_jobs: recentCounts[.cancelled]?.count ?? 0,
            dashboard_has_active_processing: dashboardHasActiveProcessing,
            dashboard_auto_refresh_seconds: dashboardHasActiveProcessing ? 4 : 0,
            dashboard_notice: dashboardNotice,
            dashboard_error: dashboardError,
            upload_notice: uploadNotice,
            upload_error: uploadError,
            ingest_default_input_folder: resolveUILocalIngestInboxDirectory().path,
            ingest_default_output_folder: routingSettings?.local_route_root ?? "/data/routed"
        )
        return try await req.view.render("dashboard", context)
    }

    app.get("ui", "jobs") { req async throws -> View in
        let jobs = try await loadJobs(req: req, limit: 300)
        return try await req.view.render("jobs", UIJobsContext(jobs: jobs))
    }

    app.get("ui", "setup") { req async throws -> View in
        let routingSettings = ConfigLoader.loadRoutingLocalSettings()
        let context = UISetupContext(
            ingest_default_input_folder: resolveUILocalIngestInboxDirectory().path,
            routing_local_route_root: routingSettings?.local_route_root ?? "/data/routed",
            routing_default_destination_template: routingSettings?.default_destination_template ?? "Archives/{year}/{class_code}/{type_doc}/{sujet}",
            routing_default_name_format: routingSettings?.default_name_format ?? "{class_code}-{type_doc}-{sujet}-{date}-{numero}",
            renaming_guide: ConfigLoader.loadRenamingGuide(),
            taxonomy_ids: await loadTaxonomyIDs(req: req),
            notice: req.query[String.self, at: "notice"],
            error: req.query[String.self, at: "error"]
        )
        return try await req.view.render("setup", context)
    }

    app.get("ui", "workers") { req async throws -> View in
        let workers = await loadWorkers(req: req)
        let queueStats = await RedisQueueService.queueStats(application: req.application, logger: req.logger)
        let context = UIWorkersContext(
            workers: workers,
            queue_ingest_depth: queueStats.ingest_depth,
            queue_dead_letter_depth: queueStats.dead_letter_depth,
            notice: req.query[String.self, at: "notice"],
            error: req.query[String.self, at: "error"]
        )
        return try await req.view.render("workers", context)
    }

    app.get("ui", "presets") { req async throws -> View in
        let presets = await loadPresets(req: req)
        let routingSettings = ConfigLoader.loadRoutingLocalSettings()
        let taxonomyIDs = await loadTaxonomyIDs(req: req)
        let selectedTaxonomyID = req.query[String.self, at: "taxonomy_id"] ?? taxonomyIDs.first
        let selectedTaxonomyJSON = await loadTaxonomyJSONPreview(id: selectedTaxonomyID, req: req)
        let routingRules = (ConfigLoader.loadRoutingRules()?.rules ?? []).map { rule in
            UIRoutingRuleSummary(
                id: nonEmptyString(rule.id) ?? "(sans-id)",
                when_type_doc: nonEmptyString(rule.when_type_doc) ?? "-",
                when_sujet: nonEmptyString(rule.when_sujet) ?? "-",
                when_class_code: nonEmptyString(rule.when_class_code) ?? "-",
                class_code: nonEmptyString(rule.class_code) ?? "-",
                preset_id: nonEmptyString(rule.preset_id) ?? "-",
                destination_template: nonEmptyString(rule.destination_template) ?? "-",
                name_format: nonEmptyString(rule.name_format) ?? "-"
            )
        }
        return try await req.view.render(
            "presets",
            UIPresetsContext(
                presets: presets,
                routing_local_route_root: routingSettings?.local_route_root ?? "",
                routing_default_destination_template: routingSettings?.default_destination_template ?? "",
                routing_default_name_format: routingSettings?.default_name_format ?? "",
                routing_rules: routingRules,
                routing_rules_json: ConfigLoader.loadRoutingRulesRawJSON(),
                taxonomy_ids: taxonomyIDs,
                selected_taxonomy_id: selectedTaxonomyID,
                selected_taxonomy_json: selectedTaxonomyJSON,
                notice: req.query[String.self, at: "notice"],
                error: req.query[String.self, at: "error"]
            )
        )
    }

    app.get("ui", "events") { req async throws -> View in
        let bootstrap = try await loadUIEvents(req: req, cursor: 0)
        let summaries = bootstrap.events.map { event in
            UIEventSummary(
                id: event.id,
                type: event.type,
                created_at: formatTimestamp(event.created_at),
                payload: formatEventPayload(event.payload)
            )
        }
        let context = UIEventsContext(
            events: Array(summaries.suffix(200)),
            initial_cursor: bootstrap.cursor
        )
        return try await req.view.render("events", context)
    }

    app.get("ui", "jobs", ":id", "download-searchable") { req async throws -> Response in
        guard let id = req.parameters.get("id"),
              let jobID = UUID(uuidString: id) else {
            let reason = urlQueryEncoded("Identifiant de tâche invalide.")
            return req.redirect(to: "/ui/jobs?error=\(reason)")
        }
        _ = try await resolveUIJob(jobID: jobID, req: req)
        return req.redirect(to: "/v1/jobs/\(jobID.uuidString)/download/searchable")
    }

    app.get("ui", "jobs", ":id") { req async throws -> View in
        guard let id = req.parameters.get("id"),
              let jobID = UUID(uuidString: id) else {
            throw Abort(.badRequest, reason: "Identifiant de tâche invalide.")
        }
        let job = try await resolveUIJob(jobID: jobID, req: req)
        let preview = try await PreviewLoader.ensurePreview(jobId: jobID, req: req)
        let classCodeOptions = await loadClassCodeOptions(req: req, include: job.suggestedClassCode)
        let presetOptions = await loadPresetIDs(req: req, include: job.suggestedPreset)
        let canRoute: Bool
        let routeDisabledReason: String?
        if job.status == .needs_review {
            canRoute = false
            routeDisabledReason = "Revue requise avant routage."
        } else if job.status == .pending || job.status == .running {
            canRoute = false
            routeDisabledReason = "Analyse en cours."
        } else if job.status == .failed || job.status == .cancelled {
            canRoute = false
            routeDisabledReason = "Statut non routable."
        } else if job.steps.routed != nil {
            canRoute = false
            routeDisabledReason = "Cette tâche est déjà routée."
        } else {
            canRoute = true
            routeDisabledReason = nil
        }
        let context = UIJobViewerContext(
            id: job.id.uuidString,
            status: localizedJobStatus(job.status.rawValue),
            file_url: job.fileURL,
            source_kind: localizedSourceKind(job.source.kind),
            suggested_preset: job.suggestedPreset ?? "N/D",
            suggested_class_code: job.suggestedClassCode ?? "N/D",
            confidence: job.confidence.map { String(format: "%.2f", $0) } ?? "-",
            needs_review: job.needsReview,
            can_review: job.status == .needs_review,
            can_route: canRoute,
            route_disabled_reason: routeDisabledReason,
            routed_at: job.steps.routed.map(formatTimestamp),
            preview_pages: max(1, preview?.pages ?? 1),
            download_url: "/v1/jobs/\(job.id.uuidString)/download",
            download_searchable_url: "/ui/jobs/\(job.id.uuidString)/download-searchable",
            analysis_type_doc: job.analysisTypeDoc ?? "N/D",
            analysis_sujets: (job.analysisSujets ?? []).isEmpty ? "N/D" : (job.analysisSujets ?? []).joined(separator: ", "),
            analysis_capture_strategy: extractAnalysisValue(job.analysisChamps, key: "capture.strategy", fallback: "idp_capture_strategy"),
            analysis_review_reasons: extractAnalysisValue(job.analysisChamps, key: "review.reasons", fallback: "idp_review_reasons"),
            analysis_champs_json: prettyPrintedJSON(job.analysisChamps),
            analysis_validation_flags: extractValidationFlags(job.analysisChamps),
            class_code_options: classCodeOptions,
            preset_options: presetOptions,
            suggested_class_code_raw: nonEmptyString(job.suggestedClassCode),
            suggested_preset_raw: nonEmptyString(job.suggestedPreset)
        )
        return try await req.view.render("job_viewer", context)
    }
}

private func loadWorkers(req: Request) async -> [UIWorkerSummary] {
    let workers = ((try? await loadWorkerRecords(req: req)) ?? [])
        .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    return workers.map { worker in
        let rawStatus = worker.status.rawValue
        let capabilities = worker.capabilities
        return UIWorkerSummary(
            id: worker.id.uuidString,
            name: worker.name,
            status_raw: rawStatus,
            status: localizedWorkerStatus(rawStatus),
            capabilities: capabilities.joined(separator: ", "),
            has_coreml: capabilities.contains(where: {
                $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                    .lowercased()
                    .contains("coreml")
            }),
            last_seen: worker.lastSeen.map(formatTimestamp) ?? "-",
            version: worker.version ?? "-",
            load: worker.load.map { String(format: "%.2f", $0) } ?? "-",
            ram_mb: worker.ram_mb.map(String.init) ?? "-",
            can_approve: rawStatus == WorkerStatus.pending.rawValue,
            can_heartbeat: rawStatus == WorkerStatus.approved.rawValue,
            can_pause: rawStatus == WorkerStatus.approved.rawValue,
            can_resume: rawStatus == WorkerStatus.paused.rawValue
        )
    }
}

private func loadWorkerRecords(req: Request) async throws -> [WorkerRecord] {
    if let persisted = try? await JobPersistenceRepository.listWorkers(on: req.db) {
        await req.application.appState.cacheWorkers(persisted)
        return persisted
    }
    return await req.application.appState.listWorkers()
}

private func uiResolveWorker(_ id: UUID, req: Request) async -> WorkerRecord? {
    if let inMemory = await req.application.appState.worker(id: id) {
        return inMemory
    }
    if let worker = try? await JobPersistenceRepository.fetchWorker(id: id, on: req.db) {
        await req.application.appState.cacheWorker(worker)
        return worker
    }
    return nil
}

private func uiEnrollWorkerWithPersistence(
    name: String,
    capabilities: [String],
    req: Request
) async -> WorkerRecord {
    if let persisted = try? await JobPersistenceRepository.enrollWorker(
        name: name,
        capabilities: capabilities,
        on: req.db
    ) {
        await req.application.appState.cacheWorker(persisted)
        return persisted
    }
    return await req.application.appState.enrollWorker(name: name, capabilities: capabilities)
}

private func uiApproveWorkerWithPersistence(
    id: UUID,
    fallback: WorkerRecord,
    req: Request
) async -> WorkerRecord {
    if let worker = try? await JobPersistenceRepository.approveWorker(id: id, on: req.db) {
        await req.application.appState.cacheWorker(worker)
        return worker
    }
    return await req.application.appState.approveWorker(id: id) ?? fallback
}

private func uiPauseWorkerWithPersistence(
    id: UUID,
    fallback: WorkerRecord,
    req: Request
) async -> WorkerRecord {
    if let worker = try? await JobPersistenceRepository.pauseWorker(id: id, on: req.db) {
        await req.application.appState.cacheWorker(worker)
        return worker
    }
    return await req.application.appState.pauseWorker(id: id) ?? fallback
}

private func uiResumeWorkerWithPersistence(
    id: UUID,
    fallback: WorkerRecord,
    req: Request
) async -> WorkerRecord {
    if let worker = try? await JobPersistenceRepository.resumeWorker(id: id, on: req.db) {
        await req.application.appState.cacheWorker(worker)
        return worker
    }
    return await req.application.appState.resumeWorker(id: id) ?? fallback
}

private func uiConfigureWorkerWithPersistence(
    id: UUID,
    payload: WorkerConfigUpdateRequest,
    fallback: WorkerRecord,
    req: Request
) async -> WorkerRecord {
    if let worker = try? await JobPersistenceRepository.configureWorker(
        id: id,
        payload: payload,
        on: req.db
    ) {
        await req.application.appState.cacheWorker(worker)
        return worker
    }
    return await req.application.appState.configureWorker(id: id, payload: payload) ?? fallback
}

private func uiHeartbeatWorkerWithPersistence(
    id: UUID,
    payload: WorkerHeartbeatRequest,
    fallback: WorkerRecord,
    req: Request
) async -> WorkerRecord {
    if let worker = try? await JobPersistenceRepository.heartbeatWorker(
        id: id,
        payload: payload,
        on: req.db
    ) {
        await req.application.appState.cacheWorker(worker)
        return worker
    }
    return await req.application.appState.heartbeatWorker(id: id, payload: payload) ?? fallback
}

private func loadUIEvents(req: Request, cursor: Int) async throws -> EventsResponse {
    do {
        return try await JobPersistenceRepository.listEvents(after: cursor, on: req.db)
    } catch {
        req.logger.warning("Bascule vers les événements en mémoire: \(error.localizedDescription)")
        return await req.application.appState.events(after: cursor)
    }
}

private func loadPresets(req: Request) async -> [UIPresetSummary] {
    let disk = ConfigLoader.loadPresets()
    let memory = await req.application.appState.listPresets()
    return mergePresets(disk: disk, memory: memory)
        .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        .map { preset in
            UIPresetSummary(
                id: preset.id,
                name: preset.name,
                name_format: preset.name_format,
                class_code: preset.class_code ?? "-",
                postprocess: (preset.postprocess ?? []).joined(separator: ", ")
            )
        }
}

private func loadJobRecords(req: Request, limit: Int) async throws -> [JobRecord] {
    let jobs: [JobRecord]
    if let persisted = try? await JobPersistenceRepository.listJobs(limit: limit, on: req.db),
       !persisted.isEmpty {
        jobs = persisted
    } else {
        jobs = await req.application.appState.listJobs(limit: limit)
    }
    return jobs
}

private func loadJobs(req: Request, limit: Int) async throws -> [UIJobSummary] {
    try await loadJobRecords(req: req, limit: limit).map(makeUIJobSummary)
}

private func makeUIJobSummary(_ job: JobRecord) -> UIJobSummary {
    UIJobSummary(
        id: job.id.uuidString,
        status: job.status.rawValue,
        status_label: localizedJobStatus(job.status.rawValue),
        file_url: job.fileURL,
        source_kind: localizedSourceKind(job.source.kind),
        confidence: job.confidence.map { String(format: "%.2f", $0) } ?? "-",
        suggested_class_code: job.suggestedClassCode ?? "N/D",
        ocr_ok: localizedRouteFlag(routeValue(job, key: "route.ocr_status")),
        resolved_file_name: routeValue(job, key: "route.resolved_file_name") ?? "-",
        metadata_ok: localizedMetadataFlag(routeValue(job, key: "route.metadata_status")),
        saved_folder_path: routeSavedFolderPath(job) ?? "-",
        updated_at: formatTimestamp(job.updatedAt)
    )
}

private func resolveUIJob(jobID: UUID, req: Request) async throws -> JobRecord {
    if let inMemory = await req.application.appState.job(id: jobID) {
        return inMemory
    }
    if let persisted = try await JobPersistenceRepository.fetchJob(id: jobID, on: req.db) {
        await req.application.appState.cacheJob(persisted)
        return persisted
    }
    throw Abort(.notFound, reason: "Tâche introuvable.")
}

private func formatTimestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

private func formatEventPayload(_ payload: [String: String]) -> String {
    guard !payload.isEmpty else { return "-" }
    return payload
        .sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: ", ")
}

private func localizedJobStatus(_ raw: String) -> String {
    switch raw {
    case "pending": return "En attente"
    case "running": return "En cours"
    case "needs_review": return "Revue requise"
    case "completed": return "Terminée"
    case "failed": return "En échec"
    case "cancelled": return "Annulée"
    default: return raw
    }
}

private func localizedWorkerStatus(_ raw: String) -> String {
    switch raw {
    case "pending": return "En attente"
    case "approved": return "Approuvé"
    case "paused": return "En pause"
    default: return raw
    }
}

private func localizedSourceKind(_ raw: String) -> String {
    switch raw.lowercased() {
    case "local": return "Local"
    case "sharepoint": return "SharePoint"
    default: return raw
    }
}

private func routeValue(_ job: JobRecord, key: String) -> String? {
    guard let value = job.analysisChamps?[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else {
        return nil
    }
    return value
}

private func localizedRouteFlag(_ raw: String?) -> String {
    switch raw?.lowercased() {
    case "ok":
        return "OK"
    case "pending":
        return "À faire"
    case "n/a", "na":
        return "-"
    default:
        return "-"
    }
}

private func localizedMetadataFlag(_ raw: String?) -> String {
    switch raw?.lowercased() {
    case "ok":
        return "OK"
    case "pending":
        return "À faire"
    case "n/a", "na":
        return "-"
    default:
        return "-"
    }
}

private func routeSavedFolderPath(_ job: JobRecord) -> String? {
    if let explicit = routeValue(job, key: "route.destination_folder_display") {
        return explicit
    }
    if let localPath = routeValue(job, key: "route.destination_local_path") {
        return URL(fileURLWithPath: localPath).deletingLastPathComponent().path
    }
    if let resolvedFolder = routeValue(job, key: "route.resolved_folder") {
        return resolvedFolder
    }
    return nil
}

private func parseUploadTags(raw: String?) -> [String] {
    guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return []
    }
    return raw
        .split(whereSeparator: { $0 == "," || $0 == ";" })
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func nonEmptyString(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func parseOptionalDouble(_ raw: String?) -> Double? {
    guard let value = nonEmptyString(raw) else { return nil }
    return Double(value)
}

private func parseOptionalInt(_ raw: String?) -> Int? {
    guard let value = nonEmptyString(raw) else { return nil }
    return Int(value)
}

private func buildRoutingRuleID(
    explicit: String?,
    whenTypeDoc: String?,
    whenSujet: String?,
    whenClassCode: String?
) -> String {
    if let explicit {
        return sanitizeRoutingRuleID(explicit)
    }
    let raw = [
        "rule",
        whenTypeDoc ?? "anytype",
        whenSujet ?? "anysujet",
        whenClassCode ?? "anycode"
    ].joined(separator: "-")
    return sanitizeRoutingRuleID(raw)
}

private func sanitizeRoutingRuleID(_ raw: String) -> String {
    let folded = raw
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
    let slug = folded.replacingOccurrences(
        of: #"[^\p{L}\p{N}._-]+"#,
        with: "-",
        options: .regularExpression
    )
    let cleaned = slug
        .trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
    return cleaned.isEmpty ? "rule-\(UUID().uuidString.prefix(8))" : cleaned
}

private func prettyPrintedJSON(_ dictionary: [String: String]?) -> String {
    guard let dictionary, !dictionary.isEmpty else {
        return "{}"
    }
    guard JSONSerialization.isValidJSONObject(dictionary),
          let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys]),
          let text = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return text
}

private func extractValidationFlags(_ dictionary: [String: String]?) -> String {
    guard let raw = dictionary?["idp_validation_flags"] else {
        return "Aucun"
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Aucun" : trimmed
}

private func extractAnalysisValue(
    _ dictionary: [String: String]?,
    key: String,
    fallback: String? = nil
) -> String {
    if let value = dictionary?[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !value.isEmpty {
        return value
    }
    if let fallback,
       let value = dictionary?[fallback]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !value.isEmpty {
        return value
    }
    return "Aucun"
}

private func resolveUILocalIngestInboxDirectory() -> URL {
    if let configured = Environment.get("ORCHIVISTE_LOCAL_INGEST_ROOT")?
        .trimmingCharacters(in: .whitespacesAndNewlines),
       !configured.isEmpty {
        return URL(fileURLWithPath: configured, isDirectory: true)
    }

    if let sqlitePath = Environment.get("ORCHIVISTE_SQLITE_PATH"),
       sqlitePath.hasPrefix("/") {
        return URL(fileURLWithPath: sqlitePath)
            .deletingLastPathComponent()
            .appendingPathComponent("inbox", isDirectory: true)
    }

    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        .appendingPathComponent(".orchiviste-inbox", isDirectory: true)
}

private func sanitizeUploadFileName(_ raw: String) -> String {
    let filename = (raw as NSString).lastPathComponent
    let allowed = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "._-"))
    let sanitized = filename.unicodeScalars
        .map { allowed.contains($0) ? Character($0) : "_" }
        .reduce(into: "") { partialResult, next in
            partialResult.append(next)
        }
    let fallback = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    if fallback.isEmpty {
        return "document"
    }
    return fallback
}

private func isSupportedIngestFileName(_ fileName: String) -> Bool {
    let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
    return DocumentTextExtractor.supportedExtensions().contains(ext)
}

private func uiFolderPickerRoots() -> [URL] {
    if let raw = Environment.get("ORCHIVISTE_UI_FOLDER_ROOTS"),
       !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let parsed = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if !parsed.isEmpty {
            return parsed
        }
    }

    let defaults = [
        "/data",
        "/Volumes/MAC_HDD"
    ].map { URL(fileURLWithPath: $0, isDirectory: true) }
    let existing = defaults.filter { FileManager.default.fileExists(atPath: $0.path) }
    if !existing.isEmpty {
        return existing
    }
    return [resolveUILocalIngestInboxDirectory().deletingLastPathComponent()]
}

private func resolveFolderPickerPath(_ requested: String?, roots: [URL]) throws -> URL {
    guard !roots.isEmpty else {
        throw Abort(.badRequest, reason: "Aucune racine de navigation configurée.")
    }
    guard let requested = requested?.trimmingCharacters(in: .whitespacesAndNewlines),
          !requested.isEmpty else {
        return roots[0]
    }

    let resolved = URL(fileURLWithPath: requested, isDirectory: true)
    let normalized = resolved.standardizedFileURL
    let candidateURL: URL
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDirectory),
       !isDirectory.boolValue {
        candidateURL = normalized.deletingLastPathComponent()
    } else {
        candidateURL = normalized
    }

    let isWithinRoot = roots.contains { root in
        let rootPath = root.standardizedFileURL.path
        return candidateURL.path == rootPath || candidateURL.path.hasPrefix(rootPath + "/")
    }
    guard isWithinRoot else {
        throw Abort(.forbidden, reason: "Accès hors des racines autorisées.")
    }
    guard FileManager.default.fileExists(atPath: candidateURL.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        throw Abort(.notFound, reason: "Dossier introuvable.")
    }
    return candidateURL
}

private func formatUploadTimestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: date)
}

private func parseBooleanFlag(_ raw: String?, defaultValue: Bool) -> Bool {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
          !raw.isEmpty else {
        return defaultValue
    }
    return raw == "1" || raw == "true" || raw == "on" || raw == "yes"
}

private func parseMaxFiles(_ raw: String?) -> Int {
    guard let value = Int(raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") else {
        return 50
    }
    return max(1, min(500, value))
}

private func collectPDFFiles(in root: URL, recursive: Bool, maxFiles: Int) throws -> [URL] {
    let manager = FileManager.default
    var results: [URL] = []
    if recursive {
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            guard url.pathExtension.lowercased() == "pdf" else { continue }
            results.append(url)
            if results.count >= maxFiles {
                break
            }
        }
    } else {
        let items = try manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        for url in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            guard url.pathExtension.lowercased() == "pdf" else { continue }
            results.append(url)
            if results.count >= maxFiles {
                break
            }
        }
    }
    return results.sorted(by: { $0.path < $1.path })
}

private func collectSupportedDocumentFiles(in root: URL, recursive: Bool, maxFiles: Int) throws -> [URL] {
    let manager = FileManager.default
    let allowed = Set(DocumentTextExtractor.supportedExtensions())
    var results: [URL] = []

    if recursive {
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            guard allowed.contains(url.pathExtension.lowercased()) else { continue }
            results.append(url)
            if results.count >= maxFiles {
                break
            }
        }
    } else {
        let items = try manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        for url in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            guard allowed.contains(url.pathExtension.lowercased()) else { continue }
            results.append(url)
            if results.count >= maxFiles {
                break
            }
        }
    }
    return results.sorted(by: { $0.path < $1.path })
}

private func parseSubmittedPDFNames(_ raw: String?) -> [String] {
    guard let raw else { return [] }
    return raw
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .map { $0.replacingOccurrences(of: "\\", with: "/") }
        .filter { $0.lowercased().hasSuffix(".pdf") }
}

private func inferSubmittedFolderLabel(from submittedNames: [String]) -> String? {
    for submittedName in submittedNames {
        let normalized = submittedName.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/").map(String.init)
        guard parts.count > 1 else { continue }
        if let candidate = nonEmptyString(parts[0]) {
            return candidate
        }
    }
    return nil
}

private func inferClassCodeFromFileNames(_ names: [String]) -> String? {
    guard !names.isEmpty else {
        return nil
    }
    let regex = try? NSRegularExpression(pattern: #"^([A-Za-z]{2,}(?:-[A-Za-z0-9]{1,6})?|[0-9]{3,4}(?:-[0-9]{2})?)"#)
    var frequency: [String: Int] = [:]

    for name in names {
        let stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let normalized = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { continue }
        if let regex {
            let nsRange = NSRange(location: 0, length: (normalized as NSString).length)
            if let match = regex.firstMatch(in: normalized, options: [], range: nsRange),
               let range = Range(match.range(at: 1), in: normalized) {
                let token = String(normalized[range]).uppercased()
                frequency[token, default: 0] += 1
                continue
            }
        }
    }

    guard let winner = frequency.max(by: { lhs, rhs in
        if lhs.value == rhs.value {
            return lhs.key > rhs.key
        }
        return lhs.value < rhs.value
    })?.key else {
        return nil
    }
    return winner
}

private func sanitizeTemplateSegment(_ raw: String) -> String {
    let cleaned = raw
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .replacingOccurrences(of: #"[^\p{L}\p{N}._-]+"#, with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
    return cleaned.isEmpty ? "documents" : cleaned
}

private func buildFolderIngestIdempotencyKey(fileURL: URL) -> String {
    let modificationDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        ?? Date.distantPast
    let seconds = Int(modificationDate.timeIntervalSince1970)
    let raw = "ui-folder-\(fileURL.path)-\(seconds)"
    return raw
        .replacingOccurrences(of: "[^a-zA-Z0-9._:-]+", with: "-", options: .regularExpression)
        .prefix(200)
        .description
}

private func loadTaxonomyIDs(req: Request) async -> [String] {
    var ids = Set<String>()

    let inMemory = await req.application.appState.listTaxonomies().map(\.taxonomy_id)
    for id in inMemory where !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        ids.insert(id)
    }

    let diskDirectory = ConfigLoader.baseDir().appendingPathComponent("analysis/taxonomy", isDirectory: true)
    if let files = try? FileManager.default.contentsOfDirectory(at: diskDirectory, includingPropertiesForKeys: nil) {
        for url in files where url.pathExtension.lowercased() == "json" {
            ids.insert(url.deletingPathExtension().lastPathComponent)
        }
    }
    return ids.sorted()
}

private func loadPresetIDs(req: Request, include value: String?) async -> [String] {
    var ids = Set<String>()
    let disk = ConfigLoader.loadPresets()
    let memory = await req.application.appState.listPresets()
    for preset in mergePresets(disk: disk, memory: memory) {
        if !preset.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ids.insert(preset.id)
        }
    }
    if let value = nonEmptyString(value) {
        ids.insert(value)
    }
    return ids.sorted()
}

private func loadClassCodeOptions(req: Request, include value: String?) async -> [String] {
    var codes = Set<String>()
    if let routingMap = ConfigLoader.loadRoutingMap() {
        for code in routingMap.mappings.keys where !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            codes.insert(code)
        }
    }

    let taxonomyIDs = await loadTaxonomyIDs(req: req)
    for id in taxonomyIDs {
        if let taxonomy = await req.application.appState.taxonomy(id: id) ?? ConfigLoader.loadTaxonomy(id: id) {
            collectTaxonomyCodes(from: taxonomy.root, into: &codes)
        }
    }
    if let value = nonEmptyString(value) {
        codes.insert(value)
    }
    return codes.sorted()
}

private func collectTaxonomyCodes(from nodes: [TaxonomyNode], into codes: inout Set<String>) {
    for node in nodes {
        let code = node.code.trimmingCharacters(in: .whitespacesAndNewlines)
        if !code.isEmpty {
            codes.insert(code)
        }
        if let children = node.children, !children.isEmpty {
            collectTaxonomyCodes(from: children, into: &codes)
        }
    }
}

private func loadTaxonomyJSONPreview(id: String?, req: Request) async -> String {
    guard let id = id?.trimmingCharacters(in: .whitespacesAndNewlines),
          !id.isEmpty else {
        return "{\n  \"taxonomy_id\": \"plan-ville\",\n  \"root\": []\n}\n"
    }

    if let inMemory = await req.application.appState.taxonomy(id: id),
       let data = try? JSONEncoder.prettyNoSlash.encode(inMemory),
       let text = String(data: data, encoding: .utf8) {
        return text
    }

    if let disk = ConfigLoader.loadTaxonomy(id: id),
       let data = try? JSONEncoder.prettyNoSlash.encode(disk),
       let text = String(data: data, encoding: .utf8) {
        return text
    }

    return "{\n  \"taxonomy_id\": \"\(id)\",\n  \"root\": []\n}\n"
}

private struct ParsedTaxonomyItem {
    let code: String
    let label: String
    let notes: String?
    let order: Int
    let parentCode: String?
}

private func buildTaxonomyFromPlanPDFText(_ rawText: String, taxonomyID: String) -> TaxonomyRecord {
    let regex = try? NSRegularExpression(pattern: #"^([0-9]{3,4}(?:-[0-9]{2})?)\s+(.+)$"#)
    let lines = rawText.components(separatedBy: .newlines)

    var labelsByCode: [String: String] = [:]
    var notesByCode: [String: [String]] = [:]
    var orderedCodes: [String] = []
    var latestCode: String?

    for rawLine in lines {
        let line = rawLine
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { continue }

        if line.lowercased().hasPrefix("remarque"),
           let latestCode {
            notesByCode[latestCode, default: []].append(line)
            continue
        }

        guard let regex else { continue }
        let range = NSRange(location: 0, length: (line as NSString).length)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 3,
              let codeRange = Range(match.range(at: 1), in: line),
              let labelRange = Range(match.range(at: 2), in: line) else {
            continue
        }

        let code = String(line[codeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let label = String(line[labelRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, !label.isEmpty else { continue }
        if labelsByCode[code] == nil {
            labelsByCode[code] = label
            orderedCodes.append(code)
        }
        latestCode = code
    }

    var items: [ParsedTaxonomyItem] = []
    items.reserveCapacity(orderedCodes.count)
    for (index, code) in orderedCodes.enumerated() {
        let label = labelsByCode[code] ?? code
        let notes = notesByCode[code]?.joined(separator: "\n")
        let parentCode = inferParentCode(for: code, among: Set(orderedCodes))
        items.append(ParsedTaxonomyItem(
            code: code,
            label: label,
            notes: notes,
            order: index,
            parentCode: parentCode
        ))
    }

    let byCode = Dictionary(uniqueKeysWithValues: items.map { ($0.code, $0) })
    var childrenMap: [String: [String]] = [:]
    var roots: [String] = []
    for item in items {
        if let parent = item.parentCode, byCode[parent] != nil {
            childrenMap[parent, default: []].append(item.code)
        } else {
            roots.append(item.code)
        }
    }

    func buildNode(code: String) -> TaxonomyNode {
        let item = byCode[code]!
        let children = (childrenMap[code] ?? [])
            .compactMap { byCode[$0] }
            .sorted { $0.order < $1.order }
            .map { buildNode(code: $0.code) }
        return TaxonomyNode(
            code: item.code,
            label: item.label,
            notes: item.notes,
            keywords: nil,
            synonyms: nil,
            children: children.isEmpty ? nil : children
        )
    }

    let rootNodes = roots
        .compactMap { byCode[$0] }
        .sorted { $0.order < $1.order }
        .map { buildNode(code: $0.code) }

    return TaxonomyRecord(
        taxonomy_id: taxonomyID,
        root: rootNodes
    )
}

private func inferParentCode(for code: String, among existingCodes: Set<String>) -> String? {
    if let hyphenIndex = code.firstIndex(of: "-") {
        let base = String(code[..<hyphenIndex])
        if existingCodes.contains(base) {
            return base
        }
    }

    let numeric = code.replacingOccurrences(of: "-", with: "")
    guard numeric.allSatisfy({ $0.isNumber }), numeric.count >= 3 else {
        return nil
    }

    var chars = Array(numeric)
    for index in stride(from: chars.count - 1, through: 0, by: -1) {
        if chars[index] == "0" { continue }
        chars[index] = "0"
        if index + 1 < chars.count {
            for j in (index + 1)..<chars.count {
                chars[j] = "0"
            }
        }
        let candidate = String(chars)
        if candidate != numeric, existingCodes.contains(candidate) {
            return candidate
        }
    }

    return nil
}

private func runEnvCommand(executable: String, arguments: [String]) -> (stdout: String, stderr: String, exitCode: Int32) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + arguments

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    do {
        try process.run()
    } catch {
        return ("", "\(error)", -1)
    }
    process.waitUntilExit()
    let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (stdout, stderr, process.terminationStatus)
}

private extension JSONEncoder {
    static var prettyNoSlash: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return encoder
    }
}

private func urlQueryEncoded(_ raw: String) -> String {
    raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
}
