import Vapor

func registerOpenAPIRoutes(_ app: Application) {
    app.get("v1", "openapi.json") { _ -> Response in
        let spec: [String: Any] = [
            "openapi": "3.1.0",
            "info": [
                "title": "Orchiviste API",
                "version": "0.3.0",
                "description": "MVP ingestion -> aperçu -> analyse -> revue -> routage -> événements"
            ],
            "servers": [
                ["url": "http://127.0.0.1:28780"]
            ],
            "paths": [
                "/v1/openapi.json": [
                    "get": [
                        "summary": "Specification OpenAPI 3.1",
                        "responses": ["200": ["description": "Document OpenAPI"]]
                    ]
                ],
                "/v1/health": [
                    "get": ["responses": ["200": ["description": "Service disponible"]]]
                ],
                "/v1/metrics": [
                    "get": [
                        "summary": "Métriques API en mémoire (MVP)",
                        "responses": [
                            "200": [
                                "description": "Instantané des métriques de requêtes",
                                "content": ["application/json": ["schema": ["$ref": "#/components/schemas/RequestMetricsSnapshot"]]]
                            ]
                        ]
                    ]
                ],
                "/v1/ingest": [
                    "post": [
                        "summary": "Creer une tâche d'ingestion",
                        "parameters": [
                            [
                                "name": "Idempotency-Key",
                                "in": "header",
                                "required": false,
                                "schema": ["type": "string"]
                            ]
                        ],
                        "requestBody": ["required": true],
                        "responses": [
                            "202": ["description": "En file d'attente", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/IngestResponse"]]]],
                            "400": ["$ref": "#/components/responses/Error400"],
                            "409": ["$ref": "#/components/responses/Error409"],
                            "500": ["$ref": "#/components/responses/Error500"]
                        ]
                    ]
                ],
                "/v1/jobs/{id}": [
                    "parameters": [["$ref": "#/components/parameters/JobID"]],
                    "get": [
                        "responses": [
                            "200": ["description": "Tâche", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/JobRecord"]]]],
                            "400": ["$ref": "#/components/responses/Error400"],
                            "404": ["$ref": "#/components/responses/Error404"]
                        ]
                    ]
                ],
                "/v1/jobs/{id}/cancel": [
                    "parameters": [["$ref": "#/components/parameters/JobID"]],
                    "post": [
                        "responses": [
                            "200": ["description": "Annulée", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/JobCancelResponse"]]]],
                            "400": ["$ref": "#/components/responses/Error400"],
                            "404": ["$ref": "#/components/responses/Error404"],
                            "409": ["$ref": "#/components/responses/Error409"]
                        ]
                    ]
                ],
                "/v1/jobs/{id}/review": [
                    "parameters": [["$ref": "#/components/parameters/JobID"]],
                    "post": [
                        "summary": "Soumettre les corrections de revue humaine",
                        "requestBody": [
                            "required": true,
                            "content": ["application/json": ["schema": ["$ref": "#/components/schemas/JobReviewRequest"]]]
                        ],
                        "responses": [
                            "200": ["description": "Tâche revue", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/JobRecord"]]]],
                            "400": ["$ref": "#/components/responses/Error400"],
                            "404": ["$ref": "#/components/responses/Error404"],
                            "409": ["$ref": "#/components/responses/Error409"]
                        ]
                    ]
                ],
                "/v1/jobs/{id}/download": [
                    "parameters": [["$ref": "#/components/parameters/JobID"]],
                    "get": [
                        "summary": "Telechargement explicite du fichier source",
                        "responses": [
                            "200": ["description": "Flux fichier"],
                            "302": ["description": "Redirection SharePoint"],
                            "400": ["$ref": "#/components/responses/Error400"],
                            "404": ["$ref": "#/components/responses/Error404"]
                        ]
                    ]
                ],
                "/v1/jobs/{id}/download/searchable": [
                    "parameters": [["$ref": "#/components/parameters/JobID"]],
                    "get": [
                        "summary": "Telechargement explicite du PDF OCR selectionnable",
                        "responses": [
                            "200": ["description": "Flux fichier PDF OCR"],
                            "302": ["description": "Redirection SharePoint"],
                            "400": ["$ref": "#/components/responses/Error400"],
                            "404": ["$ref": "#/components/responses/Error404"]
                        ]
                    ]
                ],
                "/v1/workers/enroll": [
                    "post": [
                        "requestBody": [
                            "required": true,
                            "content": ["application/json": ["schema": ["$ref": "#/components/schemas/WorkerEnrollRequest"]]]
                        ],
                        "responses": [
                            "200": ["description": "Agent enregistre", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/WorkerRecord"]]]],
                            "400": ["$ref": "#/components/responses/Error400"]
                        ]
                    ]
                ],
                "/v1/workers/{id}/approve": [
                    "parameters": [["$ref": "#/components/parameters/WorkerID"]],
                    "post": [
                        "responses": [
                            "200": ["description": "Agent approuvé", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/WorkerRecord"]]]],
                            "400": ["$ref": "#/components/responses/Error400"],
                            "404": ["$ref": "#/components/responses/Error404"]
                        ]
                    ]
                ],
                "/v1/workers/{id}/heartbeat": [
                    "parameters": [["$ref": "#/components/parameters/WorkerID"]],
                    "post": [
                        "requestBody": [
                            "required": true,
                            "content": ["application/json": ["schema": ["$ref": "#/components/schemas/WorkerHeartbeatRequest"]]]
                        ],
                        "responses": [
                            "200": ["description": "Signal agent", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/WorkerRecord"]]]],
                            "400": ["$ref": "#/components/responses/Error400"],
                            "401": ["$ref": "#/components/responses/Error401"],
                            "404": ["$ref": "#/components/responses/Error404"],
                            "409": ["$ref": "#/components/responses/Error409"]
                        ]
                    ]
                ],
                "/v1/workers/queue/stats": [
                    "get": [
                        "responses": [
                            "200": ["description": "Statistiques de file", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/QueueStatsResponse"]]]]
                        ]
                    ]
                ],
                "/v1/presets": [
                    "get": ["responses": ["200": ["description": "Liste des préréglages", "content": ["application/json": ["schema": ["type": "array", "items": ["$ref": "#/components/schemas/Preset"]]]]]]],
                    "post": [
                        "requestBody": ["required": true, "content": ["application/json": ["schema": ["$ref": "#/components/schemas/Preset"]]]],
                        "responses": [
                            "200": ["description": "Préréglage enregistre", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/Preset"]]]],
                            "400": ["$ref": "#/components/responses/Error400"],
                            "500": ["$ref": "#/components/responses/Error500"]
                        ]
                    ]
                ],
                "/v1/analyse": [
                    "post": [
                        "requestBody": ["required": true, "content": ["application/json": ["schema": ["$ref": "#/components/schemas/AnalysisRequest"]]]],
                        "responses": [
                            "200": ["description": "Réponse d'analyse", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/AnalysisResponse"]]]],
                            "400": ["$ref": "#/components/responses/Error400"],
                            "500": ["$ref": "#/components/responses/Error500"]
                        ]
                    ]
                ],
                "/v1/preview/{id}/thumbnail": [
                    "parameters": [["$ref": "#/components/parameters/JobID"]],
                    "get": ["responses": ["200": ["description": "Image miniature"], "400": ["$ref": "#/components/responses/Error400"], "404": ["$ref": "#/components/responses/Error404"]]]
                ],
                "/v1/preview/{id}/page/{n}.jpg": [
                    "get": ["responses": ["200": ["description": "Page d'aperçu"], "400": ["$ref": "#/components/responses/Error400"], "404": ["$ref": "#/components/responses/Error404"]]],
                    "parameters": [
                        ["$ref": "#/components/parameters/JobID"],
                        ["name": "n", "in": "path", "required": true, "schema": ["type": "integer"]]
                    ]
                ],
                "/v1/preview/{id}/text": [
                    "parameters": [["$ref": "#/components/parameters/JobID"]],
                    "get": [
                        "parameters": [["name": "page", "in": "query", "required": false, "schema": ["type": "integer", "minimum": 1]]],
                        "responses": [
                            "200": ["description": "Texte d'aperçu", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/PreviewTextResponse"]]]],
                            "400": ["$ref": "#/components/responses/Error400"],
                            "404": ["$ref": "#/components/responses/Error404"]
                        ]
                    ]
                ],
                "/v1/preview/{id}/office": [
                    "parameters": [["$ref": "#/components/parameters/JobID"]],
                    "get": [
                        "responses": [
                            "302": ["description": "Redirection Office Online"],
                            "400": ["$ref": "#/components/responses/Error400"],
                            "404": ["$ref": "#/components/responses/Error404"]
                        ]
                    ]
                ],
                "/v1/taxonomy/syged/import": [
                    "post": ["responses": ["200": ["description": "Taxonomie importee"]]]
                ],
                "/v1/taxonomy/{taxonomy_id}": [
                    "get": ["responses": ["200": ["description": "Taxonomie"]]],
                    "parameters": [["name": "taxonomy_id", "in": "path", "required": true]]
                ],
                "/v1/agenda/import": [
                    "post": ["responses": ["200": ["description": "Ordre du jour importe"]]]
                ],
                "/v1/agenda/{session_id}": [
                    "get": ["responses": ["200": ["description": "Ordre du jour"]]],
                    "parameters": [["name": "session_id", "in": "path", "required": true]]
                ],
                "/v1/route/{file_id}": [
                    "parameters": [["name": "file_id", "in": "path", "required": true, "schema": ["type": "string"]]],
                    "post": [
                        "requestBody": [
                            "required": false,
                            "content": ["application/json": ["schema": ["$ref": "#/components/schemas/RoutingRequest"]]]
                        ],
                        "responses": [
                            "200": ["description": "Réponse de routage", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/RoutingResponse"]]]],
                            "400": ["$ref": "#/components/responses/Error400"],
                            "404": ["$ref": "#/components/responses/Error404"],
                            "409": ["$ref": "#/components/responses/Error409"],
                            "500": ["$ref": "#/components/responses/Error500"]
                        ]
                    ]
                ],
                "/v1/events": [
                    "get": [
                        "parameters": [["name": "cursor", "in": "query", "required": false, "schema": ["type": "integer", "minimum": 0]]],
                        "responses": [
                            "200": ["description": "Evenements", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/EventsResponse"]]]],
                            "400": ["$ref": "#/components/responses/Error400"]
                        ]
                    ]
                ]
            ],
            "components": [
                "parameters": [
                    "JobID": ["name": "id", "in": "path", "required": true, "schema": ["type": "string", "format": "uuid"]],
                    "WorkerID": ["name": "id", "in": "path", "required": true, "schema": ["type": "string", "format": "uuid"]]
                ],
                "responses": [
                    "Error400": [
                        "description": "Requete invalide",
                        "content": ["application/json": ["schema": ["$ref": "#/components/schemas/ErrorEnvelope"]]]
                    ],
                    "Error401": [
                        "description": "Non autorise",
                        "content": ["application/json": ["schema": ["$ref": "#/components/schemas/ErrorEnvelope"]]]
                    ],
                    "Error404": [
                        "description": "Introuvable",
                        "content": ["application/json": ["schema": ["$ref": "#/components/schemas/ErrorEnvelope"]]]
                    ],
                    "Error409": [
                        "description": "Conflit",
                        "content": ["application/json": ["schema": ["$ref": "#/components/schemas/ErrorEnvelope"]]]
                    ],
                    "Error500": [
                        "description": "Erreur interne serveur",
                        "content": ["application/json": ["schema": ["$ref": "#/components/schemas/ErrorEnvelope"]]]
                    ]
                ],
                "schemas": [
                    "ErrorEnvelope": [
                        "type": "object",
                        "properties": [
                            "error": ["type": "boolean"],
                            "reason": ["type": "string"]
                        ]
                    ],
                    "IngestResponse": [
                        "type": "object",
                        "properties": [
                            "status": ["type": "string"],
                            "taskId": ["type": "string", "format": "uuid"]
                        ]
                    ],
                    "JobSource": [
                        "type": "object",
                        "properties": [
                            "kind": ["type": "string"],
                            "url": ["type": "string"],
                            "site": ["type": "string"],
                            "library": ["type": "string"],
                            "itemId": ["type": "string"]
                        ]
                    ],
                    "JobStepTimestamps": [
                        "type": "object",
                        "properties": [
                            "ingestReceived": ["type": "string", "format": "date-time"],
                            "previewReady": ["type": "string", "format": "date-time"],
                            "analysed": ["type": "string", "format": "date-time"],
                            "routed": ["type": "string", "format": "date-time"],
                            "completed": ["type": "string", "format": "date-time"]
                        ]
                    ],
                    "JobRecord": [
                        "type": "object",
                        "properties": [
                            "id": ["type": "string", "format": "uuid"],
                            "status": ["type": "string"],
                            "fileURL": ["type": "string"],
                            "source": ["$ref": "#/components/schemas/JobSource"],
                            "tags": ["type": "array", "items": ["type": "string"]],
                            "createdAt": ["type": "string", "format": "date-time"],
                            "updatedAt": ["type": "string", "format": "date-time"],
                            "steps": ["$ref": "#/components/schemas/JobStepTimestamps"],
                            "suggestedPreset": ["type": "string"],
                            "suggestedClassCode": ["type": "string"],
                            "analysisTypeDoc": ["type": "string"],
                            "analysisSujets": ["type": "array", "items": ["type": "string"]],
                            "analysisChamps": ["type": "object", "additionalProperties": ["type": "string"]],
                            "confidence": ["type": "number"],
                            "needsReview": ["type": "boolean"]
                        ]
                    ],
                    "JobCancelResponse": [
                        "type": "object",
                        "properties": [
                            "id": ["type": "string", "format": "uuid"],
                            "status": ["type": "string"]
                        ]
                    ],
                    "JobReviewRequest": [
                        "type": "object",
                        "properties": [
                            "corrected_fields": ["type": "object", "additionalProperties": ["type": "string"]],
                            "corrected_class_code": ["type": "string"],
                            "corrected_preset": ["type": "string"],
                            "comment": ["type": "string"]
                        ]
                    ],
                    "WorkerEnrollRequest": [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string"],
                            "capabilities": ["type": "array", "items": ["type": "string"]]
                        ]
                    ],
                    "WorkerHeartbeatRequest": [
                        "type": "object",
                        "properties": [
                            "version": ["type": "string"],
                            "load": ["type": "number"],
                            "ram_mb": ["type": "integer"],
                            "capabilities": ["type": "array", "items": ["type": "string"]]
                        ]
                    ],
                    "WorkerRecord": [
                        "type": "object",
                        "properties": [
                            "id": ["type": "string", "format": "uuid"],
                            "name": ["type": "string"],
                            "status": ["type": "string"],
                            "capabilities": ["type": "array", "items": ["type": "string"]],
                            "lastSeen": ["type": "string", "format": "date-time"],
                            "version": ["type": "string"],
                            "load": ["type": "number"],
                            "ram_mb": ["type": "integer"],
                            "token": ["type": "string"]
                        ]
                    ],
                    "Preset": [
                        "type": "object",
                        "properties": [
                            "id": ["type": "string"],
                            "name": ["type": "string"],
                            "name_format": ["type": "string"],
                            "class_code": ["type": "string"],
                            "postprocess": ["type": "array", "items": ["type": "string"]]
                        ]
                    ],
                    "AnalysisRequest": [
                        "type": "object",
                        "properties": [
                            "file_id": ["type": "string"],
                            "text": ["type": "string"],
                            "source": ["$ref": "#/components/schemas/JobSource"],
                            "lang": ["type": "string"],
                            "preset_id": ["type": "string"],
                            "policy": [
                                "type": "object",
                                "properties": ["min_confidence": ["type": "number"], "max_latency_ms": ["type": "integer"]]
                            ]
                        ]
                    ],
                    "AnalysisResponse": [
                        "type": "object",
                        "properties": [
                            "type_doc": ["type": "string"],
                            "sujets": ["type": "array", "items": ["type": "string"]],
                            "structure": [
                                "type": "object",
                                "properties": ["has_signature": ["type": "boolean"], "pages": ["type": "integer"]]
                            ],
                            "champs": ["type": "object", "additionalProperties": ["type": "string"]],
                            "confidence": ["type": "number"],
                            "suggested_preset": ["type": "string"],
                            "suggested_class_code": ["type": "string"],
                            "explanations": [
                                "type": "object",
                                "properties": [
                                    "matched_rules": ["type": "array", "items": ["type": "string"]],
                                    "top_nodes": ["type": "array", "items": ["type": "string"]]
                                ]
                            ]
                        ]
                    ],
                    "PreviewTextResponse": [
                        "type": "object",
                        "properties": [
                            "page": ["type": "integer"],
                            "text": ["type": "string"]
                        ]
                    ],
                    "RoutingTarget": [
                        "type": "object",
                        "properties": [
                            "site": ["type": "string"],
                            "library": ["type": "string"],
                            "folder_expr": ["type": "string"],
                            "metadata": ["type": "object", "additionalProperties": ["type": "string"]]
                        ]
                    ],
                    "RoutingRequest": [
                        "type": "object",
                        "properties": [
                            "class_code": ["type": "string"],
                            "preset_id": ["type": "string"],
                            "destination_folder": ["type": "string"],
                            "name_format": ["type": "string"]
                        ]
                    ],
                    "RoutingResponse": [
                        "type": "object",
                        "properties": [
                            "file_id": ["type": "string"],
                            "class_code": ["type": "string"],
                            "target": ["$ref": "#/components/schemas/RoutingTarget"],
                            "resolved_folder": ["type": "string"],
                            "mode": ["type": "string", "enum": ["stub", "graph", "local"]],
                            "destination_url": ["type": "string"],
                            "moved_item_id": ["type": "string"],
                            "destination_local_path": ["type": "string"],
                            "resolved_file_name": ["type": "string"]
                        ]
                    ],
                    "EventRecord": [
                        "type": "object",
                        "properties": [
                            "id": ["type": "integer"],
                            "type": ["type": "string"],
                            "created_at": ["type": "string", "format": "date-time"],
                            "payload": ["type": "object", "additionalProperties": ["type": "string"]]
                        ]
                    ],
                    "EventsResponse": [
                        "type": "object",
                        "properties": [
                            "cursor": ["type": "integer"],
                            "events": ["type": "array", "items": ["$ref": "#/components/schemas/EventRecord"]]
                        ]
                    ],
                    "QueueStatsResponse": [
                        "type": "object",
                        "properties": [
                            "ingest_depth": ["type": "integer"],
                            "dead_letter_depth": ["type": "integer"]
                        ]
                    ],
                    "LatencySnapshot": [
                        "type": "object",
                        "properties": [
                            "avg": ["type": "number"],
                            "max": ["type": "number"]
                        ]
                    ],
                    "RouteMetricSnapshot": [
                        "type": "object",
                        "properties": [
                            "route": ["type": "string"],
                            "count": ["type": "integer"],
                            "avg_ms": ["type": "number"],
                            "max_ms": ["type": "number"]
                        ]
                    ],
                    "RequestMetricsSnapshot": [
                        "type": "object",
                        "properties": [
                            "started_at": ["type": "string", "format": "date-time"],
                            "uptime_s": ["type": "number"],
                            "total_requests": ["type": "integer"],
                            "in_flight": ["type": "integer"],
                            "by_status": ["type": "object", "additionalProperties": ["type": "integer"]],
                            "by_method": ["type": "object", "additionalProperties": ["type": "integer"]],
                            "top_routes": ["type": "array", "items": ["$ref": "#/components/schemas/RouteMetricSnapshot"]],
                            "latency_ms": ["$ref": "#/components/schemas/LatencySnapshot"]
                        ]
                    ]
                ]
            ],
            "webhooks": [
                "eventDelivered": [
                    "post": [
                        "summary": "Webhook sortant pour les événements émis",
                        "requestBody": [
                            "required": true,
                            "content": ["application/json": ["schema": ["$ref": "#/components/schemas/EventRecord"]]]
                        ],
                        "parameters": [
                            ["name": "x-orchiviste-signature", "in": "header", "required": true, "schema": ["type": "string"]],
                            ["name": "x-orchiviste-timestamp", "in": "header", "required": true, "schema": ["type": "string"]]
                        ],
                        "responses": [
                            "200": ["description": "Webhook reçu"]
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: spec, options: [.prettyPrinted])
        let res = Response(status: .ok)
        res.headers.replaceOrAdd(name: .contentType, value: "application/json")
        res.body = .init(data: data)
        return res
    }
}
