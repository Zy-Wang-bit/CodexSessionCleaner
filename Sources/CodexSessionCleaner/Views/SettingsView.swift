import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            LabeledContent("Deletion core") {
                Text(CodexCLIService.resolveScriptPath().path)
                    .textSelection(.enabled)
            }
            LabeledContent("Python") {
                Text("/usr/bin/env python3")
                    .textSelection(.enabled)
            }
        }
        .padding()
        .frame(width: 560)
    }
}
