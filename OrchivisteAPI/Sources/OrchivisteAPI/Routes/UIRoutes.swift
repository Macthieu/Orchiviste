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
    let upload_notice: String?
    let upload_error: String?
    let ingest_default_input_folder: String
    let ingest_default_output_folder: String
}

private struct UIJobsContext: Encodable {
    let jobs: [UIJobSummary]
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
    let updated_at: String
}

private struct UIWorkerSummary: Encodable {
    let id: String
    let name: String
    let status_raw: String
    let status: String
    let capabilities: String
    let last_seen: String
    let version: String
    let load: String
    let ram_mb: String
    let can_approve: Bool
    let can_heartbeat: Bool
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
    let analysis_champs_json: String
    let analysis_validation_flags: String
}

private struct UILocalIngestForm: Content {
    let pdf: File
    let tags: String?
}

private struct UIFolderIngestForm: Content {
    let input_folder: String
    let tags: String?
    let recursive: String?
    let max_files: String?
    let output_root: String?
}

private struct UIPresetCreateForm: Content {
    let id: String
    let name: String
    let name_format: String
    let class_code: String?
    let postprocess: String?
}

private struct UIRoutingSettingsForm: Content {
    let local_route_root: String?
    let default_destination_template: String?
    let default_name_format: String?
}

private struct UIRoutingRulesForm: Content {
    let rules_json: String
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

private struct UITaxonomyImportForm: Content {
    let taxonomy_id: String?
    let taxonomy_json: String
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

