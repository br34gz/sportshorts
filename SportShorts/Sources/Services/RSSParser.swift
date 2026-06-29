import Foundation

enum RSSParser {

    /// Raw video entry from a YouTube channel RSS feed — pre-classification.
    /// (The downstream FeedFetcher attaches sport/competition labels.)
    struct Entry {
        let id: String
        let title: String
        let channelTitle: String
        let publishedAt: Date
        let thumbnailURL: URL?
    }

    static func parse(_ data: Data, channel: YouTubeChannel) throws -> [Entry] {
        let delegate = FeedDelegate(fallbackChannelTitle: channel.name)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw NSError(domain: "RSSParser", code: 1, userInfo: [NSLocalizedDescriptionKey: parser.parserError?.localizedDescription ?? "XML parse failed"])
        }
        return delegate.items
    }

    private final class FeedDelegate: NSObject, XMLParserDelegate {
        var items: [Entry] = []
        let fallbackChannelTitle: String

        private var currentElement = ""
        private var currentText = ""
        private var inEntry = false
        private var entryId: String?
        private var entryTitle: String?
        private var entryAuthor: String?
        private var entryPublished: Date?
        private var entryThumbnail: URL?

        private static let iso8601: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f
        }()

        init(fallbackChannelTitle: String) {
            self.fallbackChannelTitle = fallbackChannelTitle
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
            currentElement = elementName
            currentText = ""
            if elementName == "entry" {
                inEntry = true
                entryId = nil; entryTitle = nil; entryAuthor = nil; entryPublished = nil; entryThumbnail = nil
            }
            if inEntry, elementName == "media:thumbnail", let urlStr = attributeDict["url"] {
                entryThumbnail = URL(string: urlStr)
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            currentText += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if inEntry {
                switch elementName {
                case "yt:videoId": entryId = text
                case "title": entryTitle = text
                case "name": entryAuthor = text
                case "published": entryPublished = FeedDelegate.iso8601.date(from: text)
                case "entry":
                    if let id = entryId, let title = entryTitle, let published = entryPublished {
                        items.append(Entry(
                            id: id,
                            title: title,
                            channelTitle: entryAuthor ?? fallbackChannelTitle,
                            publishedAt: published,
                            thumbnailURL: entryThumbnail ?? URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")
                        ))
                    }
                    inEntry = false
                default: break
                }
            }
            currentText = ""
        }
    }
}
