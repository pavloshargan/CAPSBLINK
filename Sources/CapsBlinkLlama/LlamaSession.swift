import Foundation
import llama

public enum LlamaError: LocalizedError {
    case modelLoadFailed(String)
    case contextCreationFailed
    case tokenizationFailed
    case decodeFailed(Int32)
    case grammarParseFailed

    public var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let path): return "Failed to load model at \(path)"
        case .contextCreationFailed: return "Failed to create llama context"
        case .tokenizationFailed: return "Failed to tokenize prompt"
        case .decodeFailed(let code): return "llama_decode failed (\(code))"
        case .grammarParseFailed: return "Invalid GBNF grammar"
        }
    }
}

/// Owns one llama.cpp model + context for the lifetime of a watch session.
///
/// The model is loaded once (with full Metal offload when available) and every
/// `generate` call reuses it, clearing the KV cache in between. All llama.cpp
/// state is confined to this actor.
public actor LlamaSession {
    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private let contextTokens: Int32
    private let batchTokens: Int32

    /// llama.cpp process-wide setup, done exactly once. Also quiets llama's
    /// very chatty default logging down to warnings and errors.
    private static let backendReady: Void = {
        llama_log_set({ level, text, _ in
            guard let text, level.rawValue >= GGML_LOG_LEVEL_WARN.rawValue else { return }
            fputs(String(cString: text), stderr)
        }, nil)
        llama_backend_init()
    }()

    public init(modelPath: String, contextLength: Int32 = 4096) throws {
        _ = Self.backendReady

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 1_000 // offload everything Metal can take
        guard let model = llama_model_load_from_file(modelPath, modelParams) else {
            throw LlamaError.modelLoadFailed(modelPath)
        }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(contextLength)
        contextParams.n_batch = UInt32(contextLength) // decode prompts in one pass
        let threads = Int32(max(2, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
        contextParams.n_threads = threads
        contextParams.n_threads_batch = threads
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw LlamaError.contextCreationFailed
        }

        self.model = model
        self.context = context
        self.vocab = llama_model_get_vocab(model)
        self.contextTokens = contextLength
        self.batchTokens = Int32(llama_n_batch(context))
    }

    deinit {
        llama_free(context)
        llama_model_free(model)
    }

    /// Runs one chat completion. When `grammar` (GBNF) is provided, sampling
    /// is constrained to it — the model *cannot* produce output outside the
    /// grammar, which is how we guarantee structured JSON verdicts.
    public func generate(
        system: String,
        user: String,
        grammar: String? = nil,
        maxTokens: Int32 = 256
    ) throws -> String {
        // Fresh state per call; prompts are small and reuse across different
        // diffs would poison the cache anyway.
        llama_memory_clear(llama_get_memory(context), true)

        let prompt = applyChatTemplate(system: system, user: user)
        var tokens = try tokenize(prompt)

        // Guarantee room for generation, preferring to drop the middle of the
        // user content (start carries the instruction, end carries the diff).
        let budget = Int(contextTokens - maxTokens - 8)
        if tokens.count > budget {
            let head = tokens.prefix(budget / 2)
            let tail = tokens.suffix(budget - head.count)
            tokens = Array(head) + Array(tail)
        }

        try tokens.withUnsafeMutableBufferPointer { buffer in
            var offset = 0
            while offset < buffer.count {
                let chunk = min(Int(batchTokens), buffer.count - offset)
                let batch = llama_batch_get_one(buffer.baseAddress! + offset, Int32(chunk))
                let status = llama_decode(context, batch)
                guard status == 0 else { throw LlamaError.decodeFailed(status) }
                offset += chunk
            }
        }

        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(chain) }
        if let grammar {
            guard let grammarSampler = llama_sampler_init_grammar(vocab, grammar, "root") else {
                throw LlamaError.grammarParseFailed
            }
            llama_sampler_chain_add(chain, grammarSampler)
        }
        // Greedy decoding: verdicts should be deterministic, not creative.
        llama_sampler_chain_add(chain, llama_sampler_init_greedy())

        var output = ""
        for _ in 0..<maxTokens {
            var token = llama_sampler_sample(chain, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            output += piece(for: token)
            let batch = llama_batch_get_one(&token, 1)
            let status = llama_decode(context, batch)
            guard status == 0 else { break }
        }
        return output
    }

    // MARK: - Prompt assembly

    private func applyChatTemplate(system: String, user: String) -> String {
        let template = llama_model_chat_template(model, nil)
        guard let template else {
            return Self.chatML(system: system, user: user)
        }

        let systemC = strdup("system")!
        let userC = strdup("user")!
        let systemContent = strdup(system)!
        let userContent = strdup(user)!
        defer {
            free(systemC); free(userC); free(systemContent); free(userContent)
        }
        var messages = [
            llama_chat_message(role: UnsafePointer(systemC), content: UnsafePointer(systemContent)),
            llama_chat_message(role: UnsafePointer(userC), content: UnsafePointer(userContent)),
        ]

        var capacity = (system.utf8.count + user.utf8.count) * 2 + 512
        for _ in 0..<2 {
            var buffer = [CChar](repeating: 0, count: capacity)
            let written = llama_chat_apply_template(template, &messages, messages.count, true, &buffer, Int32(capacity))
            if written < 0 {
                return Self.chatML(system: system, user: user)
            }
            if Int(written) <= capacity {
                let bytes = buffer[0..<Int(written)].map { UInt8(bitPattern: $0) }
                return String(decoding: bytes, as: UTF8.self)
            }
            capacity = Int(written) + 1
        }
        return Self.chatML(system: system, user: user)
    }

    /// Fallback for models whose template llama.cpp cannot apply.
    static func chatML(system: String, user: String) -> String {
        """
        <|im_start|>system
        \(system)<|im_end|>
        <|im_start|>user
        \(user)<|im_end|>
        <|im_start|>assistant

        """
    }

    // MARK: - Token helpers

    private func tokenize(_ text: String) throws -> [llama_token] {
        let byteCount = text.utf8.count
        var tokens = [llama_token](repeating: 0, count: byteCount + 32)
        var count = llama_tokenize(vocab, text, Int32(byteCount), &tokens, Int32(tokens.count), true, true)
        if count < 0 && count != Int32.min {
            tokens = [llama_token](repeating: 0, count: Int(-count))
            count = llama_tokenize(vocab, text, Int32(byteCount), &tokens, Int32(tokens.count), true, true)
        }
        guard count > 0 else { throw LlamaError.tokenizationFailed }
        return Array(tokens.prefix(Int(count)))
    }

    private func piece(for token: llama_token) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        guard length > 0 else { return "" }
        let bytes = buffer[0..<Int(length)].map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
