import Foundation

/// Describes a GGUF model: where to find it, how to verify it.
///
/// To swap the bundled model, change `ModelSpec.default` (and the matching
/// values in scripts/fetch-model.sh) — see docs/MODEL.md.
public struct ModelSpec: Sendable {
    public let fileName: String
    public let displayName: String
    /// SHA-256 of the GGUF file; downloads are refused on mismatch.
    public let sha256: String?
    /// Tried in order. First entry is this repo's release asset; the last is
    /// the upstream Hugging Face file as a fallback.
    public let downloadURLs: [URL]
    public let approximateBytes: Int64

    public init(
        fileName: String,
        displayName: String,
        sha256: String?,
        downloadURLs: [URL],
        approximateBytes: Int64
    ) {
        self.fileName = fileName
        self.displayName = displayName
        self.sha256 = sha256
        self.downloadURLs = downloadURLs
        self.approximateBytes = approximateBytes
    }

    public static let qwen25_15bInstructQ4KM = ModelSpec(
        fileName: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
        displayName: "Qwen2.5 1.5B Instruct (Q4_K_M)",
        sha256: "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e",
        downloadURLs: [
            URL(string: "https://github.com/pavloshargan/CAPSBLINK/releases/download/models-v1/qwen2.5-1.5b-instruct-q4_k_m.gguf")!,
            URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!,
        ],
        approximateBytes: 1_117_320_736
    )

    public static let `default` = qwen25_15bInstructQ4KM
}