    app.on(.POST, "ui", "ingest", "local", body: .collect(maxSize: "48mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UILocalIngestForm.self)
            let filename = form.pdf.filename.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !filename.isEmpty else {
                throw Abort(.badRequest, reason: "Aucun fichier fourni.")
            }
            guard filename.lowercased().hasSuffix(".pdf") else {
                throw Abort(.badRequest, reason: "Seuls les fichiers PDF sont acceptés.")
            }
            guard form.pdf.data.readableBytes > 0 else {
                throw Abort(.badRequest, reason: "Le fichier PDF est vide.")
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
            try Data(buffer: form.pdf.data).write(to: destination, options: .atomic)

            let parsedTags = parseUploadTags(raw: form.tags)
            let requestBody = IngestRequest(
                fileURL: destination.path,
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
            let reason = abort.reason.isEmpty ? "Échec de l'import PDF." : abort.reason
            req.logger.warning("Échec ingestion UI.", metadata: [
                "reason": .string(reason)
            ])
            return req.redirect(to: "/ui?upload_error=\(urlQueryEncoded(reason))")
        } catch {
            req.logger.error("Échec ingestion UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui?upload_error=\(urlQueryEncoded("Erreur interne pendant l'import PDF."))")
        }
    }

    app.on(.POST, "ui", "ingest", "folder", body: .collect(maxSize: "2mb")) { req async throws -> Response in
        do {
            let form = try req.content.decode(UIFolderIngestForm.self)
            let inputFolderRaw = form.input_folder.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !inputFolderRaw.isEmpty else {
                throw Abort(.badRequest, reason: "Le dossier d'entrée est requis.")
            }

            let inputURL = URL(fileURLWithPath: inputFolderRaw, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw Abort(.badRequest, reason: "Le dossier d'entrée est introuvable sur le serveur API.")
            }

            let recursive = parseBooleanFlag(form.recursive, defaultValue: true)
            let maxFiles = parseMaxFiles(form.max_files)
            let tags = parseUploadTags(raw: form.tags)
            let files = try collectPDFFiles(in: inputURL, recursive: recursive, maxFiles: maxFiles)
            guard !files.isEmpty else {
                throw Abort(.badRequest, reason: "Aucun fichier PDF trouvé dans le dossier d'entrée.")
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

            return req.redirect(to: "/ui?upload_notice=\(urlQueryEncoded("\(ingested) PDF ajouté(s) depuis le dossier."))")
        } catch let abort as AbortError {
            return req.redirect(to: "/ui?upload_error=\(urlQueryEncoded(abort.reason))")
        } catch {
            req.logger.error("Échec ingestion dossier UI.", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return req.redirect(to: "/ui?upload_error=\(urlQueryEncoded("Erreur interne pendant l'import du dossier."))")
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
        let jobs = try await loadJobs(req: req, limit: 100)
        let workerCount = try await loadWorkerRecords(req: req).count
        let queueStats = await RedisQueueService.queueStats(application: req.application, logger: req.logger)
        let routingSettings = ConfigLoader.loadRoutingLocalSettings()
        let uploadNotice = req.query[String.self, at: "upload_notice"]
        let uploadError = req.query[String.self, at: "upload_error"]

        let counts = Dictionary(grouping: jobs, by: \.status)
        let context = UIDashboardContext(
            total_jobs: jobs.count,
            pending_jobs: counts["pending"]?.count ?? 0,
            running_jobs: counts["running"]?.count ?? 0,
            needs_review_jobs: counts["needs_review"]?.count ?? 0,
            completed_jobs: counts["completed"]?.count ?? 0,
            failed_jobs: counts["failed"]?.count ?? 0,
            cancelled_jobs: counts["cancelled"]?.count ?? 0,
            worker_count: workerCount,
            queue_ingest_depth: queueStats.ingest_depth,
            queue_dead_letter_depth: queueStats.dead_letter_depth,
            recent_jobs: Array(jobs.prefix(15)),
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

    app.get("ui", "jobs", ":id") { req async throws -> View in
        guard let id = req.parameters.get("id"),
              let jobID = UUID(uuidString: id) else {
            throw Abort(.badRequest, reason: "Identifiant de tâche invalide.")
        }
        let job = try await resolveUIJob(jobID: jobID, req: req)
        let preview = try await PreviewLoader.ensurePreview(jobId: jobID, req: req)
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
            download_searchable_url: "/v1/jobs/\(job.id.uuidString)/download/searchable",
            analysis_type_doc: job.analysisTypeDoc ?? "N/D",
            analysis_sujets: (job.analysisSujets ?? []).isEmpty ? "N/D" : (job.analysisSujets ?? []).joined(separator: ", "),
            analysis_champs_json: prettyPrintedJSON(job.analysisChamps),
            analysis_validation_flags: extractValidationFlags(job.analysisChamps)
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
        return UIWorkerSummary(
            id: worker.id.uuidString,
            name: worker.name,
            status_raw: rawStatus,
            status: localizedWorkerStatus(rawStatus),
            capabilities: worker.capabilities.joined(separator: ", "),
            last_seen: worker.lastSeen.map(formatTimestamp) ?? "-",
            version: worker.version ?? "-",
            load: worker.load.map { String(format: "%.2f", $0) } ?? "-",
            ram_mb: worker.ram_mb.map(String.init) ?? "-",
            can_approve: rawStatus == WorkerStatus.pending.rawValue,
            can_heartbeat: rawStatus == WorkerStatus.approved.rawValue
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

private func loadJobs(req: Request, limit: Int) async throws -> [UIJobSummary] {
    let jobs: [JobRecord]
    if let persisted = try? await JobPersistenceRepository.listJobs(limit: limit, on: req.db),
       !persisted.isEmpty {
        jobs = persisted
    } else {
        jobs = await req.application.appState.listJobs(limit: limit)
    }
    return jobs.map { job in
        UIJobSummary(
            id: job.id.uuidString,
            status: job.status.rawValue,
            status_label: localizedJobStatus(job.status.rawValue),
            file_url: job.fileURL,
            source_kind: localizedSourceKind(job.source.kind),
            confidence: job.confidence.map { String(format: "%.2f", $0) } ?? "-",
            suggested_class_code: job.suggestedClassCode ?? "N/D",
            updated_at: formatTimestamp(job.updatedAt)
        )
    }
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
        return "document.pdf"
    }
    return fallback
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
