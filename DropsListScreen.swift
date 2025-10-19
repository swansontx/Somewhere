import SwiftUI

struct DropsListScreen: View {
    @EnvironmentObject var store: DropStore

    var body: some View {
        NavigationStack {
            List(store.drops) { drop in
                VStack(alignment: .leading, spacing: 6) {
                    Text(drop.text).font(.headline)
                    Text("\(drop.author.name) • \(drop.visibility.rawValue)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Drops")
        }
    }
}
