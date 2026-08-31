import SwiftUI
import UniformTypeIdentifiers

public struct MarkdownDocument: FileDocument {
    public static let markdownType = UTType(importedAs: "net.daringfireball.markdown")
    public static var readableContentTypes: [UTType] { [markdownType, .plainText] }

    public var text: String

    public init(text: String = "") {
        self.text = text
    }

    public init(data: Data) throws {
        if let string = String(data: data, encoding: .utf8) {
            text = string
        } else if let string = String(data: data, encoding: .isoLatin1) {
            text = string
        } else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try self.init(data: data)
    }

    public func data() -> Data {
        Data(text.utf8)
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data())
    }
}
