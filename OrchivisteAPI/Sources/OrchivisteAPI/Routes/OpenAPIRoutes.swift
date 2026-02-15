import Vapor

func registerOpenAPIRoutes(_ app: Application) {
    app.get("v1", "openapi.json") { _ -> Response in
        let spec: [String: Any] = [
            "openapi": "3.1.0",
            "info": ["title": "Orchiviste API", "version": "0.1.0"],
            "paths": [
                "/v1/health": [
                    "get": ["responses": ["200": ["description": "OK"]]]
                ],
                "/v1/ingest": [
                    "post": [
                        "requestBody": ["required": true],
                        "responses": ["202": ["description": "Queued"]]
                    ]
                ],
                "/v1/jobs/{id}": [
                    "get": ["responses": ["200": ["description": "Job"]]],
                    "parameters": [["name": "id", "in": "path", "required": true]]
                ],
                "/v1/jobs/{id}/cancel": [
                    "post": ["responses": ["200": ["description": "Cancelled"]]],
                    "parameters": [["name": "id", "in": "path", "required": true]]
                ],
                "/v1/workers/enroll": [
                    "post": ["responses": ["200": ["description": "Worker enrolled"]]]
                ],
                "/v1/workers/{id}/approve": [
                    "post": ["responses": ["200": ["description": "Worker approved"]]],
                    "parameters": [["name": "id", "in": "path", "required": true]]
                ],
                "/v1/workers/{id}/heartbeat": [
                    "post": ["responses": ["200": ["description": "Worker heartbeat"]]],
                    "parameters": [["name": "id", "in": "path", "required": true]]
                ],
                "/v1/presets": [
                    "get": ["responses": ["200": ["description": "Preset list"]]],
                    "post": ["responses": ["200": ["description": "Preset saved"]]]
                ],
                "/v1/analyse": [
                    "post": ["responses": ["200": ["description": "Analyse response"]]]
                ],
                "/v1/preview/{id}/thumbnail": [
                    "get": ["responses": ["200": ["description": "Thumbnail"]]],
                    "parameters": [["name": "id", "in": "path", "required": true]]
                ],
                "/v1/preview/{id}/page/{n}.jpg": [
                    "get": ["responses": ["200": ["description": "Preview page"]]],
                    "parameters": [
                        ["name": "id", "in": "path", "required": true],
                        ["name": "n", "in": "path", "required": true]
                    ]
                ],
                "/v1/preview/{id}/text": [
                    "get": ["responses": ["200": ["description": "Preview text"]]]
                ],
                "/v1/preview/{id}/office": [
                    "get": ["responses": ["302": ["description": "Office Online"]]]
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
                    "post": ["responses": ["200": ["description": "Routing response"]]],
                    "parameters": [["name": "file_id", "in": "path", "required": true]]
                ],
                "/v1/events": [
                    "get": ["responses": ["200": ["description": "Events"]]]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: spec, options: [.prettyPrinted])
        var res = Response(status: .ok)
        res.headers.replaceOrAdd(name: .contentType, value: "application/json")
        res.body = .init(data: data)
        return res
    }
}
