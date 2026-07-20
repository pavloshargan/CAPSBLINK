import Foundation

/// GBNF grammar that constrains the model to emit exactly one JSON object of
/// the shape `{"notify": <bool>, "reason": "<short string>"}` — structured
/// output enforced at the sampler level, not by prompting alone.
public enum VerdictGrammar {
    public static let gbnf = #"""
    root ::= "{\"notify\": " boolean ", \"reason\": \"" content "\"}"
    boolean ::= "true" | "false"
    content ::= jchar{0,240}
    jchar ::= [^"\\\x00-\x1F\x7F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F])
    """#
}
