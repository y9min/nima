import Foundation

struct EmojiCatalogEntry: Identifiable, Equatable {
    let emoji: String
    let name: String
    let group: String
    let subgroup: String

    var id: String {
        "\(emoji)-\(name)"
    }

    var searchableText: String {
        "\(emoji) \(name) \(group) \(subgroup)".lowercased()
    }

    var isSkinToneVariant: Bool {
        searchableText.contains("skin tone")
            || emoji.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
    }
}

struct EmojiCatalogSection: Identifiable, Equatable {
    let group: String
    let entries: [EmojiCatalogEntry]

    var id: String {
        group
    }
}

enum EmojiCatalog {
    static let sections: [EmojiCatalogSection] = loadSections()

    static var groups: [String] {
        sections.map(\.group)
    }

    static func filteredSections(
        in sections: [EmojiCatalogSection] = EmojiCatalog.sections,
        query: String,
        selectedGroup: String?
    ) -> [EmojiCatalogSection] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return sections.compactMap { section in
            guard selectedGroup == nil || selectedGroup == section.group else { return nil }
            let baseEntries = section.entries.filter { !$0.isSkinToneVariant }
            let entries = normalizedQuery.isEmpty
                ? baseEntries
                : baseEntries.filter { $0.searchableText.contains(normalizedQuery) }
            return entries.isEmpty ? nil : EmojiCatalogSection(group: section.group, entries: entries)
        }
    }

    private static func loadSections() -> [EmojiCatalogSection] {
        let bundle = Bundle(for: EmojiCatalogBundleMarker.self)
        guard let url = bundle.url(forResource: "emoji_catalog", withExtension: "tsv"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return fallbackSections
        }

        var grouped: [(group: String, entries: [EmojiCatalogEntry])] = []
        for line in content.split(separator: "\n").dropFirst() {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count >= 4 else { continue }

            let entry = EmojiCatalogEntry(
                emoji: columns[0],
                name: columns[1],
                group: columns[2],
                subgroup: columns[3]
            )
            guard !entry.isSkinToneVariant else { continue }

            if let index = grouped.firstIndex(where: { $0.group == entry.group }) {
                grouped[index].entries.append(entry)
            } else {
                grouped.append((entry.group, [entry]))
            }
        }

        let sections = grouped.map { EmojiCatalogSection(group: $0.group, entries: $0.entries) }
        return sections.isEmpty ? fallbackSections : sections
    }

    private static let fallbackSections = [
        EmojiCatalogSection(
            group: "Objects",
            entries: [
                EmojiCatalogEntry(emoji: "⏰", name: "alarm clock", group: "Objects", subgroup: "time"),
                EmojiCatalogEntry(emoji: "💼", name: "briefcase", group: "Objects", subgroup: "office"),
                EmojiCatalogEntry(emoji: "📚", name: "books", group: "Objects", subgroup: "book-paper")
            ]
        )
    ]
}

private final class EmojiCatalogBundleMarker: NSObject {}
