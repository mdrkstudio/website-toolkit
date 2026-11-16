import Foundation

public enum WebsiteContentExtractor {
    public struct PageLink: Hashable, Codable, Sendable {
        public let url: URL
        public let kind: String
    }

    public static func emails(in text: String) -> [String] {
        // Scan around @, never retry an unbounded regex at every byte of a base64/script blob.
        let bytes = Array(text.utf8)
        func alpha(_ b: UInt8) -> Bool { (65...90).contains(b) || (97...122).contains(b) }
        func digit(_ b: UInt8) -> Bool { (48...57).contains(b) }
        func local(_ b: UInt8) -> Bool { alpha(b) || digit(b) || [46, 95, 37, 43, 45].contains(b) }
        func domain(_ b: UInt8) -> Bool { alpha(b) || digit(b) || b == 46 || b == 45 }
        var result: [String] = []
        var seen = Set<String>()
        for at in bytes.indices where bytes[at] == 64 {
            var start = at
            while start > 0 && at - start <= 64 && local(bytes[start - 1]) { start -= 1 }
            var end = at + 1
            while end < bytes.count && end - at <= 254 && domain(bytes[end]) { end += 1 }
            guard start < at, at - start <= 64, end > at + 1, end - start <= 254 else { continue }
            while end > at + 1 && bytes[end - 1] == 46 { end -= 1 }
            let name = String(decoding: bytes[start..<at], as: UTF8.self)
            let host = String(decoding: bytes[(at + 1)..<end], as: UTF8.self).lowercased()
            let labels = host.split(separator: ".", omittingEmptySubsequences: false)
            guard !name.hasPrefix("."), !name.hasSuffix("."), !name.contains(".."),
                  !name.lowercased().hasPrefix("u003e"), labels.count >= 2,
                  labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-") }),
                  let tld = labels.last, (2...24).contains(tld.count), tld.utf8.allSatisfy(alpha),
                  !["png", "jpg", "jpeg", "gif", "webp", "svg", "css", "js"].contains(String(tld)) else { continue }
            let email = name.lowercased() + "@" + host
            if seen.insert(email).inserted { result.append(email) }
        }
        return result
    }

