import SwiftUI

struct SettingsScreen: View {
    @State private var defaultVisibility: DropVisibility = .public
    @State private var notifyNearby = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Defaults") {
                    Picker("Default visibility", selection: $defaultVisibility) {
                        ForEach(DropVisibility.allCases) { v in
                            Text(v.rawValue).tag(v)
                        }
                    }
                    Toggle("Notify me about nearby drops", isOn: $notifyNearby)
                }

                Section("Account") {
                    Button("Sign out") { /* hook later */ }
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
