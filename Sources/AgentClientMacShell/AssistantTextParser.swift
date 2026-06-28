import AgentClientCore
import Foundation

// MARK: - AssistantTextParser

/// Scans assistant streaming text for thinking blocks, tool calls, and other
/// process-level markers that should be surfaced as TurnSteps.
///
/// This is an incremental parser: call `extractNewSteps(from:previousLength:)`
/// with the new total text and the length from the previous call — it only
/// scans the appended portion.
struct AssistantTextParser {

    /// Result from a parse pass.
    struct ParseResult {
        /// New steps discovered in this pass.
        let steps: [TurnStep]
        /// The text length at which this scan ended (pass back as `previousLength` next time).
        let scannedLength: Int
    }

    /// Patterns used to detect step boundaries in the assistant text.
    private static let thinkingOpen  = try! NSRegularExpression(pattern: "(?:<thinking>|<Thought>|【思考】|\\*\\*思考[：:]?)", options: [])
    private static let thinkingClose = try! NSRegularExpression(pattern: "(?:</thinking>|</Thought>|【/思考】|\\*\\*$)", options: [])
    private static let toolUseOpen   = try! NSRegularExpression(pattern: "(?:<tool[ _]use>|<function[ _]call>|\\*\\*工具[：:]|\\*\\*Tool[：:]|Tool Use[：:]|工具调用[：:]|---\\s*$)", options: [.caseInsensitive])
    private static let toolUseClose  = try! NSRegularExpression(pattern: "(?:</tool[ _]use>|</function[ _]call>|\\*\\*$|---)", options: [.caseInsensitive])

    /// Scan `text` for new thinking / tool-use blocks that start after `previousLength`.
    /// Returns any newly discovered steps.
    static func extractNewSteps(from text: String, previousLength: Int) -> ParseResult {
        guard text.count > previousLength else {
            return ParseResult(steps: [], scannedLength: text.count)
        }

        // Only scan the NEW portion to avoid re-detecting old markers.
        let startIdx = text.index(text.startIndex, offsetBy: min(previousLength, text.count))
        let newPortion = String(text[startIdx...])
        var steps: [TurnStep] = []

        // Check for thinking blocks — look for open marker anywhere in the text
        // but only report if it's new (in the new portion or spans the boundary).
        let range = NSRange(newPortion.startIndex..<newPortion.endIndex, in: newPortion)
        if let match = thinkingOpen.firstMatch(in: newPortion, range: range) {
            let contextStart = text.index(before: text.index(text.startIndex, offsetBy: previousLength + match.range.lowerBound))
            let snippetStart = max(text.startIndex, text.index(contextStart, offsetBy: -10))
            let snippet = String(text[snippetStart..<text.index(snippetStart, offsetBy: min(20, text.distance(from: snippetStart, to: text.endIndex)))])
            steps.append(TurnStep(kind: TurnStepKind.thinking, detail: "Thinking…", status: StepStatus.active))
            // Look for close marker in the new portion too
            if let _ = thinkingClose.firstMatch(in: newPortion, range: range) {
                steps.append(TurnStep(kind: TurnStepKind.thinking, detail: snippet, status: StepStatus.completed))
            }
        }

        // Check for tool use markers
        if let match = toolUseOpen.firstMatch(in: newPortion, range: range) {
            // Extract the tool name from context — look ahead for command/file name
            let contextEnd = min(newPortion.endIndex, text.index(newPortion.startIndex, offsetBy: match.range.location + match.range.length + 60))
            let context = String(newPortion[newPortion.startIndex..<contextEnd])
            let detail = extractToolDetail(from: context)
            steps.append(TurnStep(kind: TurnStepKind.toolCall, detail:detail, status: StepStatus.active))
            if let _ = toolUseClose.firstMatch(in: newPortion, range: range) {
                steps.append(TurnStep(kind: TurnStepKind.toolCall, detail:detail, status: StepStatus.completed))
            }
        }

        return ParseResult(steps: steps, scannedLength: text.count)
    }

    /// Try to extract a human-readable tool detail from the text around a marker.
    private static func extractToolDetail(from context: String) -> String {
        // Look for common patterns: read_file("path"), bash command, write, edit
        let patterns: [NSRegularExpression] = [
            try! NSRegularExpression(pattern: "['\"]([^'\"]+)['\"]"),               // quoted string
            try! NSRegularExpression(pattern: "read(?:_file|File)?\\s*[：(]?\\s*['\"]?([^)'\"]+)", options: [.caseInsensitive]),
            try! NSRegularExpression(pattern: "write(?:_file|File)?\\s*[：(]?\\s*['\"]?([^)'\"]+)", options: [.caseInsensitive]),
            try! NSRegularExpression(pattern: "edit(?:_file|File)?\\s*[：(]?\\s*['\"]?([^)'\"]+)", options: [.caseInsensitive]),
            try! NSRegularExpression(pattern: "`([^`]+)`", options: []),            // backtick command
            try! NSRegularExpression(pattern: "bash\\s+([^\\n,]+)", options: [.caseInsensitive]),
        ]

        for pattern in patterns {
            let range = NSRange(context.startIndex..<context.endIndex, in: context)
            if let match = pattern.firstMatch(in: context, range: range),
               let r = Range(match.range(at: 1), in: context) {
                let val = String(context[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !val.isEmpty { return val }
            }
        }

        let firstLine = context.split(separator: "\n").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return String(firstLine.prefix(50))
    }
}
