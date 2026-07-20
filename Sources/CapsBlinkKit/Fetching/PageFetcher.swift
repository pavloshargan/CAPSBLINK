import Foundation

public enum FetchError: LocalizedError {
    case notHTTP
    case badStatus(Int)
    case undecodableBody

    public var errorDescription: String? {
        switch self {
        case .notHTTP: return "The URL is not an HTTP(S) resource"
        case .badStatus(let code): return "Server returned HTTP \(code)"
        case .undecodableBody: return "Could not decode the response body as text"
        }
    }
}

public enum FetchResult: Sendable {
    case content(String)
    /// Server answered 304 to a conditional request — the page did not change.
    case notModified
}

/// Downloads pages with polite conditional requests (ETag / Last-Modified),
/// so unchanged pages cost a 304 round-trip and never reach the extractor.
public actor PageFetcher {
    private struct Validators {
        var etag: String?
        var lastModified: String?
    }

    private let session: URLSession
    private var validators: [URL: Validators] = [:]

    public init(timeout: TimeInterval = 30) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = [
            "User-Agent": "CapsBlink/1.0 (macOS page watcher; +https://github.com/pavloshargan/CAPSBLINK)"
        ]
        session = URLSession(configuration: configuration)
    }

    public func fetch(_ url: URL) async throws -> FetchResult {
        var request = URLRequest(url: url)
        if let known = validators[url] {
            if let etag = known.etag {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }
            if let lastModified = known.lastModified {
                request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
            }
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FetchError.notHTTP
        }
        if http.statusCode == 304 {
            return .notModified
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FetchError.badStatus(http.statusCode)
        }

        validators[url] = Validators(
            etag: http.value(forHTTPHeaderField: "ETag"),
            lastModified: http.value(forHTTPHeaderField: "Last-Modified")
        )

        guard let body = Self.decode(data, contentTypeHeader: http.value(forHTTPHeaderField: "Content-Type")) else {
            throw FetchError.undecodableBody
        }
        return .content(body)
    }

    /// Forget stored validators (e.g. when the user switches URLs).
    public func reset() {
        validators.removeAll()
    }

    static func decode(_ data: Data, contentTypeHeader: String?) -> String? {
        if let charset = contentTypeHeader?.components(separatedBy: "charset=").dropFirst().first {
            let name = charset.components(separatedBy: ";").first?
                .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"'"))) ?? ""
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
                if let text = String(data: data, encoding: encoding) {
                    return text
                }
            }
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }
}
