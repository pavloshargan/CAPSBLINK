import CryptoKit
import Foundation

public enum ModelError: LocalizedError {
    case allDownloadsFailed([String])
    case checksumMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .allDownloadsFailed(let messages):
            return "Model download failed: \(messages.joined(separator: "; "))"
        case .checksumMismatch(let expected, let actual):
            return "Model checksum mismatch (expected \(expected.prefix(12))…, got \(actual.prefix(12))…)"
        }
    }
}

/// Locates the GGUF model, downloading it on first launch when it is not
/// bundled with the app.
///
/// Search order:
/// 1. `CAPSBLINK_MODEL_PATH` environment variable (developer override)
/// 2. The app bundle's `Models/` resource directory (release builds bundle the model)
/// 3. `~/Library/Application Support/CapsBlink/Models/` (downloaded on demand)
public actor ModelManager {
    private let spec: ModelSpec
    private let bundle: Bundle

    public init(spec: ModelSpec = .default, bundle: Bundle = .main) {
        self.spec = spec
        self.bundle = bundle
    }

    public static func applicationSupportModelsDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CapsBlink/Models", isDirectory: true)
    }

    /// Returns the model location if it is already available locally.
    public func installedModelURL() -> URL? {
        if let override = ProcessInfo.processInfo.environment["CAPSBLINK_MODEL_PATH"] {
            let url = URL(fileURLWithPath: override)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        if let bundled = bundle.url(forResource: (spec.fileName as NSString).deletingPathExtension,
                                    withExtension: (spec.fileName as NSString).pathExtension,
                                    subdirectory: "Models") {
            return bundled
        }
        let downloaded = Self.applicationSupportModelsDirectory().appendingPathComponent(spec.fileName)
        if FileManager.default.fileExists(atPath: downloaded.path) {
            return downloaded
        }
        return nil
    }

    /// Returns a usable model path, downloading and verifying it if necessary.
    public func ensureModel(progress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        if let existing = installedModelURL() {
            return existing
        }
        var failures: [String] = []
        for url in spec.downloadURLs {
            do {
                return try await download(from: url, progress: progress)
            } catch {
                failures.append("\(url.host ?? "?"): \(error.localizedDescription)")
            }
        }
        throw ModelError.allDownloadsFailed(failures)
    }

    private func download(from remote: URL, progress: (@Sendable (Double) -> Void)?) async throws -> URL {
        let directory = Self.applicationSupportModelsDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(spec.fileName)
        let temporary = directory.appendingPathComponent(spec.fileName + ".download")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }

        let (bytes, response) = try await URLSession.shared.bytes(from: remote)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FetchError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let expectedLength = http.expectedContentLength > 0
            ? Double(http.expectedContentLength)
            : Double(spec.approximateBytes)

        var hasher = SHA256()
        var buffer = Data()
        buffer.reserveCapacity(1 << 20)
        var written: Int64 = 0
        var lastReportedPercent = -1

        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 20 {
                hasher.update(data: buffer)
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                let percent = Int(Double(written) / expectedLength * 100)
                if percent != lastReportedPercent {
                    lastReportedPercent = percent
                    progress?(min(0.99, Double(written) / expectedLength))
                }
            }
        }
        if !buffer.isEmpty {
            hasher.update(data: buffer)
            try handle.write(contentsOf: buffer)
        }
        try handle.close()

        if let expected = spec.sha256 {
            let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard actual == expected else {
                try? FileManager.default.removeItem(at: temporary)
                throw ModelError.checksumMismatch(expected: expected, actual: actual)
            }
        }

        _ = try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        progress?(1.0)
        return destination
    }
}
