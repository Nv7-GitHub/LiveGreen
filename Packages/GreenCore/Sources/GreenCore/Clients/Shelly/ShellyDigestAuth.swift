import CryptoKit
import Foundation

/// HTTP Digest authentication as used by Shelly Gen2+ devices (RFC 7616, SHA-256, qop=auth,
/// username "admin", realm = device id).
struct ShellyDigestChallenge: Sendable, Hashable {
    var realm: String
    var nonce: String
    var qop: String?
    var algorithm: String
    var opaque: String?

    static let username = "admin"

    /// Parses a `WWW-Authenticate: Digest …` header.
    init?(header: String) {
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("digest ") else { return nil }
        let parameters = Self.parameters(String(trimmed.dropFirst("digest ".count)))
        guard let realm = parameters["realm"], let nonce = parameters["nonce"] else { return nil }
        self.realm = realm
        self.nonce = nonce
        self.qop = parameters["qop"]?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0 == "auth" } ?? parameters["qop"]
        self.algorithm = parameters["algorithm"] ?? "SHA-256"
        self.opaque = parameters["opaque"]
    }

    /// The `Authorization` header value for one request.
    func authorization(password: String, method: String, uri: String, cnonce: String, nonceCount: Int = 1) -> String {
        let nc = String(format: "%08x", nonceCount)
        let ha1 = Self.sha256Hex("\(Self.username):\(realm):\(password)")
        let ha2 = Self.sha256Hex("\(method):\(uri)")
        let response = qop == nil
            ? Self.sha256Hex("\(ha1):\(nonce):\(ha2)")
            : Self.sha256Hex("\(ha1):\(nonce):\(nc):\(cnonce):\(qop ?? "auth"):\(ha2)")
        var fields = [
            "username=\"\(Self.username)\"", "realm=\"\(realm)\"", "nonce=\"\(nonce)\"", "uri=\"\(uri)\"",
            "algorithm=\(algorithm)", "response=\"\(response)\"",
        ]
        if let qop { fields += ["qop=\(qop)", "nc=\(nc)", "cnonce=\"\(cnonce)\""] }
        if let opaque { fields.append("opaque=\"\(opaque)\"") }
        return "Digest " + fields.joined(separator: ", ")
    }

    static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Splits `key="value", key=value` pairs, respecting quoted commas.
    static func parameters(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var key = "", value = "", readingValue = false, quoted = false
        func commit() {
            let name = key.trimmingCharacters(in: .whitespaces).lowercased()
            if !name.isEmpty { result[name] = value.trimmingCharacters(in: .whitespaces) }
            key = ""; value = ""; readingValue = false
        }
        for character in text {
            switch character {
            case "\"": quoted.toggle()
            case "=" where !readingValue && !quoted: readingValue = true
            case "," where !quoted: commit()
            default:
                if readingValue { value.append(character) } else { key.append(character) }
            }
        }
        commit()
        return result
    }

    static func makeCNonce() -> String {
        (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}
