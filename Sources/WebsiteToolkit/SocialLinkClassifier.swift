import Foundation
public struct SocialLinks: Codable, Sendable {
    public var telegram: [String] = []
    public var whatsapp: [String] = []
    public var vk: [String] = []
    public var ok: [String] = []
    public var max: [String] = []
    public init() {}
}
public enum SocialChannel: String, Codable, Sendable { case telegram, whatsapp, vk, ok, max }
public enum SocialLinkClassifier {
    public static func channel(for rawURL: String) -> SocialChannel? {
        let value = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = value.contains("://") ? value : "https://" + value
        guard let c = URLComponents(string: candidate), ["https","http"].contains(c.scheme?.lowercased() ?? ""), c.user == nil, c.password == nil, let host = c.host?.lowercased() else { return nil }
        let hosts: [(SocialChannel,[String])] = [(.telegram,["t.me","telegram.me"]),(.whatsapp,["wa.me","whatsapp.com"]),(.vk,["vk.com","vk.ru"]),(.ok,["ok.ru"]),(.max,["max.ru"])]
        return hosts.first { _, domains in domains.contains { host == $0 || host.hasSuffix("." + $0) } }?.0
    }
    @discardableResult public static func insert(_ value: String, into links: inout SocialLinks) -> Bool {
        guard let channel = channel(for: value) else { return false }
        switch channel {
        case .telegram: if !links.telegram.contains(value) { links.telegram.append(value) }
        case .whatsapp: if !links.whatsapp.contains(value) { links.whatsapp.append(value) }
        case .vk: if !links.vk.contains(value) { links.vk.append(value) }
        case .ok: if !links.ok.contains(value) { links.ok.append(value) }
        case .max: if !links.max.contains(value) { links.max.append(value) }
        }
        return true
    }
}
