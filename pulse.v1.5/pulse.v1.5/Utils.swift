import SwiftUI
import UniformTypeIdentifiers

// MARK: - 文件导出辅助结构
struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var message: String
    
    init(message: String) {
        self.message = message
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        message = string
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = message.data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