    public static func phones(in text: String) -> [String] {
        matches(#"(?:\+7|8)[\s\-\(\)]{0,12}\d{3}[\s\-\(\)]{0,12}\d{3}[\s\-]{0,12}\d{2}[\s\-]{0,12}\d{2}"#, in: text)
            .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) }
            .uniqued()
    }

    public static func title(in html: String) -> String? {
        guard let match = firstMatch(#"<title[^>]{0,512}>(.{0,4096}?)</title>"#, in: html, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        return plainText(from: match).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func plainText(from html: String) -> String {
        // Single forward pass, including malformed/unterminated tags. No regex backtracking.
        let bytes = Array(html.utf8)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = 0
        var hiddenTag: String?
        while index < bytes.count {
            if bytes[index] != 60 {
                if hiddenTag == nil { output.append(bytes[index]) }
                index += 1
                continue
            }
            index += 1
            let closing = index < bytes.count && bytes[index] == 47
            if closing { index += 1 }
            let nameStart = index
            while index < bytes.count && ((65...90).contains(bytes[index]) || (97...122).contains(bytes[index])) { index += 1 }
            let name = String(decoding: bytes[nameStart..<min(index, nameStart + 16)], as: UTF8.self).lowercased()
            var quote: UInt8?
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if let current = quote { if byte == current { quote = nil } }
                else if byte == 34 || byte == 39 { quote = byte }
                else if byte == 62 { break }
            }
            if closing && name == hiddenTag { hiddenTag = nil }
            else if !closing && hiddenTag == nil && ["script", "style"].contains(name) { hiddenTag = name }
            if hiddenTag == nil { output.append(32) }
        }
        var value = String(decoding: output, as: UTF8.self)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&quot;": "\"", "&#39;": "'", "&lt;": "<", "&gt;": ">"]
        for (entity, replacement) in entities { value = value.replacingOccurrences(of: entity, with: replacement) }
        return value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func importantLinks(in html: String, baseURL: URL, limit: Int = 7) -> [PageLink] {
        let rawLinks = matches(#"href\s{0,16}=\s{0,16}[\"']([^\"']{1,4096})[\"']"#, in: html, options: [.caseInsensitive], captureGroup: 1)
        let baseHost = normalizedHost(baseURL.host)
        let keywords: [(String, String, Int)] = [
            ("contact", "Контакты", 0), ("kontakt", "Контакты", 0), ("kontakty", "Контакты", 0),
            ("about", "О компании", 1), ("o-komp", "О компании", 1), ("company", "О компании", 1),
            ("requisite", "Реквизиты", 2), ("rekviz", "Реквизиты", 2),
            ("partner", "Партнёрам", 3), ("opt", "Оптовикам", 3), ("dealer", "Дилерам", 3),
            ("delivery", "Доставка", 4), ("dostav", "Доставка", 4)
        ]

        var candidates: [(PageLink, Int)] = []
        var seen = Set<String>()
        for raw in rawLinks {
            guard let url = URL(string: raw.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: baseURL)?.absoluteURL,
                  url.user == nil, url.password == nil,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  normalizedHost(url.host) == baseHost else { continue }
            let lower = url.path.lowercased()
            guard !["css", "js", "png", "jpg", "jpeg", "svg", "gif", "webp", "pdf", "zip", "woff", "woff2"].contains(url.pathExtension.lowercased()) else { continue }
            guard let keyword = keywords.first(where: { lower.contains($0.0) }) else { continue }
            // Tracking/anchor variants of Contact/About are not extra pages to download.
            var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
            components?.fragment = nil
            let filteredQuery = components?.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") && !["yclid", "gclid", "fbclid"].contains($0.name.lowercased()) }
            components?.queryItems = filteredQuery
            if components?.queryItems?.isEmpty == true { components?.queryItems = nil }
            let canonical = components?.url?.absoluteString ?? url.deletingFragment().absoluteString
            guard seen.insert(canonical).inserted else { continue }
            candidates.append((PageLink(url: URL(string: canonical) ?? url, kind: keyword.1), keyword.2))
        }
        return candidates.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0)
    }

    public static func socialLinks(in html: String, baseURL: URL) -> SocialLinks {
        var result = SocialLinks()
        let rawLinks = matches(#"href\s{0,16}=\s{0,16}[\"']([^\"']{1,4096})[\"']"#, in: html, options: [.caseInsensitive], captureGroup: 1)
        for raw in rawLinks {
            guard let value = URL(string: raw, relativeTo: baseURL)?.absoluteURL.absoluteString else { continue }
            SocialLinkClassifier.insert(value, into: &result)
        }
        return result
    }

    public static func contactEmails(in html: String) -> [String] {
        let links = matches(#"href\s{0,16}=\s{0,16}["']mailto:([^"']{1,4096})["']"#, in: html, options: [.caseInsensitive], captureGroup: 1)
        let addresses = links.flatMap { raw in emails(in: String(raw.split(separator: "?", maxSplits: 1).first ?? "").removingPercentEncoding ?? raw) }
        return (emails(in: plainText(from: html)) + addresses).uniqued()
    }

    public static func contactPhones(in html: String) -> [String] {
        let links = matches(#"href\s{0,16}=\s{0,16}["']tel:([^"']{1,4096})["']"#, in: html, options: [.caseInsensitive], captureGroup: 1)
        return (phones(in: plainText(from: html)) + links.flatMap { phones(in: $0.removingPercentEncoding ?? $0) }).uniqued()
    }

    private static func matches(
        _ pattern: String,
        in text: String,
        options: NSRegularExpression.Options = [],
        captureGroup: Int = 0
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard match.numberOfRanges > captureGroup, let range = Range(match.range(at: captureGroup), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func firstMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func normalizedHost(_ host: String?) -> String {
        let value = (host ?? "").lowercased()
        return value.hasPrefix("www.") ? String(value.dropFirst(4)) : value
    }
}

private extension URL {
    func deletingFragment() -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else { return self }
        components.fragment = nil
        return components.url ?? self
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
