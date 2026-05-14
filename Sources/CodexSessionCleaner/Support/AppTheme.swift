import SwiftUI

enum AppTheme {
    static let appBackground = Color(nsColor: .windowBackgroundColor)
    static let sidebarBackground = Color(nsColor: .controlBackgroundColor)
    static let cardBackground = Color(nsColor: .textBackgroundColor)
    static let subtleFill = Color(nsColor: .quaternaryLabelColor).opacity(0.10)
    static let stroke = Color(nsColor: .separatorColor).opacity(0.45)
    static let primaryAccent = Color.accentColor
}
