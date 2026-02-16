import Vapor

enum RangeResponse {
    static func make(req: Request, data: Data, contentType: HTTPMediaType) -> Response {
        let res = Response(status: .ok)
        res.headers.replaceOrAdd(name: .contentType, value: contentType.serialize())
        res.headers.replaceOrAdd(name: "Accept-Ranges", value: "bytes")

        guard let rangeHeader = req.headers.first(name: .range),
              rangeHeader.hasPrefix("bytes=") else {
            res.body = .init(data: data)
            return res
        }

        let bytes = String(rangeHeader.dropFirst("bytes=".count))
        let parts = bytes.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let startPart = parts.first,
              let start = Int(startPart),
              start >= 0 else {
            return Response(status: .rangeNotSatisfiable)
        }

        let end: Int
        if parts.count > 1, let endPart = parts.last, !endPart.isEmpty, let parsedEnd = Int(endPart) {
            end = min(parsedEnd, data.count - 1)
        } else {
            end = data.count - 1
        }

        guard start <= end, start < data.count else {
            return Response(status: .rangeNotSatisfiable)
        }

        let slice = data.subdata(in: start..<(end + 1))
        res.status = .partialContent
        res.headers.replaceOrAdd(name: "Content-Range", value: "bytes \(start)-\(end)/\(data.count)")
        res.body = .init(data: slice)
        return res
    }
}
