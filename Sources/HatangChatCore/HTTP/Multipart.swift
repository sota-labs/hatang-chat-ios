import Foundation

/// A `multipart/form-data` body with one file part.
enum Multipart {
    static func body(boundary: String, field: String, filename: String, contentType: String, data: Data) -> Data {
        let safeName = filename
            .replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        var b = Data()
        b.append(Data("--\(boundary)\r\n".utf8))
        b.append(Data("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(safeName)\"\r\n".utf8))
        b.append(Data("Content-Type: \(contentType)\r\n\r\n".utf8))
        b.append(data)
        b.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return b
    }
}
