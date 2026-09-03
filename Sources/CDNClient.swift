import Foundation
import UniformTypeIdentifiers

// MARK: - API models (see https://cdn.hackclub.com/openapi.json)

struct CDNUpload: Decodable {
    let id: String
    let filename: String
    let size: Int
    let content_type: String
    let url: String
}

struct CDNUser: Decodable {
    let id: String
    let email: String
    let name: String
    let storage_used: Int
    let storage_limit: Int?
    let quota_tier: String
}

struct CDNAPIError: Decodable {
    let error: String?
    let code: String?
    let message: String?
    let hint: String?
}

enum CDNError: LocalizedError {
    case noAPIKey
    case api(status: Int, body: CDNAPIError)
    case badResponse(status: Int, text: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key set. Open Settings and paste a key from cdn.hackclub.com/api_keys."
        case .api(_, let body):
            let message = body.message ?? body.error ?? "Upload failed."
            if let hint = body.hint, !hint.isEmpty { return "\(message) \(hint)" }
            return message
        case .badResponse(let status, let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Server returned HTTP \(status)." : "HTTP \(status): \(trimmed.prefix(200))"
        }
    }
}

// MARK: - Client

/// Streams uploads from a temp file so a multi-gigabyte drop never lands in memory,
/// and reports byte-level progress through a callback.
final class CDNClient: NSObject, URLSessionDataDelegate {
    static let shared = CDNClient()

    private final class TaskState {
        var received = Data()
        let onProgress: (Int64, Int64) -> Void
        let onFinish: (Result<(Int, Data), Error>) -> Void
        let scratch: URL?
        init(scratch: URL?, onProgress: @escaping (Int64, Int64) -> Void,
             onFinish: @escaping (Result<(Int, Data), Error>) -> Void) {
            self.scratch = scratch
            self.onProgress = onProgress
            self.onFinish = onFinish
        }
    }

    private let lock = NSLock()
    private var states: [Int: TaskState] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 60 * 60 * 6
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private static let base = URL(string: "https://cdn.hackclub.com")!

    // MARK: Account

    func me(apiKey: String) async throws -> CDNUser {
        var request = URLRequest(url: Self.base.appendingPathComponent("api/v4/me"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Self.decodeError(status: status, data: data) }
        return try JSONDecoder().decode(CDNUser.self, from: data)
    }

    // MARK: Upload

    /// Uploads one file. `onProgress` fires on a background queue with (bytesSent, bytesTotal).
    func upload(fileURL: URL, apiKey: String,
                onProgress: @escaping (Int64, Int64) -> Void) async throws -> CDNUpload {
        guard !apiKey.isEmpty else { throw CDNError.noAPIKey }

        let boundary = "----HackClubCDN\(UUID().uuidString)"
        let body = try Self.writeMultipartBody(fileURL: fileURL, fieldName: "file", boundary: boundary)
        var request = URLRequest(url: Self.base.appendingPathComponent("api/v4/upload"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (status, data) = try await withCheckedThrowingContinuation { continuation in
            let task = session.uploadTask(with: request, fromFile: body)
            let state = TaskState(scratch: body, onProgress: onProgress) { result in
                continuation.resume(with: result)
            }
            lock.lock(); states[task.taskIdentifier] = state; lock.unlock()
            task.resume()
        }

        guard status == 201 || status == 200 else { throw Self.decodeError(status: status, data: data) }
        return try JSONDecoder().decode(CDNUpload.self, from: data)
    }

    private static func decodeError(status: Int, data: Data) -> Error {
        if let body = try? JSONDecoder().decode(CDNAPIError.self, from: data),
           body.message != nil || body.error != nil {
            return CDNError.api(status: status, body: body)
        }
        return CDNError.badResponse(status: status, text: String(data: data, encoding: .utf8) ?? "")
    }

    // MARK: Multipart

    /// Writes the multipart envelope to a scratch file, copying the payload in 4 MB chunks.
    private static func writeMultipartBody(fileURL: URL, fieldName: String, boundary: String) throws -> URL {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("hc-cdn-\(UUID().uuidString).multipart")
        FileManager.default.createFile(atPath: scratch.path, contents: nil)

        let out = try FileHandle(forWritingTo: scratch)
        defer { try? out.close() }

        let name = fileURL.lastPathComponent
        let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"

        var header = "--\(boundary)\r\n"
        header += "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(escape(name))\"\r\n"
        header += "Content-Type: \(mime)\r\n\r\n"
        try out.write(contentsOf: Data(header.utf8))

        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 4 << 20), !chunk.isEmpty {
            try out.write(contentsOf: chunk)
        }

        try out.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        return scratch
    }

    private static func escape(_ filename: String) -> String {
        filename.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }

    // MARK: URLSession delegate

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        lock.lock(); let state = states[task.taskIdentifier]; lock.unlock()
        state?.onProgress(totalBytesSent, totalBytesExpectedToSend)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock(); states[dataTask.taskIdentifier]?.received.append(data); lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let state = states.removeValue(forKey: task.taskIdentifier); lock.unlock()
        guard let state else { return }
        if let scratch = state.scratch { try? FileManager.default.removeItem(at: scratch) }
        if let error {
            state.onFinish(.failure(error))
        } else {
            let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
            state.onFinish(.success((status, state.received)))
        }
    }
}
