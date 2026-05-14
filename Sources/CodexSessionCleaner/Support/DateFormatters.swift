import Foundation

enum SessionFormatters {
    static func updatedAtText(_ seconds: Int?) -> String {
        guard let seconds else {
            return "Unknown"
        }
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
