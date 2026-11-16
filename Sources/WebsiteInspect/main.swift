import Foundation
import WebsiteToolkit
struct Result: Encodable {
    let website: WebsiteAddress
    let title: String?
    let emails: [String]
    let phones: [String]
    let links: [WebsiteContentExtractor.PageLink]
    let social: SocialLinks
}
func main() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    if args == ["--help"] { print("Usage: website-inspect page.html --base-url https://example.com"); return }
    guard args.count == 3, args[1] == "--base-url", let address = WebsiteNormalizer.normalize(args[2], keepPath: true) else { throw NSError(domain:"Usage: website-inspect page.html --base-url https://example.com",code:1) }
    let data = try Data(contentsOf: URL(fileURLWithPath: args[0]))
    guard data.count <= 5_000_000, let html = String(data:data,encoding:.utf8) else { throw NSError(domain:"Expected UTF-8 HTML up to 5 MB",code:2) }
    let result = Result(website:address,title:WebsiteContentExtractor.title(in:html),emails:WebsiteContentExtractor.contactEmails(in:html),phones:WebsiteContentExtractor.contactPhones(in:html),links:WebsiteContentExtractor.importantLinks(in:html,baseURL:address.url),social:WebsiteContentExtractor.socialLinks(in:html,baseURL:address.url))
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
    print(String(decoding:try encoder.encode(result),as:UTF8.self))
}
do { try main() } catch { FileHandle.standardError.write(Data(("Error: \(error.localizedDescription)\n").utf8)); exit(1) }
