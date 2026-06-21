import Foundation

public final class LineDelimitedJSONBuffer {
    private var buffer = Data()

    public init() {}

    public func append(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []

        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)

            guard let line = String(data: lineData, encoding: .utf8) else {
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                lines.append(trimmed)
            }
        }

        return lines
    }
}
