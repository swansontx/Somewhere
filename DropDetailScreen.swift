import SwiftUI

struct DropDetailScreen: View, Identifiable {
    @EnvironmentObject var store: DropStore
    let id = UUID()
    let drop: DropItem

    var body: some View {
        VStack(spacing: 12) {
            Capsule().fill(.secondary.opacity(0.3)).frame(width: 40, height: 5).padding(.top, 8)

            Text(drop.text)
                .font(.title3).bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("\(drop.author.name) • \(drop.visibility.rawValue) • \(drop.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button {
                    store.react(to: drop)
                } label: {
                    Label("\(drop.reactions)", systemImage: "heart.fill")
                }

                Button {
                    store.toggleLift(drop)
                } label: {
                    Label(drop.isLiftedByCurrentUser ? "Lifted" : "Lift", systemImage: "arrow.up.heart")
                }

                Button {
                    // placeholder for replies
                } label: {
                    Label("Reply", systemImage: "text.bubble")
                }
            }
            .buttonStyle(.bordered)
            .padding(.top, 6)

            Spacer()
        }
        .presentationDetents([.medium, .large])
        .padding()
    }
}
