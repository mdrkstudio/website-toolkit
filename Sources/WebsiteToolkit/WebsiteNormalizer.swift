import Foundation
public struct WebsiteAddress: Codable, Sendable {
    public let url: URL
    public let domain: String
}
public enum WebsiteNormalizer {
    /// Canonical homepage by default. Use keepPath to retain path and non-tracking query items.
    public static func normalize(_ raw: String, keepPath: Bool = false) -> WebsiteAddress? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !input.contains(where: { $0.isWhitespace }), !input.contains("\\") else { return nil }
        let candidate: String
        if input.hasPrefix("//") { candidate = "https:" + input }
        else if input.contains("://") { candidate = input }
        else if input.contains(":") && !input.contains(":80") && !input.contains(":443") { return nil }
        else { candidate = "https://" + input }
        guard var c = URLComponents(string: candidate), let scheme = c.scheme?.lowercased(), ["https","http"].contains(scheme), var host = c.host?.lowercased(), !host.isEmpty, c.user == nil, c.password == nil else { return nil }
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        if host.hasSuffix(".") { host.removeLast() }
        guard host.contains("."), !host.hasPrefix("."), !host.contains(".."), host.split(separator: ".").allSatisfy({ !$0.hasPrefix("-") && !$0.hasSuffix("-") }) else { return nil }
        c.scheme = scheme; c.host = host; c.fragment = nil
        if c.port == (scheme == "https" ? 443 : 80) { c.port = nil }
        if !keepPath { c.path = ""; c.query = nil }
        else {
            c.queryItems = c.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") && !["gclid","fbclid","yclid"].contains($0.name.lowercased()) }
            if c.queryItems?.isEmpty == true { c.query = nil }
        }
        guard let url = c.url else { return nil }
        return WebsiteAddress(url: url, domain: host)
    }
}
