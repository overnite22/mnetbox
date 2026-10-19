import Foundation

enum L10n {
    static func text(_ key: String) -> String { Bundle.main.localizedString(forKey: key, value: key, table: nil) }
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }
    /// NetBox IDs are identifiers, not quantities: never apply digit grouping (#7001, not #7,001).
    static func identifier(_ key: String, _ id: Int) -> String {
        String(format: text(key), id)
    }
}
