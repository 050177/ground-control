import Foundation
import GCCore
import Network

/// Loopback-only HTTP server. Two consumers:
///   - claude http hooks  → POST /hook
///   - gc-mcp             → GET/POST/PATCH /api/flights[…]
/// Bearer-token authenticated; the token lives in server.json next to the port.
/// Minimal HTTP/1.1 implementation (no keep-alive) — sufficient for both.
final class HookServer: @unchecked Sendable {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "gc.hookserver", qos: .userInitiated)
    private let board: BoardStore

    /// Called on the main actor with each decoded hook event.
    var onHook: @MainActor (HookEvent) -> Void = { _ in }
    /// Called on the main actor when the board changes via the API.
    var onBoardChanged: @MainActor (Board) -> Void = { _ in }
    /// Called on the main actor when an agent sets the preview URL via the MCP tool.
    var onPreviewURL: @MainActor (String) -> Void = { _ in }

    private(set) var config: ServerConfig?

    init(board: BoardStore) {
        self.board = board
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .loopback

        let listener = try NWListener(using: params, on: .any)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = listener.port {
                    let config = ServerConfig.publish(port: Int(port.rawValue))
                    self?.config = config
                    print("[hook-server] ready on 127.0.0.1:\(port.rawValue)")
                }
            case let .failed(error):
                print("[hook-server] failed: \(error)")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
    }

    // MARK: - Connection handling

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) {
            [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let request = Self.parseRequest(buffer) {
                self.route(request, connection: connection)
                return // response sent; connection closes
            }
            if isComplete || error != nil || buffer.count > 4 << 20 {
                Self.respond(connection, status: 400, body: "bad request")
                return
            }
            self.receive(on: connection, buffer: buffer)
        }
    }

    // MARK: - Routing

    private func route(_ request: Request, connection: NWConnection) {
        guard let token = config?.token,
              request.headers["authorization"] == "Bearer \(token)" else {
            Self.respond(connection, status: 401, body: #"{"error":"unauthorized"}"#)
            return
        }

        let segments = request.path.split(separator: "/").map(String.init)
        let method = request.method

        if method == "POST", segments == ["hook"] {
            guard let event = try? JSONDecoder().decode(HookEvent.self, from: request.body) else {
                Self.respond(connection, status: 422, body: #"{"error":"bad hook payload"}"#)
                return
            }
            print("[hook] \(event.event) session=\(event.sessionId.prefix(8))")
            Self.respond(connection, status: 200, body: "{}")
            Task { @MainActor in self.onHook(event) }
            return
        }

        if method == "GET", segments == ["api", "flights"] {
            Self.respond(connection, status: 200, body: board.board)
            return
        }

        if method == "POST", segments == ["api", "flights"] {
            guard let create = try? JSONDecoder().decode(CreateFlight.self, from: request.body),
                  !create.title.isEmpty else {
                Self.respond(connection, status: 422, body: #"{"error":"title required"}"#)
                return
            }
            let flight = board.update { board in
                let flight = Flight(
                    number: board.nextFlightNumber,
                    title: create.title,
                    notes: create.notes ?? "",
                    assignedPane: create.assignedPane,
                    sessionId: create.sessionId,
                    projectPath: create.projectPath
                )
                board.nextFlightNumber += 1
                board.flights.append(flight)
                return flight
            }
            Self.respond(connection, status: 201, body: flight)
            Task { @MainActor in self.onBoardChanged(self.board.board) }
            return
        }

        if segments.count == 3, segments[0] == "api", segments[1] == "flights" {
            let idOrNumber = segments[2]

            if method == "GET" {
                let flight = board.board.flights.first { Self.matches($0, idOrNumber) }
                if let flight {
                    Self.respond(connection, status: 200, body: flight)
                } else {
                    Self.respond(connection, status: 404, body: #"{"error":"flight not found"}"#)
                }
                return
            }

            if method == "PATCH" {
                guard let patch = try? JSONDecoder().decode(PatchFlight.self, from: request.body) else {
                    Self.respond(connection, status: 422, body: #"{"error":"bad patch"}"#)
                    return
                }
                let updated = board.update { board -> Flight? in
                    guard let index = board.flights.firstIndex(where: { Self.matches($0, idOrNumber) }) else {
                        return nil
                    }
                    var flight = board.flights[index]
                    if let title = patch.title { flight.title = title }
                    if let notes = patch.notes { flight.notes = notes }
                    if let status = patch.status { flight.status = status }
                    if case let .some(pane) = patch.assignedPane { flight.assignedPane = pane }
                    if let sessionId = patch.sessionId { flight.sessionId = sessionId }
                    flight.updatedAt = Date()
                    board.flights[index] = flight
                    return flight
                }
                guard let updated else {
                    Self.respond(connection, status: 404, body: #"{"error":"flight not found"}"#)
                    return
                }
                Self.respond(connection, status: 200, body: updated)
                Task { @MainActor in self.onBoardChanged(self.board.board) }
                return
            }

            Self.respond(connection, status: 405, body: #"{"error":"method not allowed"}"#)
            return
        }

        if method == "POST", segments == ["api", "preview"] {
            struct PreviewPayload: Codable { var url: String }
            guard let payload = try? JSONDecoder().decode(PreviewPayload.self, from: request.body),
                  !payload.url.isEmpty else {
                Self.respond(connection, status: 422, body: #"{"error":"url required"}"#)
                return
            }
            Self.respond(connection, status: 200, body: #"{"ok":true}"#)
            Task { @MainActor in self.onPreviewURL(payload.url) }
            return
        }

        Self.respond(connection, status: 404, body: #"{"error":"not found"}"#)
    }

    private static func matches(_ flight: Flight, _ idOrNumber: String) -> Bool {
        flight.id.uuidString.lowercased() == idOrNumber.lowercased()
            || String(flight.number) == idOrNumber
    }

    private struct CreateFlight: Codable {
        var title: String
        var notes: String?
        var projectPath: String?
        var assignedPane: String?
        var sessionId: String?
    }

    private struct PatchFlight: Codable {
        var title: String?
        var notes: String?
        var status: FlightStatus?
        var assignedPane: String??
        var sessionId: String?
    }

    // MARK: - Minimal HTTP/1.1

    private struct Request {
        var method: String
        var path: String
        var headers: [String: String]
        var body: Data
    }

    /// Returns a fully-read request, or nil if more bytes are needed.
    private static func parseRequest(_ data: Data) -> Request? {
        guard let headerEnd = data.range(of: Data([13, 10, 13, 10])) else { return nil }
        let headerData = data[..<headerEnd.lowerBound]
        let body = data[headerEnd.upperBound...]

        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        var lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard body.count >= contentLength else { return nil }

        return Request(
            method: String(parts[0]).uppercased(),
            path: String(parts[1]),
            headers: headers,
            body: Data(body.prefix(contentLength))
        )
    }

    private static func respond(_ connection: NWConnection, status: Int, body: String) {
        respond(connection, status: status, body: Data(body.utf8))
    }

    private static func respond<T: Encodable>(_ connection: NWConnection, status: Int, body: T) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(body)) ?? Data("{}".utf8)
        respond(connection, status: status, body: data)
    }

    private static func respond(_ connection: NWConnection, status: Int, body: Data) {
        let phrases = [200: "OK", 201: "Created", 400: "Bad Request", 401: "Unauthorized",
                       404: "Not Found", 405: "Method Not Allowed", 422: "Unprocessable Entity"]
        let head = """
        HTTP/1.1 \(status) \(phrases[status] ?? "OK")\r
        Content-Type: application/json\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """
        var response = Data(head.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
