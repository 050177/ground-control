import Foundation

public struct Board: Codable, Sendable, Equatable {
    public var flights: [Flight]
    public var nextFlightNumber: Int

    public init(flights: [Flight] = [], nextFlightNumber: Int = 1) {
        self.flights = flights
        self.nextFlightNumber = nextFlightNumber
    }
}

/// Single-writer store for the departures board. The app holds the only
/// instance; gc-mcp reaches it through the HTTP API. JSON on disk, atomic writes.
public final class BoardStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    public private(set) var board: Board

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? ServerConfig.appSupportDirectory.appendingPathComponent("board.json")
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? BoardStore.decoder.decode(Board.self, from: data) {
            board = decoded
        } else {
            board = Board()
        }
    }

    /// Mutate the board under lock, persist atomically, return the closure's result.
    @discardableResult
    public func update<T>(_ mutate: (inout Board) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        let result = mutate(&board)
        persist()
        return result
    }

    private func persist() {
        do {
            let data = try BoardStore.encoder.encode(board)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            FileHandle.standardError.write("BoardStore persist failed: \(error)\n".data(using: .utf8)!)
        }
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
