import Vapor

func registerOpenAPIRoutes(_ app: Application) {
    app.get("v1", "openapi.json") { _ -> Response in
        let spec: [String: Any] = [
            "openapi": "3.1.0",
            "info": [
                "title": "Orchiviste API",
                "version": "0.3.0",
                "description": "MVP ingest -> preview -> analyse -> review -> routing -> events"
            ],
            "servers": [
                ["url": "http://127.0.0.1:8080"]
            ],
            "paths": [
                "/v1/openapi.json": [
                    "get": [
                        "summary": "OpenAPI 3.1 specification",
                        "responses": ["200": ["description": "OpenAPI document"]]
                    ]
                ],
                "/v1/health": [
                    "get": ["responses": ["200": ["description": "OK"]]]
                ],
                "/v1/ingest": [
                    "post": [
                        "summary": "Create ingest job",
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
                            "202": ["description": "Queued", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/IngestResponse"]]]],
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
                            "200": ["description": "Job", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/JobRecord"]]]],
                            "400": ["$ref": "#/components/responses/Error400"],
                            "404": ["$ref": "#/components/responses/Error404"]
                        ]
                    ]
                ],
                "/v1/jobs/{id}/cancel": [
                    "parameters": [["$ref": "#/components/parameters/JobID"]],
                    "post": [
                        "responses": [
                            "200": ["description": "Cancelled", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/JobCancelResponse"]]]],
                            "400": ["$ref": "#/components/responses/Error400"],
                            "404": ["$ref": "#/components/responses/Error404"],
                            "409": ["$ref": "#/components/responses/Error409"]
                        ]
                    ]
                ],
                "/v1/jobs/{id}/review": [
                    "parameters": [["$ref": "#/components/parameters/JobID"]],
                    "post": [
                        "summary": "Submit human review corrections",
                        "requestBody": [
                            "required": true,
                            "content": ["application/json": ["schema": ["$ref": "#/components/schemas/JobReviewRequest"]]]
                        ],
                        "responses": [
                            "200": ["description": "Reviewed job", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/JobRecord"]]]],
                            "400": ["$ref": "#/components/responses/Error400"],
                            "404": ["$ref": "#/components/responses/Error404"],
                            "409": ["$ref": "#/components/responses/Error409"]
                        ]
                    ]
                ],
                "/v1/jobs/{id}/download": [
                    "parameters": [["$ref": "#/components/parameters/JobID"]],
                    "get": [
                        "summary": "Explicit download action for source file",
                        "responses": [
                            "200": ["description": "File stream"],
                            "302": ["description": "SharePoint redirect"],
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
                            "200": ["description": "Worker enrolled", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/WorkerRecord"]]]],
                            "400": ["$ref": "#/components/responses/Error400"]
                        ]
                    ]
                ],
                "/v1/workers/{id}/approve": [
                    "parameters": [["$ref": "#/components/parameters/WorkerID"]],
                    "post": [
                        "responses": [
                            "200": ["description": "Worker approved", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/WorkerRecord"]]]],
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
                            "200": ["description": "Worker heartbeat", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/WorkerRecord"]]]],
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
                            "200": ["description": "Queue stats", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/QueueStatsResponse"]]]]
                        ]
                    ]
                ],
                "/v1/presets": [
                    "get": ["responses": ["200": ["description": "Preset list", "content": ["application/json": ["schema": ["type": "array", "items": ["$ref": "#/components/schemas/Preset"]]]]]]],
                    "post": [
                        "requestBody": ["required": true, "content": ["application/json": ["schema": ["$ref": "#/components/schemas/Preset"]]]],
                        "responses": ["200": ["description": "Preset saved", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/Preset"]]]]]
                    ]
                ],
                "/v1/analyse": [
                    "post": [
                        "requestBody": ["required": true, "content": ["application/json": ["schema": ["$ref": "#/components/schemas/AnalysisRequest"]]]],
                        "responses": [
                            "200": ["description": "Analyse response", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/AnalysisResponse"]]]],
                            "400": ["$ref": "#/components/responses/Error400"],
                            "500": ["$ref": "#/components/responses/Error500"]
                        ]
                    ]
                ],
                "/v1/preview/{id}/thumbnail": [
                    "parameters": [["$ref": "#/components/parameters/JobID"]],
                    "get": ["responses": ["200": ["description": "Thumbnail image"], "400": ["$ref": "#/components/responses/Error400"], "404": ["$ref": "#/components/responses/Error404"]]]
                ],
                "/v1/preview/{id}/page/{n}.jpg": [
                    "get": ["responses": ["200": ["description": "Preview page"], "400": ["$ref": "#/components/responses/Error400"], "404": ["$ref": "#/components/responses/Error404"]]],
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
                            "200": ["description": "Preview text", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/PreviewTextResponse"]]]],
                            "400": ["$ref": "#/components/responses/Error400"],
                            "404": ["$ref": "#/components/responses/Error404"]
                        ]
                    ]
                ],
                "/v1/preview/{id}/office": [
                    "parameters": [["$ref": "#/components/parameters/JobID"]],
                    "get": [
                        "responses": [
                            "302": ["description": "Office Online redirect"],
                            "400": ["$ref": "#/components/responses/Error400"],
                            "404": ["$ref": "#/components/responses/Error404"]
                        ]
                    ]
                ],
                "/v1/taxonomy/syged/import": [
                    "post": ["responses": ["200": ["description": "Taxonomy imported"]]]
                ],
                "/v1/taxonomy/{taxonomy_id}": [
                    "get": ["responses": ["200": ["description": "Taxonomy"]]],
                    "parameters": [["name": "taxonomy_id", "in": "path", "required": true]]
                ],
                "/v1/agenda/import": [
                    "post": ["responses": ["200": ["description": "Agenda imported"]]]
                ],
                "/v1/agenda/{session_id}": [
                    "get": ["responses": ["200": ["description": "Agenda"]]],
                    "parameters": [["name": "session_id", "in": "path", "required": true]]
                ],
                "/v1/route/{file_id}": [
                    "parameters": [["name": "file_id", "in": "path", "required": true, "schema": ["type": "string"]]],
                    "post": [
                        "responses": [
                            "200": ["description": "Routing response", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/RoutingResponse"]]]],
                            "400": ["$ref": "#/components/responses/Error400"],
                            "404": ["$ref": "#/components/responses/Error404"],
                            "409": ["$ref": "#/components/responses/Error409"]
                        ]
                    ]
                ],
                "/v1/events": [
                    "get": [
                        "parameters": [["name": "cursor", "in": "query", "required": false, "schema": ["type": "integer", "minimum": 0]]],
                        "responses": [
                            "200": ["description": "Events", "content": ["application/json": ["schema": ["$ref": "#/components/schemas/EventsResponse"]]]]
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
                        "description": "Bad request",
                        "content": ["application/json": ["schema": ["$ref": "#/components/schemas/ErrorEnvelope"]]]
                    ],
                    "Error401": [
                        "description": "Unauthorized",
                        "content": ["application/json": ["schema": ["$ref": "#/components/schemas/ErrorEnvelope"]]]
                    ],
                    "Error404": [
                        "description": "Not found",
                        "content": ["application/json": ["schema": ["$ref": "#/components/schemas/ErrorEnvelope"]]]
                    ],
                    "Error409": [
                        "description": "Conflict",
                        "content": ["application/json": ["schema": ["$ref": "#/components/schemas/ErrorEnvelope"]]]
                    ],
                    "Error500": [
                        "description": "Internal server error",
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
                    "RoutingResponse": [
                        "type": "object",
                        "properties": [
                            "file_id": ["type": "string"],
                            "class_code": ["type": "string"],
                            "target": ["$ref": "#/components/schemas/RoutingTarget"],
                            "resolved_folder": ["type": "string"]
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
                    ]
                ]
            ],
            "webhooks": [
                "eventDelivered": [
                    "post": [
                        "summary": "Outgoing webhook for emitted events",
                        "requestBody": [
                            "required": true,
                            "content": ["application/json": ["schema": ["$ref": "#/components/schemas/EventRecord"]]]
                        ],
                        "parameters": [
                            ["name": "x-orchiviste-signature", "in": "header", "required": true, "schema": ["type": "string"]],
                            ["name": "x-orchiviste-timestamp", "in": "header", "required": true, "schema": ["type": "string"]]
                        ],
                        "responses": [
                            "200": ["description": "Webhook received"]
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
