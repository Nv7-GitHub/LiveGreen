import CryptoKit
import Foundation

/// HTTP digest auth as used by Shelly Gen2+ (RFC 7616, SHA-256, user "admin").
nonisolated struct ShellyDigestAuth: Sendable {
    var realm: String
    var nonce: String
    var qop: String?
    var opaque: String?

    /// Parses a `WWW-Authenticate: Digest realm="…", nonce="…", qop="auth", algorithm=SHA-256` header.
    init?(challenge header: String) {
        guard header.lowercased().hasPrefix("digest") else { return nil }
        var fields: [String: String] = [:]
        let pattern = /(\w+)=(?:"([^"]*)"|([^\s,]+))/
        for match in header.dropFirst(6).matches(of: pattern) {
            fields[String(match.1).lowercased()] = String(match.2 ?? match.3 ?? "")
        }
        guard let realm = fields["realm"], let nonce = fields["nonce"] else { return nil }
        self.realm = realm
        self.nonce = nonce
        self.qop = fields["qop"]
        self.opaque = fields["opaque"]
    }

    /// The `Authorization` header for one request.
    func authorization(method: String, uri: String, password: String,
                       username: String = "admin", cnonce: String = UUID().uuidString) -> String {
        let ha1 = Self.sha256("\(username):\(realm):\(password)")
        let ha2 = Self.sha256("\(method):\(uri)")
        let nc = "00000001"
        var parts = ["username=\"\(username)\"", "realm=\"\(realm)\"", "nonce=\"\(nonce)\"",
                     "uri=\"\(uri)\"", "algorithm=SHA-256"]
        if qop != nil {
            let response = Self.sha256("\(ha1):\(nonce):\(nc):\(cnonce):auth:\(ha2)")
            parts += ["response=\"\(response)\"", "qop=auth", "nc=\(nc)", "cnonce=\"\(cnonce)\""]
        } else {
            parts.append("response=\"\(Self.sha256("\(ha1):\(nonce):\(ha2)"))\"")
        }
        if let opaque { parts.append("opaque=\"\(opaque)\"") }
        return "Digest " + parts.joined(separator: ", ")
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
