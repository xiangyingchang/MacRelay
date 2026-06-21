import AgentClientCore
import Foundation

let detection = CodexCLIDetector.detect()

print("installed=\(detection.isInstalled)")
print("path=\(detection.executablePath ?? "")")
print("version=\(detection.version ?? "")")
if let error = detection.errorMessage {
    print("error=\(error)")
}
